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
  Get(:snapshot) >> Is(Dict) >>
  Get(:element) >> Is(Vector) >> Is(Dict) >>
  Record(
    :id => Get(:id) >> Is(String),
    :min => Get(:min) >> convert.(Unsigned, It),
    :path => Get(:path) >> Is(String),
    :max => Get(:max) >> Is(String),
    :type =>
      Get(:type) >> Is(Union{Vector, Missing}) >>
      Is(Vector) >> Is(Dict) >>
      Record(
        :code => Get(:code) >> Is(String),
        :extension => Get(:extension) >> Is(Union{Vector, Missing}) >>
          Is(Vector) >> Is(Dict) >>
          Record(
            :valueUrl => Get(:valueUrl) >> Is(Union{String, Missing}),
            :url => Get(:url) >> Is(String),
            :valueBoolean => Get(:valueBoolean) >> Is(Union{Bool, Missing})
          )
      )
  )

UnpackProfile =
  Given(
    :prefix => string.(Get(:type) >> Is(String), "."),
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

