# DataKnots4FHIR.jl

This package is an application of DataKnots to Health Level 7 (HL7)
Fast Healthcare Interoperability Resources (FHIR). The main activity
of this package is to parse profile specifications and produce
queries that convert JSON based FHIR resources into DataKnots.

Let's start with an example from the FHIR specification, an [example
patient](https://www.hl7.org/fhir/R4/patient-example.json.html). In
Julia, we can use the *artifact* system to find its file name.

    using Pkg.Artifacts

    fname = joinpath(artifact"fhir-r4", "fhir-r4", "patient-example.json")
    #-> .../fhir-r4/patient-example.json

    open(fname) do file
        read(file, String)
    end
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

We can then then use the `JSON` module to parse it. This will return
a top-level dictionary. Once returned, we could use Julia natively to
query the data.

    using JSON

    jsondata = JSON.parsefile(fname)
    #=>
    Dict{String,Any} with 14 entries:
      "active"               => true
      "managingOrganization" => Dict{String,Any}("reference"=>"Organizati…
      "address"              => Any[Dict{String,Any}("line"=>Any["534 Ere…
      "name"                 => Any[Dict{String,Any}("family"=>"Chalmers"…
    ⋮
    =#

    jsondata["name"][1]["family"]
    #-> "Chalmers"

However, native structures arn't particular convenient when dealing
with plural values, filtering, aggregate, and other operations. We could
use DataKnots for this.

    using DataKnots

    knot = convert(DataKnot, jsondata)
    #=>
    ┼────────────────────────────────────────────────────────────────────…
    │ Dict{String,Any}(\"active\"=>true,\"managingOrganization\"=>Dict{St…
    =#

    knot[Is(Dict) >> It.name >> Is(Vector) >> Is(Dict) >>
         It.family >> Is(Union{String,Missing})]
    #=>
      │ family   │
    ──┼──────────┼
    1 │ Chalmers │
    2 │ Windsor  │
    =#

The output of this is convenient, but the query has quite a bit of type
information. This can be automated by converting the FHIR R4 ``Patient`
[profile](https://www.hl7.org/fhir/r4/patient.html).

    Using DataKnots4FHIR

    Patient = FHIRProfile(:R4, "Patient");

    knot[Patient >> It.name.family]
    #=>
      │ family   │
    ──┼──────────┼
    1 │ Chalmers │
    2 │ Windsor  │
    =#

There is a macro version using a more succinct syntax.

    @query knot $Patient.name.family
    #=>
      │ family   │
    ──┼──────────┼
    1 │ Chalmers │
    2 │ Windsor  │
    =#

Once we have a DataKnot, we can do all sorts of query operations; for
example, we can find the given names associated with the family
name `"Windsor"`.

    @query knot $Patient.name.filter(family=="Windsor").given
    #=>
      │ given │
    ──┼───────┼
    1 │ Peter │
    2 │ James │
    =#

What's more interesting is when we query large collections...
