# DataKnots4FHIR.jl

This package is an application of the DataKnots processing system to
Health Level 7 (HL7) Fast Healthcare Interoperability Resources (FHIR).
This project creates schema-driven DataKnot queries for each FHIR
profile, giving convenient access to JSON encoded FHI.

## Quick Start

Let's start with an example FHIR resource encoded using JSON, [example
patient](https://www.hl7.org/fhir/R4/patient-example.json.html). This
resource could could be downloaded to a temporary file as follows.

```julia
fname = download("https://www.hl7.org/fhir/R4/patient-example.json")
```

Alternatively, we've packaged the R4 FHIR specification, with examples,
as Julia *Artifact* so they can be accessed via `artifact"fhir-r4"`.

    using Pkg.Artifacts

    fname = joinpath(artifact"fhir-r4", "fhir-r4", "patient-example.json")
    #-> …/fhir-r4/patient-example.json"

Regardless, the content for this downloaded file is JSON. It could be
read directly and printed to the terminal.

    println(read(fname, String))
    #=>
    {
      "resourceType": "Patient",
      "id": "example",
    ⋮
      "name": [
        {
          "use": "official",
          "family": "Chalmers",
    ⋮
    =#

We can then then use the `JSON` module to parse it. This will return a
top-level dictionary.

    using JSON

    resource = JSON.parsefile(fname)
    display(resource)
    #=>
    Dict{String,Any} with 14 entries:
      "active"               => true
      "managingOrganization" => Dict{String,Any}("reference"=>"Organizati…
      "address"              => Any[Dict{String,Any}("line"=>Any["534 Ere…
      "name"                 => Any[Dict{String,Any}("family"=>"Chalmers"…
    ⋮
    =#

Querying this structure could be done with native Julia. The following
would return family names listed for this patient resource.

    [item["family"]
     for item in resource["name"]
     if haskey(item, "family") ]
    #=>
    ["Chalmers", "Windsor"]
    =#

To more easily query this resource, we use two steps. First, we have to
convert this data into a ``DataKnot``. However, since JSON is
schemaless, DataKnots can't easily work with it directly. Here we see
that by default, it's a single value holding that same dictionary.

    using DataKnots

    resource = convert(DataKnot, JSON.parsefile(fname))
    #=>
    ┼────────────────────────────────────────────────────────────────────…
    │ Dict{String,Any}(\"active\"=>true,\"managingOrganization\"=>Dict{St…
    =#

The `FHIRProfile` query constructor provides the needed schema by
converting the FHIR resource definition from the HL7 specification. For
example, let's build a query reflecting the the FHIR R4
[Patient](https://www.hl7.org/fhir/r4/patient.html) profile. What the
``Patient`` query does is rather involved, so we'll skip that for now,
using the semicolon to suppress printing its definition.

    using DataKnots4FHIR

    Patient = FHIRProfile(:R4, "Patient");

With this ``Patient`` query, the above inquiry, we can once again list
all of the family names used by the patient resource. This example uses
the DataKnots macro syntax; where the ``Patient`` query is referenced
using the dollar sign (``$``).

    @query resource $Patient.name.family
    #=>
      │ family   │
    ──┼──────────┼
    1 │ Chalmers │
    2 │ Windsor  │
    =#

With this syntax, the ``name`` field in each ``Patient`` is defined by
the [HumanName](https://www.hl7.org/fhir/r4/datatypes.html#HumanName)
element. With this ``Patient`` schema query, the incoming data knot is
structured so that it could be intelligibly queried. For example, we
could return all of the ``given`` names of this patient associated with
the ``"Windsor"`` family name.

    @query resource $Patient.name.filter(family=="Windsor").given
    #=>
      │ given │
    ──┼───────┼
    1 │ Peter │
    2 │ James │
    =#

To see the structure of our data, we use ``show(as=:shape, knot)``.
This shows the resource hierarchically. Here we can see each ``Patient``
has a zero-or-more ``name`` records. Each ``name`` has at-most-one
``family`` and zero-or-more `given` names.

    show(as=:shape, @query resource $Patient)
    #=>
    1-element DataKnot:
      Patient                   0:1
      ├╴resourceType            1:1 × String
      ├╴id                      0:1 × String
    ⋮
      ├╴active                  0:1 × Bool
      ├╴name                    0:N
      │ ├╴id                    0:1 × String
    ⋮
      │ ├╴family                0:1 × String
      │ ├╴given                 0:N × String
    ⋮
    =#

There are a wealth of query operators available in DataKnots. More
[documentation](https://rbt-lang.github.io/DataKnots.jl/stable/) for
DataKnots is available.

## Challenges of JSON Resources

Using FHIR resources represented with JSON, without a corresponding
profile definition, is somewhat challenging. Since JSON is schemaless,
there is no way to know before inspecting the resource object if a given
data element is a scalar value represented as a ``String`` or
``Integer`, or a nested structure represented as a ``Dict``.

To make it easy to interrogate FHIR specification examples using their
respective profiles, we have a helper function helper function which
finds a specification example, loads it as JSON, and converts it to a
DataKnot for us.

    resource = FHIRExample(:R4, "Patient", "example")
    #=>
    ┼────────────────────────────────────────────────────────────────────…
    │ Dict{String,Any}(\"active\"=>true,\"managingOrganization\"=>Dict{St…
    =#


Hence, to check of the resource is a ``"Patient"``, we'd write

    resource[Is(Dict) >> It.resourceType >> Is(String) .== "Patient"]
    #=>
    ┼──────┼
    │ true │
    =#

Further, if the value is plural, there will be an intermediate
``Vector``. Moreover, missing field are simply omitted which make it
hard to raise an exception if there is a query typo.

    resource[Is(Dict) >> It.name >> Is(Vector) >> Is(Dict) >>
                         It.family >> Is(Union{String,Missing})]
    #=>
      │ family   │
    ──┼──────────┼
    1 │ Chalmers │
    2 │ Windsor  │
    =#

To make it easy to interrogate FHIR specification examples using their
respective profiles, we have a helper function
helper function which finds the example, loads it as JSON, and converts
it to a DataKnot for us.

    resource = FHIRExample(:R4, "Patient", "example")

This magic is done by the ``Patient`` object.

    Patient = FHIRProfile(:R4, "Patient");
    #=>
    Is(Dict{String,Any}) >>
    Filter(It.resourceType >> Is(String) .== "Patient") >>
    Record(
        Get(:resourceType) >> Is(String),
    ⋮
    =#
