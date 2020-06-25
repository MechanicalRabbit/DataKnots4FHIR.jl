using Pkg.Artifacts
using JSON

function load_json(postfix)
    items = Dict{String, Any}[]
    for fname in readdir(joinpath(artifact"fhir-r4", "fhir-r4"))
        if !endswith(fname, postfix)
            continue
        end
        item = JSON.parsefile(joinpath(artifact"fhir-r4", "fhir-r4", fname))
        item["fileName"] = chop(fname, tail=length(postfix))
        push!(items, item)
    end
    return items
end

function determine_cardinality(min::Integer, max::String)
    if min == 0
        if max == "1"
            return Is0to1
        else
            return Is0toN
        end
    else
        if max == "1"
            return Is1to1
        else
            return Is1toN
        end
    end
end

get_base(path::String) = join(split(path, ".")[1:end-1],".")
get_name(path::String) = replace(split(path, ".")[end], "[x]" => "")

Attributes =
  It.snapshot >> Is(Dict) >>
  It.element >> Is(Vector) >> Is(Dict) >>
  Filter(It.max >> String .!= "0") >>
  Record(
    :base => get_base.(It.path),
    :name => get_name.(It.path),
    :card => determine_cardinality.(It.min, It.max),
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

make_field_label(name::String, is_plural::Bool, code::String) = 
  Symbol(is_plural ? "$(name)$(uppercase(code)[1])$(code[2:end])" : name)

function make_field_type(code::String)::DataKnots.AbstractQuery
  lookup = Dict{String, DataKnots.AbstractQuery}( 
     "string" => Is(String),
     "boolean" => Is(Bool),
     "integer" => Is(Int),
     "code" => Is(String),
     "uri" => Is(String),
     "text" => Is(String)
  )
  return get(lookup, code, It)
end

UnpackFields = 
  Filter("BackboneElement" .∉  It.type.code) >>
  Given(
    :is_plural => Count(It.type) .> 1,
    :name => It.name,
    :card => It.card,
    It.type >>
      Record(
        :label => make_field_label.(It.name, It.is_plural, It.code),
        :type => make_field_type.(It.code),
        It.card,
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

function profile(name)
    fname = "$(lowercase(name)).profile.json"
    item = JSON.parsefile(joinpath(artifact"fhir-r4", "fhir-r4", fname))
    knot = convert(DataKnot, item)[UnpackProfiles]
    return knot
end

function build_record(elements::DataKnot, base::String)
    fields = DataKnots.AbstractQuery[]
    for row in get(elements[Filter(It.base .== base) >> UnpackFields])
       push!(fields, Get(row[:label]) >> row[:type] >> 
                       row[:card] >> Label(row[:label]))
    end
    for row in get(elements[Filter(It.base .== base) >>
                       Filter(It.type >> (It.code .== "BackboneElement"))])
        nested = build_record(elements, "$(base).$(row[:name])")
        push!(fields, nested >> row[:card] >> Label(Symbol(row[:name])))
    end
    return Is(Dict) >> Record(fields...)
end 

function build_record(resourceType::String)
    meta = profile(resourceType)
    return build_record(meta[It.elements], get(meta[It.id])) >> 
             Label(Symbol(resourceType))
end

function example(name)
    fname = "$(lowercase(name))-example.json"
    item = JSON.parsefile(joinpath(artifact"fhir-r4", "fhir-r4", fname))
    return convert(DataKnot, item)[build_record(item["resourceType"])]
end

