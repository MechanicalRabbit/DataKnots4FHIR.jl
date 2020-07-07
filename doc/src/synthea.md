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

    Bundle = FHIRProfile(:R4, :Bundle)
    Patient = FHIRProfile(:R4, :Patient)
    Observation = FHIRProfile(:R4, :Observation)
    Condition = FHIRProfile(:R4, :Condition)

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
        :condition => It.entry.resource >> Condition,
        :observation => It.entry.resource >> Observation )

    @query db $Bundle{patient.id, no_obs => count(observation),
                                  no_cnd => count(condition)}
    #=>
        │ Bundle                                               │
        │ id                                    no_obs  no_cnd │
    ────┼──────────────────────────────────────────────────────┼
      1 │ 31f1152b-6f91-4b0b-b7d3-67af683a7216     156       8 │
      2 │ 6f882e03-5e1d-4c04-8507-29ddfc0548bb     123      13 │
      ⋮
    116 │ e43e35c8-4ee6-4ad6-a195-a92afaeda66b      49      10 │
    =#

Since we're unfamilar with this database, we could see what sort of
observations were made. It seems not very much variety, but this is
synthetic data.

    @query db begin
        $Bundle.observation.valueCodeableConcept
        group(coding{code, display})
        {coding, count=>count(valueCodeableConcept)}
    end
    #=>
       │ coding{code,display}                                count │
    ───┼───────────────────────────────────────────────────────────┼
     1 │ 10828004, Positive (qualifier value)                   10 │
     2 │ 109838007, Overlapping malignant neoplasm of colon      1 │
    ⋮
    34 │ 87433001, Pulmonary emphysema (disorder)                1 │
    35 │ 95281009, Sudden Cardiac Death                          3 │
    =#

Let's see what sort of conditions are assigned.

    @query db begin
               $Bundle.condition.code
               group(coding{code, display})
               {coding, count=>count(code)}
    end
    #=>
        │ coding{code,display}                                      count │
    ────┼─────────────────────────────────────────────────────────────────┼
      1 │ 10509002, Acute bronchitis (disorder)                        57 │
      2 │ 109838007, Overlapping malignant neoplasm of colon            1 │
      3 │ 124171000119105, Chronic intractable migraine without au…     4 │
      ⋮
    124 │ 87628006, Bacterial infectious disease (disorder)             3 │
    125 │ 88805009, Chronic congestive heart failure (disorder)         1 │
    =#

