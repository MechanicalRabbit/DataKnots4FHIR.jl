## Clinical Quality Measure (CQM) Demonstration

This workbook demonstrates how `DataKnots` could be used to construct a
domain specific query language (DSQL) for modeling Clinical Quality
Measures (CQMs). By modeling 4 electronic CQMs, [CMS104v8](
https://ecqi.healthit.gov/sites/default/files/ecqm/measures/CMS104v8.html),
[CMS124v7](
https://ecqi.healthit.gov/sites/default/files/ecqm/measures/CMS124v7.html),
[CMS125v7](
https://ecqi.healthit.gov/sites/default/files/ecqm/measures/CMS125v7.html),
and [CMS130v7](
https://ecqi.healthit.gov/sites/default/files/ecqm/measures/CMS130v7.html),
we provide a direct comparison to the Clinical Quality Language (CQL).
To get started, we must import modules relevant to our project.

    using DataKnots
    using DataKnots4FHIR
    using Dates
    using IntervalSets
    using JSON
    using Pkg.Artifacts

Next, let's create an in-memory test database with synthetic patient
bundles. This Synthea dataset was provided via a HL7 [connectathon](
https://github.com/DBCG/connectathon/tree/master/fhir3/supplemental-tests).
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

    @query db count(CMS104_pass)
    #=>
    ┼────┼
    │ 10 │
    =#

    @query db CMS104_pass
    #=>
       │ CMS104_pass                                                      │
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

    @query db CMS104_pass.bundle().{
                resource().group(resourceType).label(Resource).
                {resourceType, count(Resource).label(count)}}
    #=>
       │ Bundle                                                           │
       │ Resource{resourceType,count}                                     │
    ───┼──────────────────────────────────────────────────────────────────┼
     1 │ Claim, 63; Condition, 32; Encounter, 41; ExplanationOfBenefit, 4…│
     2 │ Claim, 17; Condition, 4; Encounter, 13; ExplanationOfBenefit, 13…│
     ⋮
     9 │ Claim, 45; Condition, 19; Encounter, 29; ExplanationOfBenefit, 2…│
    10 │ Claim, 53; Condition, 25; Encounter, 34; ExplanationOfBenefit, 3…│
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

To run a measure, we'll need to have a measure period.

    @define MeasurePeriod = interval("[2019-01-01..2020-01-01)")

For now, let's do only a small query...

    @query db CMS124_pass.QDM.PapTestWithin3Years
    #=>
       │ PapTestWithin3Years                                              │
       │ code             value                 relevantPeriod            │
    ───┼──────────────────────────────────────────────────────────────────┼
     1 │ 10524-7 [LOINC]  445528004 [SNOMEDCT]  2018-03-27T12:52:10..2018…│
     2 │ 10524-7 [LOINC]  445528004 [SNOMEDCT]  2019-02-20T12:52:10..2019…│
     ⋮
    19 │ 10524-7 [LOINC]  445528004 [SNOMEDCT]  2018-03-01T14:02:25..2018…│
    20 │ 10524-7 [LOINC]  445528004 [SNOMEDCT]  2019-02-24T14:02:25..2019…│
    =#

For now, let's do only a small query...

    @query db CMS124_pass.QDM.QualifyingEncounters
    #=>
       │ QualifyingEncounters                                           │
       │ code                  relevantPeriod                           │
    ───┼────────────────────────────────────────────────────────────────┼
     1 │ 439740005 [SNOMEDCT]  2019-02-20T12:52:10..2019-02-20T13:07:10 │
     2 │ 439740005 [SNOMEDCT]  2019-07-18T22:14:44..2019-07-18T22:29:44 │
     ⋮
    15 │ 439740005 [SNOMEDCT]  2019-05-04T09:05:14..2019-05-04T09:20:14 │
    16 │ 439740005 [SNOMEDCT]  2019-02-24T14:02:25..2019-02-24T14:17:25 │
    =#

Let's look at PapTestWithin5Years

    @query db CMS124_pass.QDM.PapTestWithin5Years
    #=>
       │ PapTestWithin5Years                                              │
       │ code             value                 relevantPeriod            │
    ───┼──────────────────────────────────────────────────────────────────┼
     1 │ 10524-7 [LOINC]  445528004 [SNOMEDCT]  2018-03-27T12:52:10..2018…│
     2 │ 10524-7 [LOINC]  445528004 [SNOMEDCT]  2019-02-20T12:52:10..2019…│
     ⋮
    19 │ 10524-7 [LOINC]  445528004 [SNOMEDCT]  2018-03-01T14:02:25..2018…│
    20 │ 10524-7 [LOINC]  445528004 [SNOMEDCT]  2019-02-24T14:02:25..2019…│
    =#
