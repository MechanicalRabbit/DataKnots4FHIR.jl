## Clinical Quality Measure (CQM) Demonstration

This workbook demonstrates how `DataKnots` could be used to construct a
domain specific query language (DSQL) for modeling Clinical Quality
Measures (CQMs). By modeling 4 electronic CQMs, 
[CMS104v8](https://ecqi.healthit.gov/sites/default/files/ecqm/measures/CMS104v8.html),
[CMS124v7](https://ecqi.healthit.gov/sites/default/files/ecqm/measures/CMS124v7.html),
[CMS125v7](https://ecqi.healthit.gov/sites/default/files/ecqm/measures/CMS125v7.html),
and [CMS130v7](https://ecqi.healthit.gov/sites/default/files/ecqm/measures/CMS130v7.html),
we provide a direct comparison to the Clinical Quality Language (CQL).
To get started, we must import modules relevant to our project.

    using DataKnots
    using DataKnots4FHIR
    using Dates
    using IntervalSets
    using JSON
    using Pkg.Artifacts

Next, let's create an in-memory test database with synthetic patient
bundles. This Synthea dataset was provided via a HL7
[connectathon](https://github.com/DBCG/connectathon/tree/master/fhir3/supplemental-tests).
For each measure, this database consists of 20 patient records, 10 that
are in the numerator of the eCQM ("pass"), and 10 that are not ("fail").

    function build(measure::String, kind::String)
        items = []
        datapath = joinpath(artifact"synthea-79", "synthea-79",
                            measure, kind)
        for fname in readdir(datapath)
            push!(items, JSON.parsefile(joinpath(datapath, fname)))
        end
        return items
    end

    db = convert(DataKnot, (
            CMS104_pass=build("CMS104v8", "numerator"),
            CMS104_fail=build("CMS104v8", "denominator"),
            CMS124_pass=build("CMS124v7", "numerator"),
            CMS124_fail=build("CMS124v7", "denominator"),
            CMS125_pass=build("CMS125v7", "numerator"),
            CMS125_fail=build("CMS125v7", "denominator"),
            CMS130_pass=build("CMS130v7", "numerator"),
            CMS130_fail=build("CMS130v7", "denominator")))

We can then run any sort of `DataKnot` on these datasets. However, they
cannot be directly queried because they are `Dict` structures.

    @query db count(CMS124_pass)
    #=>
    ┼────┼
    │ 10 │
    =#

    @query db CMS124_pass
    #=>
       │ CMS124_pass                                                      │
    ───┼──────────────────────────────────────────────────────────────────┼
     1 │ Dict{String,Any}(\"entry\"=>Any[Dict{String,Any}(\"fullUrl\"=>\"…│
     2 │ Dict{String,Any}(\"entry\"=>Any[Dict{String,Any}(\"fullUrl\"=>\"…│
     3 │ Dict{String,Any}(\"entry\"=>Any[Dict{String,Any}(\"fullUrl\"=>\"…│
     ⋮
     9 │ Dict{String,Any}(\"entry\"=>Any[Dict{String,Any}(\"fullUrl\"=>\"…│
    10 │ Dict{String,Any}(\"entry\"=>Any[Dict{String,Any}(\"fullUrl\"=>\"…│
    =#

We can unpack these structures into a more meaningful representation of
this Fast Healthcare Interoperability Resources (FHIR). This querying
approach requires careful conversion to each kind of FHIR Profile.
Moreover, it is not optimial for representing quality measures.

    @define bundle() = fhir_profile("STU3", "Bundle")
    @define resource() = entry.resource.fhir_profile("STU3", "Resource")

    @query db CMS124_pass.bundle().{
                resource().group(resourceType).label(Resource).
                {resourceType, count(Resource).label(count)}}
    #=>
       │ Bundle                                                           │
       │ Resource{resourceType,count}                                     │
    ───┼──────────────────────────────────────────────────────────────────┼
     1 │ Claim, 9; Condition, 1; Encounter, 9; ExplanationOfBenefit, 9; I…│
     2 │ Claim, 9; Condition, 1; Encounter, 9; ExplanationOfBenefit, 9; I…│
     ⋮
     9 │ Claim, 9; Condition, 1; Encounter, 9; ExplanationOfBenefit, 9; I…│
    10 │ Claim, 9; Condition, 1; Encounter, 9; ExplanationOfBenefit, 9; I…│
    =#

We can futher unpack these structures to something similar to the
Quality Data Model (QDM).

    @query db CMS124_pass.QDM.LaboratoryTestPerformed
    #=>
       │ LaboratoryTestPerformed                                          │
       │ code             value                 relevantPeriod            │
    ───┼──────────────────────────────────────────────────────────────────┼
     1 │ 10524-7 [LOINC]  445528004 [SNOMEDCT]  2018-03-27T12:52:10..2018…│
     2 │ 10524-7 [LOINC]  445528004 [SNOMEDCT]  2019-02-20T12:52:10..2019…│
     ⋮
    26 │ 10524-7 [LOINC]  445528004 [SNOMEDCT]  2018-03-01T14:02:25..2018…│
    27 │ 10524-7 [LOINC]  445528004 [SNOMEDCT]  2019-02-24T14:02:25..2019…│
    =#

Let's load the eCQM.

    include("cms124v7.jl")
    #-> ⋮

To run a measure, we'll need to have a measure period; note that we want
it to be an open interval on the right endpoint.

    @define MeasurePeriod = interval("[2018-01-01..2019-01-01)")

Let's unit-test a few queries to see that they return what we wish.

    @query db CMS124_pass.QDM.PapTestWithin3Years
    #=>
       │ PapTestWithin3Years                                              │
       │ code             value                 relevantPeriod            │
    ───┼──────────────────────────────────────────────────────────────────┼
     1 │ 10524-7 [LOINC]  445528004 [SNOMEDCT]  2018-03-27T12:52:10..2018…│
     2 │ 10524-7 [LOINC]  445528004 [SNOMEDCT]  2018-08-22T22:14:44..2018…│
     ⋮
     9 │ 10524-7 [LOINC]  445528004 [SNOMEDCT]  2018-05-09T09:05:14..2018…│
    10 │ 10524-7 [LOINC]  445528004 [SNOMEDCT]  2018-03-01T14:02:25..2018…│
    =#

    @query db CMS124_pass.QDM.QualifyingEncounters
    #=>
       │ QualifyingEncounters                                             │
       │ code                  dischargeDisposition  relevantPeriod       │
    ───┼──────────────────────────────────────────────────────────────────┼
     1 │ 439740005 [SNOMEDCT]  439740005 [SNOMEDCT]  2018-03-27T12:52:10.…│
     2 │ 439740005 [SNOMEDCT]  439740005 [SNOMEDCT]  2018-08-22T22:14:44.…│
     ⋮
    20 │ 439740005 [SNOMEDCT]  439740005 [SNOMEDCT]  2018-05-09T09:05:14.…│
    21 │ 439740005 [SNOMEDCT]  439740005 [SNOMEDCT]  2018-03-01T14:02:25.…│
    =#

    @query db CMS124_pass.QDM.PapTestWithin5Years
    #=>
       │ PapTestWithin5Years                                              │
       │ code             value                 relevantPeriod            │
    ───┼──────────────────────────────────────────────────────────────────┼
     1 │ 10524-7 [LOINC]  445528004 [SNOMEDCT]  2018-03-27T12:52:10..2018…│
     2 │ 10524-7 [LOINC]  445528004 [SNOMEDCT]  2018-08-22T22:14:44..2018…│
     ⋮
     9 │ 10524-7 [LOINC]  445528004 [SNOMEDCT]  2018-05-09T09:05:14..2018…│
    10 │ 10524-7 [LOINC]  445528004 [SNOMEDCT]  2018-03-01T14:02:25..2018…│
    =#

For the expected failures, they are `false` for the numerator.

    @query db CMS124_fail.QDM.{Numerator, Denominator, DenominatorExclusions}
    #=>
       │ QDM                                           │
       │ Numerator  Denominator  DenominatorExclusions │
    ───┼───────────────────────────────────────────────┼
     1 │     false         true                  false │
     2 │     false         true                  false │
     ⋮
     9 │     false         true                  false │
    10 │     false         true                  false │
    =#

For the expected numerator passes, we get all `true`.

    @query db CMS124_pass.QDM.{Numerator, Denominator, DenominatorExclusions}
    #=>
       │ QDM                                           │
       │ Numerator  Denominator  DenominatorExclusions │
    ───┼───────────────────────────────────────────────┼
     1 │      true         true                  false │
     2 │      true         true                  false │
     ⋮
     9 │      true         true                  false │
    10 │      true         true                  false │
    =#
