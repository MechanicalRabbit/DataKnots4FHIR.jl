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

Attributes =
  It.snapshot >> Is(Dict) >>
  It.element >> Is(Vector) >> Is(Dict) >>
  Filter(It.max >> String .!= "0") >>
  Record(
    It.id >> Is(String),
    It.path >> Is(String),
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
      :first => Attributes >> Take(1) >> Is1to1,
      :elements => Attributes >> Drop(1) >>
         Collect(
           :id => replace.(It.id, Pair.(It.prefix, ""))
         )
    )
  )

function verify_profiles(knot)
    IsDefinition = It.resourceType .!== "StructureDefinition"
    @assert(0 == length(get(knot[Filter(It.type .!== It.first.path)])))
    @assert(0 == length(get(knot[Filter(IsDefinition)])))
end

function profiles()
    knot = convert(DataKnot, load_json(".profile.json"))[UnpackProfiles]
    verify_profiles(knot)
    return knot
end

function examples()
    data = Dict{String, DataKnot}()
    for item in load_json("-example.json")
       rtype = item["resourceType"]
       data[item["fileName"]] = convert(DataKnot, item)
    end
    return data
end
