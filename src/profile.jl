using Pkg.Artifacts
using JSON

mutable struct Context
   depth::Int
end

profiles = Dict{Symbol, DataKnot}()
primitives = Dict{Symbol, Type}()

function load_json(postfix)
    items = Dict{String, Any}[]
    for fname in readdir(joinpath(artifact"fhir-r4", "fhir-r4"))
        if !endswith(fname, postfix)
            continue
        end
        item = JSON.parsefile(joinpath(artifact"fhir-r4", "fhir-r4", fname))
        item["handle"] = Symbol(lowercase(chop(fname, tail=length(postfix))))
        push!(items, item)
    end
    return items
end

get_base(path::String) = join(split(path, ".")[1:end-1],".")
get_name(path::String) = replace(split(path, ".")[end], "[x]" => "")

make_field_label(name::String, is_variant::Bool, code::String) =
  Symbol(is_variant ? "$(name)$(uppercase(code)[1])$(code[2:end])" : name)

Attributes =
  It.snapshot >> Is(Dict) >>
  It.element >> Is(Vector) >> Is(Dict) >>
  Filter(It.max >> String .!= "0") >>
  Record(
    :base => get_base.(It.path),
    :name => get_name.(It.path),
    :mandatory => ((It.min >> Is(Int)) .!== 0),
    :singular => ((It.max >> Is(String)) .== "1"),
    :type =>
      It.type >> Is(Union{Vector, Missing}) >>
      Is(Vector) >> Is(Dict) >>
      Record(
        :code => It.code >> Is(String),
        :extension => It.extension >> Is(Union{Vector, Missing}) >>
          Is(Vector) >> Is(Dict) >>
          Record(
            :valueUrl => It.valueUrl >> Is(Union{String, Missing}),
            :url => It.url >> Is(String),
            :valueBoolean => It.valueBoolean >> Is(Union{Bool, Missing})
          )
      )
  )

function compute_card(singular::Bool, mandatory::Bool,
                      basetype::Type)::DataKnots.AbstractQuery
    if mandatory
        if singular
            return Is(basetype) >> Is1to1
        end
        return Is(Vector) >> Is(basetype) >> Is1toN
    end
    if singular
        return Is(Union{Missing, basetype}) >> Is0to1
    end
    return coalesce.(It, Ref([])) >> Is(Vector) >> Is(basetype) >> Is0toN
end

function make_field_type(ctx::Context, code::String, singular::Bool,
                         mandatory::Bool)::DataKnots.AbstractQuery
    code = Symbol(lowercase(code))
    if haskey(primitives, code)
        return compute_card(singular, mandatory, primitives[code])
    end
    if haskey(profiles, code)
        profile = profiles[code]
        return compute_card(singular, mandatory, Dict) >>
                 build_query(ctx, profile[It.elements],
                             get(profile[It.id]))
    end
    return compute_card(singular, mandatory, Any)
end

UnpackFields(ctx::Context) =
  Filter("BackboneElement" .∉  It.type.code) >>
  Given(
    :is_variant => Count(It.type) .> 1,
    It.name, It.singular, It.mandatory,
    It.type >>
      Record(
        :label => make_field_label.(It.name, It.is_variant, It.code),
        :query => make_field_type.(Ref(ctx), It.code,
                                   It.singular, It.mandatory)
      )
  )

UnpackProfiles =
  Given(
    :prefix => string.(It.type >> Is(String), "."),
    Record(
      It.id >> Is(String),
      It.type >> Is(String),
      It.resourceType >> Is(String),
      It.kind >> Is(String),
      :base => It.baseDefinition >> Is(Union{String, Missing}) >>
         replace.(It, "http://hl7.org/fhir/StructureDefinition/" => ""),
      :elements => Attributes >> Drop(1)
    )
  )

function verify_profiles(knot)
    IsDefinition = It.resourceType .!== "StructureDefinition"
    @assert(0 == length(get(knot[Filter(IsDefinition)])))
end

function profiles()
    knot = convert(DataKnot, load_json(".profile.json"))[UnpackProfiles]
    verify_profiles(knot)
    return knot
end

profile(name) = get(profiles, Symbol(lowercase(String(name))), missing)

function build_query(ctx::Context, elements::DataKnot, base::String)
    fields = DataKnots.AbstractQuery[]
    if ctx.depth > 3
        return It
    else
        ctx.depth = ctx.depth + 1
    end
    for row in get(elements[Filter(It.base .== base) >> UnpackFields(ctx)])
       if row[:label] == :extension
           continue  # TODO: enable extension recursion smartly
       end
       push!(fields, Get(row[:label]) >> row[:query] >> Label(row[:label]))
    end
    for row in get(elements[Filter(It.base .== base) >>
                       Filter(It.type >> (It.code .== "BackboneElement"))])
        Nested = build_query(ctx, elements, "$(base).$(row[:name])")
        Card = compute_card(row[:singular], row[:mandatory], Dict)
        push!(fields, Get(Symbol(row[:name])) >> Card >> Nested >>
                                                 Label(Symbol(row[:name])))
    end
    ctx.depth = ctx.depth -1
    return Is(Dict) >> Record(fields...)
end

function build_query(resourceType)
    meta = profiles[Symbol(lowercase(String(resourceType)))]
    return build_query(Context(0), meta[It.elements], get(meta[It.id])) >>
             Label(Symbol(resourceType))
end

function path(name)
    fname = "$(lowercase(name))-example.json"
    return joinpath(artifact"fhir-r4", "fhir-r4", fname)
end

function example(name)
    fname = "$(lowercase(name))-example.json"
    item = JSON.parsefile(joinpath(artifact"fhir-r4", "fhir-r4", fname))
    return convert(DataKnot, item)
end

for item in load_json(".profile.json")
    if item["kind"] != "primitive-type"
        @assert !haskey(profiles, item["handle"])
        profiles[item["handle"]] = convert(DataKnot, item)[UnpackProfiles]
        continue
    end
    @assert !haskey(primitives, item["handle"])
    lookup = Dict{Symbol, DataType}(
       :string => String,
       :boolean => Bool,
       :integer => Int,
       :code => String,
       :uri => String,
       :text => String)
    primitives[item["handle"]] = get(lookup, item["handle"], Any)
end;
