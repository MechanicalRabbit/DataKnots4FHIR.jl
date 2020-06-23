using Pkg.Artifacts
using JSON

function load_profiles()
    items = Dict{String, Any}[]
    for fname in readdir(joinpath(artifact"fhir-r4", "fhir-r4"))
        if !endswith(fname, ".profile.json")
            continue
        end
        item = JSON.parsefile(joinpath(artifact"fhir-r4", "fhir-r4", fname))
        @assert(item["resourceType"] == "StructureDefinition")
        push!(items, item)
    end
    return convert(DataKnot, items)
end

Attributes =
  It.snapshot >> Is(Dict) >>
  It.element >> Is(Vector) >> Is(Dict) >>
  Given(
    :min => It.min >> convert.(Unsigned, It),
    :max => It.max >> Is(String),
    Record(
      :id => It.id >> Is(String),
      :path => It.path >> Is(String),
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
  )

UnpackProfile =
  Given(
    :prefix => string.(It.type >> Is(String), "."),
    Record(
      :id => It.id >> Is(String),
      :type => It.type >> Is(String),
      :kind => It.kind >> Is(String),
      :base => It.baseDefinition >> Is(Union{String, Missing}) >>
         replace.(It, "http://hl7.org/fhir/StructureDefinition/" => ""),
      :first => Attributes >> Take(1) >> Is1to1,
      :elements => Attributes >> Drop(1) >>
         Collect(
           :id => replace.(It.id, Pair.(It.prefix, "")))))

function verify_assumptions(knot)
    @assert(0 == length(get(knot[Filter(It.type .!== It.first.path)])))

end

function testfhir()
    knot = load_profiles()[UnpackProfile]
    verify_assumptions(knot)
    return knot
end

