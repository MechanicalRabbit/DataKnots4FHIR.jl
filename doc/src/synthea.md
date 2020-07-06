## Querying Synthea FHIR Bundles

This package demonstrates how to query bundles of FHIR using DataKnots
with a 116 person synthetic dataset. First we import the relevant 
libraries we'll be using.

    using JSON
    using Dates
    using DataKnots
    using DataKnots4FHIR
    using Pkg.Artifacts

Next let's build an in-memory database that holds our synthetic patient
bundles. Note that the downloaded data includes two additional bundles,
for providers and hospitals.

    datapath = joinpath(artifact"synthea-116", "synthea-116");

    items = []
    for fname in readdir(datapath)
        item = JSON.parsefile(joinpath(datapath, fname))
        push!(items, item)
    end

    db = convert(DataKnot, (bundle=items, ) )
    #=>
    │ bundle                                                             …
    ┼────────────────────────────────────────────────────────────────────…
    │ Dict{String,Any}(\"entry\"=>Any[Dict{String,Any}(\"fullUrl\"=>\"urn…
    =#

    @query db count(bundle)
    #=>
    ┼─────┼
    │ 118 │
    =#

Then, we could define some FHIR profiles to work with it. For example,
we could ask, "What are the total number of ``Patient`` resources?"

    Observation = FHIRProfile(:R4, :Observation)
    Bundle = FHIRProfile(:R4, :Bundle)
    Patient = FHIRProfile(:R4, :Patient)

    @query db count(bundle.$Bundle.entry.resource.$Patient) 
    #=>
    ┼─────┼
    │ 116 │
    =#

Let's refine our bundle to pull out the things we're interested in
seeing. First, we're only interested in bundles that have a patient
entry in them. Then, let's group patents and observations and see how
many observations we have for each patient.

    Bundle =
       It.bundle >>
       FHIRProfile(:R4, :Bundle) >>
       Filter(Exists(It.entry.resource >> Patient)) >>
       Record(
        :patient => It.entry.resource >> Patient >> Is0to1,
        :observation => It.entry.resource >> Observation )

    @query db $Bundle{patient.id, count => count(observation)}
    #=>
        │ Bundle                                      │
        │ id                                    count │
    ────┼─────────────────────────────────────────────┼
      1 │ 31f1152b-6f91-4b0b-b7d3-67af683a7216    156 │
      2 │ 6f882e03-5e1d-4c04-8507-29ddfc0548bb    123 │
      ⋮
    116 │ e43e35c8-4ee6-4ad6-a195-a92afaeda66b     49 │
    =#
