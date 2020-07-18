## Incremental Building of CMS124v7

In this workbook, we will incrementally develop a CMS124v7 measure;
going though the process of discovery and building/testing each
component. The completed query will be maintained separately.

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

For starters, let's define a Quality Data Model suitable to this
measure.

    QDMProfile(::Val{:STU3}, ::Val{Symbol("5.3")},
               ::Val{Symbol("Laboratory Test, Performed")}) =
        It.entry.resource >>
        FHIRProfile(:STU3, "Observation") >>
        Record(
          :code => It.code.coding >> Is1toN >>
                   Coding.(It.system, It.code),
          :relevantPeriod =>
              DateTime.(It.effectiveDateTime, UTC) >> Is1to1 >>
              DateTimePeriod.(It, It)) >>
        Label(:LaboratoryTestPerformed)

    QDMProfile(vFHIR, vQDM::String, element::String) =
        QDMProfile(Val(Symbol(vFHIR)), Val(Symbol(vQDM)),
                   Val(Symbol(element)))

    QDM = FHIRProfile(:STU3, "Bundle") >>
          Record(
             QDMProfile("STU3", "5.3", "Laboratory Test, Performed")
          )

    db[It.pass >> QDM >> It.LaboratoryTestPerformed]
    #=>
       │ LaboratoryTestPerformed                                          │
       │ code                        relevantPeriod                       │
    ───┼──────────────────────────────────────────────────────────────────┼
     1 │ 10524-7 [http://loinc.org]  2018-03-27T12:52:10 to 2018-03-27T12…│
     2 │ 10524-7 [http://loinc.org]  2019-02-20T12:52:10 to 2019-02-20T12…│
     ⋮
    26 │ 10524-7 [http://loinc.org]  2018-03-01T14:02:25 to 2018-03-01T14…│
    27 │ 10524-7 [http://loinc.org]  2019-02-24T14:02:25 to 2019-02-24T14…│
    =#

## Older Test Cases

The first thing we need to do is construct the relevant FHIR profiles.
Let's define what it means to be a bundle...

    @define as_patient() = fhir_profile("STU3", "Patient")
    @define as_condition() = fhir_profile("STU3", "Condition")
    @define as_encounter() = fhir_profile("STU3", "Encounter")
    @define as_observation() = fhir_profile("STU3", "Observation")
    @define as_bundle() = fhir_profile("STU3", "Bundle")

    @define unpack() = begin
         as_bundle()
         record(
           it.entry.resource.as_patient().is0to1(),
           it.entry.resource.as_encounter(),
           it.entry.resource.as_condition(),
           it.entry.resource.as_observation())
    end

    @query db pass.unpack(){
               Patient.id,
               no_obs => count(Observation),
               no_cnd => count(Condition)}
    #=>
       │ Bundle                                               │
       │ id                                    no_obs  no_cnd │
    ───┼──────────────────────────────────────────────────────┼
     1 │ 3abdd6da-1f73-4964-a926-4694a6ad0d92       2       1 │
     2 │ 98f9fe24-5bc3-4361-89ab-ea0c8e89f868       2       1 │
     ⋮
     9 │ e07bddf8-00a2-4f46-84e6-6209e3c528a9       2       1 │
    10 │ 25d8d8dd-64d4-4adb-8e4a-010585236c62       2       1 │
    =#

We can think of value-sets as predicates. Let's define ``is_paptest`` to
mean that a ``CodeableConcept`` matches the requested coding. Here, we
see that the 10 patients that are expected to have a positive numerator
have had a ``paptest``.

    @define is_paptest() = iscoded("http://loinc.org",
                  "10524-7", "18500-9", "19762-4", "19764-0", "19765-7",
                  "19766-5", "19774-9", "33717-0", "47527-7", "47528-5")

    @query db {count(pass.unpack().filter(Observation.code.is_paptest())),
               count(fail.unpack().filter(Observation.code.is_paptest()))}
    #=>
    │ #A  #B │
    ┼────────┼
    │ 10   0 │
    =#

Let's see what other data is involved with observations that are paptests.
The CQL for this query is...

```CQL
define "Pap Test with Results":
	[Observation: "Pap Test"] PapTest
		where PapTest.value is not null
			and PapTest.status in { 'final', 'amended',
                                                'corrected', 'preliminary' }
```

    @define paptest_with_results() =
              Observation.filter(code.is_paptest() &
                                 exists(value) &
                                 status.in("final", "amended",
                                           "corrected", "preliminary"))

    @query db begin
         pass.unpack()
         filter(exists(paptest_with_results()))
         Patient.id
    end
    #=>
       │ id                                   │
    ───┼──────────────────────────────────────┼
     1 │ 3abdd6da-1f73-4964-a926-4694a6ad0d92 │
     2 │ 98f9fe24-5bc3-4361-89ab-ea0c8e89f868 │
     3 │ 83e608cc-dffc-42dd-9923-d6ed4490734a │
     ⋮
     9 │ e07bddf8-00a2-4f46-84e6-6209e3c528a9 │
    10 │ 25d8d8dd-64d4-4adb-8e4a-010585236c62 │
    =#

Next, let's define the measure period, and see which of these
observations fall within that measure period. There are two deficiencies
here: we're using zoned datetime and we don't yet have open intervals.

    @define measure_period =
       time_period("2019-01-01T00:00:00.000",
                   "2019-12-31T23:59:59.999")

#   @query db begin
#        pass.unpack()
#        filter(
#            paptest_with_results().
#            effectiveDateTime.
#            during(measure_period)
#        )
#        Patient.id
#   end
#   #=>
#      │ id                                   │
#   ───┼──────────────────────────────────────┼
#    1 │ 3abdd6da-1f73-4964-a926-4694a6ad0d92 │
#    2 │ 98f9fe24-5bc3-4361-89ab-ea0c8e89f868 │
#    3 │ 83e608cc-dffc-42dd-9923-d6ed4490734a │
#    ⋮
#    9 │ e07bddf8-00a2-4f46-84e6-6209e3c528a9 │
#   10 │ 25d8d8dd-64d4-4adb-8e4a-010585236c62 │
#   =#

The CQL fragment isn't quite a simple. We have to make a special
combinator called ``normalize_interval`` that presumably takes the
``effectiveDateTime`` and normalizes it to an ``effectivePeriod``.

```CQL
define "Pap Test Within 3 Years":
	"Pap Test with Results" PapTest
		where Global."Normalize Interval"(PapTest.effective)
               ends 3 years or less before end of "Measurement Period"
```
