## Incremental Building of CMS124v7

In this workbook, we will incrementally develop a CMS124v7 measure using
Synthea data provided in January 2020 as part of a HL7 [connectathon](
https://github.com/DBCG/connectathon/tree/master/fhir3/supplemental-tests).
There are two approaches to computing this measure with the Clinical
Quality Language (CQL), using the Quality Data Model (QDM) or using the
QUICK model directly from FHIR. This workbook shows how we could see
this work in two stages. First, we'll create a minimal conversion of
FHIR to a model inspired by the QDM. Second, we'll implement CMS124v7
using this inspiried model.

    using JSON
    using Dates
    using TimeZones
    using DataKnots
    using DataKnots4FHIR
    using Pkg.Artifacts

Let's create an in-memory database that holds our synthetic patient
bundles. We have expected results -- there are 10 that pass the
numerator criteria, and 10 that fail to meet this criteria.

    datapath = joinpath(artifact"synthea-79", "synthea-79", "CMS124v7");

    function build(kind::String)
        items = []
        for fname in readdir(joinpath(datapath, kind))
            push!(items, JSON.parsefile(joinpath(datapath, kind, fname)))
        end
        return items
    end
    db = convert(DataKnot, (pass=build("numerator"),
                            fail=build("denominator")))

    @query db {no_pass=>count(pass), no_fail=>count(fail)}
    #=>
    │ no_pass  no_fail │
    ┼──────────────────┼
    │      10       10 │
    =#

In this module, we've defined a "QDM" query that translates a FHIR data
source as loaded into a QDM. Here we can look at laboratory tests that
are executed on the `pass` dataset.

    @query db pass.QDM.LaboratoryTestPerformed{code, value, relevantPeriod}
    #=>
       │ LaboratoryTestPerformed                                          │
       │ code             value                 relevantPeriod            │
    ───┼──────────────────────────────────────────────────────────────────┼
     1 │ 10524-7 [LOINC]  445528004 [SNOMEDCT]  2018-03-27T12:52:10 to 20…│
     2 │ 10524-7 [LOINC]  445528004 [SNOMEDCT]  2019-02-20T12:52:10 to 20…│
     ⋮
    26 │ 10524-7 [LOINC]  445528004 [SNOMEDCT]  2018-03-01T14:02:25 to 20…│
    27 │ 10524-7 [LOINC]  445528004 [SNOMEDCT]  2019-02-24T14:02:25 to 20…│
    =#

In an eCQM, one of the very first things we want to do is filter by a
value set. We can use the `@valueset` macro to declare `PapTest` data,
in a manner comparable to CQL. It can then be treated as a query.

```CQL
valueset "Pap Test": 'urn:oid:2.16.840.1.113883.3.464.1003.108.12.1017'
```

    @valueset PapTest = "2.16.840.1.113883.3.464.1003.108.12.1017"

    @query db PapTest
    #=>
       │ PapTest         │
    ───┼─────────────────┼
     1 │ 10524-7 [LOINC] │
     2 │ 18500-9 [LOINC] │
     3 │ 19762-4 [LOINC] │
     ⋮
     9 │ 47527-7 [LOINC] │
    10 │ 47528-5 [LOINC] │
    =#

One of the first CQL queries in CMS124v7 is "Pap Test with Results", we
can now define an equivalent using query combinators. This same query
combinator can be created using the UUID from ULMS.

```CQL
define "Pap Test with Results":
        ["Laboratory Test, Performed": "Pap Test"] PapTest
                where PapTest.result is not null
```

    @define PapTestWithResults =
                LaboratoryTestPerformed.
                    filter(code.matches(PapTest) & exists(value))

    @query db pass.QDM.PapTestWithResults
    #=>
       │ PapTestWithResults                                               │
       │ code             value                 relevantPeriod            │
    ───┼──────────────────────────────────────────────────────────────────┼
     1 │ 10524-7 [LOINC]  445528004 [SNOMEDCT]  2018-03-27T12:52:10 to 20…│
     2 │ 10524-7 [LOINC]  445528004 [SNOMEDCT]  2019-02-20T12:52:10 to 20…│
     ⋮
    19 │ 10524-7 [LOINC]  445528004 [SNOMEDCT]  2018-03-01T14:02:25 to 20…│
    20 │ 10524-7 [LOINC]  445528004 [SNOMEDCT]  2019-02-24T14:02:25 to 20…│
    =#

Note that the equivalent version using CQL for QUICK includes further
limitations on the `Observation` property `status`; for us, this is done
earlier as we convert to the QDM model.

```CQL
define "Pap Test with Results":
	[Observation: "Pap Test"] PapTest
		where PapTest.value is not null
			and PapTest.status in { 'final', 'amended',
                                                'corrected', 'preliminary' }
```

Next, let's look at intervals.

```CQL
define "Pap Test Within 3 Years":
	"Pap Test with Results" PapTest
		where Global."Normalize Interval"(PapTest.effective)
               ends 3 years or less before end of "Measurement Period"
```
