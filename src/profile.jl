using Pkg.Artifacts
using JSON

IsInt       = Is(Int)
IsBool      = Is(Bool)
IsDict      = Is(Dict{String, Any})
IsString    = Is(String)
IsVector    = Is(Vector{Any})
IsOptInt    = Is(Union{Int, Missing})
IsOptBool   = Is(Union{Bool, Missing})
IsOptDict   = Is(Union{Dict{String, Any}, Missing})
IsOptString = Is(Union{String, Missing})
IsOptVector = Is(Union{Vector{Any}, Missing})

mutable struct Context
   seen::Vector{Symbol}
   flatten::Bool
end
Context() = Context(Vector{Symbol}(), false)

profile_registry = Dict{Symbol, DataKnot}()
example_registry = Dict{Tuple{Symbol, Symbol}, DataKnot}()
primitive_registry = Dict{Symbol, Type}()
flatten_profile = (:extension, )

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
  It.snapshot >> IsDict >>
  It.element >> IsVector >> IsDict >>
  Filter((It.max >> IsString) .!= "0") >>
  Record(
    :base => get_base.(It.path),
    :name => get_name.(It.path),
    :mandatory => ((It.min >> IsInt) .!== 0) .&
                   (.! contains.(It.path, "[x]")),
    :singular => ((It.max >> IsString) .== "1"),
    :type =>
      It.type >> IsOptVector >>
      IsVector >> IsDict >>
      Record(
        :code => It.code >> IsString,
        :extension => It.extension >> IsOptVector >>
          IsVector >> IsDict >>
          Record(
            :valueUrl => It.valueUrl >> IsOptString,
            :url => It.url >> IsString,
            :valueBoolean => It.valueBoolean >> IsOptBool
          )
      )
  )

function compute_card(singular::Bool, mandatory::Bool,
                      basetype::Type)::DataKnots.AbstractQuery
    if mandatory
        if singular
            return Is(basetype) >> Is1to1
        end
        return IsVector >> Is(basetype) >> Is1toN
    end
    if singular
        return Is(Union{Missing, basetype}) >> Is0to1
    end
    return coalesce.(It, Ref([])) >> IsVector >> Is(basetype) >> Is0toN
end

function make_field_type(ctx::Context, code::String, singular::Bool,
                         mandatory::Bool)::DataKnots.AbstractQuery
    code = Symbol(lowercase(code))
    if haskey(primitive_registry, code)
        return compute_card(singular, mandatory, primitive_registry[code])
    end
    if haskey(profile_registry, code)
        if ctx.flatten || code in ctx.seen || code == :resource
            return compute_card(singular, mandatory, Dict)
        end
        profile = profile_registry[code]
        #println("[", "  " ^ length(ctx.seen), code, ctx.seen)
        push!(ctx.seen, code)
        ctx.flatten = code in flatten_profile
        Nested = build_profile(ctx, profile[It.elements],
                               get(profile[It.id]))
        ctx.flatten = false
        @assert code == pop!(ctx.seen)
        #println("]", "  " ^ length(ctx.seen), code, ctx.seen)
        return compute_card(singular, mandatory, Dict) >> Nested
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
    :prefix => string.(It.type >> IsString, "."),
    Record(
      It.id >> IsString,
      It.type >> IsString,
      It.resourceType >> IsString,
      It.kind >> IsString,
      :base => It.baseDefinition >> IsOptString >>
         replace.(It, "http://hl7.org/fhir/StructureDefinition/" => ""),
      :elements => Attributes >> Drop(1)
    )
  )

function build_profile(ctx::Context, elements::DataKnot, base::String,
                       top::Bool = false)
    fields = DataKnots.AbstractQuery[]
    if top
        push!(fields, Get(:resourceType) >> IsString)
    end
    for row in get(elements[Filter(It.base .== base) >> UnpackFields(ctx)])
       if row[:label] == :extension
           continue  # TODO: enable extension recursion smartly
       end
       push!(fields, Get(row[:label]) >> row[:query] >> Label(row[:label]))
    end
    for row in get(elements[Filter(It.base .== base) >>
                       Filter(It.type >> (It.code .== "BackboneElement"))])
        Nested = build_profile(ctx, elements, "$(base).$(row[:name])")
        Card = compute_card(row[:singular], row[:mandatory], Dict)
        push!(fields, Get(Symbol(row[:name])) >> Card >> Nested >>
                                                 Label(Symbol(row[:name])))
    end
    return Record(fields...)
end

function load_profile_registry()
    for item in load_json(".profile.json")
        handle = Symbol(lowercase(item["id"]))
        if item["kind"] != "primitive-type"
            @assert !haskey(profile_registry, handle)
            profile_registry[handle] =
                convert(DataKnot, item)[UnpackProfiles]
            continue
        end
        @assert !haskey(primitive_registry, handle)
        lookup = Dict{Symbol, DataType}(
           :string => String,
           :boolean => Bool,
           :integer => Int,
           :code => String,
           :uri => String,
           :text => String)
        primitive_registry[handle] = get(lookup, handle, Any)
    end
end

function FHIRProfile(version::Symbol, resourceType::String)
    @assert version == :R4
    if length(profile_registry) == 0
       load_profile_registry()
    end
    meta = profile_registry[Symbol(lowercase(resourceType))]
    return IsDict >>
           Filter((It.resourceType >> IsString) .== resourceType) >>
           build_profile(Context(), meta[It.elements],
                         get(meta[It.id]), true) >>
           Label(Symbol(resourceType))
end

function load_example_registry()
    conflicts = Set{Tuple{Symbol, Symbol}}()
    for item in load_json("-example.json")
        if haskey(item, "id")
            handle = (Symbol(lowercase(item["resourceType"])),
                      Symbol(lowercase(item["id"])))
            if haskey(example_registry, handle)
                push!(conflicts, handle)
            else
                example_registry[handle] = convert(DataKnot, item)
            end
        end
    end
    # unregister resource examples with duplicate identifiers
    for item in conflicts
        pop!(example_registry, item)
    end
end

function FHIRExample(version::Symbol, resourceType::String, id::String)
    @assert version == :R4
    if length(example_registry) == 0
       load_example_registry()
    end
    return example_registry[(Symbol(lowercase(resourceType)),
                             Symbol(lowercase(id)))]
end

function FHIRSpecificationInventory(version::Symbol)
    @assert version == :R4
    inventory = Dict{String, Vector{String}}()
    for resourceType in keys(profile_registry)
         examples = Vector{String}()
         for (rt, id) in keys(example_registry)
             if rt == resourceType
                 push!(examples, String(id))
             end
         end
         inventory[String(resourceType)] = examples
    end
    return inventory
end

function regression()
    load_profile_registry()
    inventory = FHIRSpecificationInventory(:R4)
    for profile in keys(inventory)
        println(profile)
        Q = FHIRProfile(:R4, profile)
        for ident in inventory[profile]
            println(profile, " ", ident)
            ex = FHIRExample(:R4, profile, ident)
            try
               ex[Q]
            catch e
               println(profile, " ", ident, " ! " , e)
            end
        end
    end
end
