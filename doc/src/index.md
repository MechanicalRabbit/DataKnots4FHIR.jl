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
converting the FHIR resource definition from the HL7 specification.
For example, let's build a query reflecting the the FHIR R4
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

To make it easy to explore these profiles, we have a helper constructor,
``FHIRExample``, which finds a specification example by its identifier,
loads it as JSON, and converts it into a DataKnot for us. Hence, the
following is the minimal code needed to get up-and-running.

    using DataKnots
    using DataKnots4FHIR

    Patient = FHIRProfile(:R4, "Patient");
    resource = FHIRExample(:R4, "Patient", "example");

    @query resource $Patient
    #=>
    │ Patient                                                            …
    │ resource… id       meta{id,… implicit… language  text{id,… containe…
    ┼────────────────────────────────────────────────────────────────────…
    │ Patient   example                                missing,…         …
    =#

What exactly does the ``Patient`` profile do?

## Profile Queries

Directly querying a JSON encoded FHIR resource is challenging. Since
JSON is schemaless, we don't know in advance if a given data element is
a scalar value represented as a ``String`` or ``Integer`, or a nested
structure represented as a ``Dict``, or some other kind of object. We
can use DataKnot's ``show(as=:shape, *knot*)`` function to look at the
structure of a dataknot.

    show(as=:shape, resource)
    #=>
    1-element DataKnot:
      #  Dict{String,Any}
    =#

DataKnots lets us query dictionaries by key. Hence, we could return the
``resourceType`` of this FHIR resource.

    @query resource resourceType
    #=>
    │ resourceType │
    ┼──────────────┼
    │ Patient      │
    =#

However, things get complex when we try to return the list of ``name``
elements associated with the resource. Suppose we want to return a list
of family names, one might try to write ``name.family``.

    @query resource name.family
    #=>
    ERROR: cannot find "family" at
    (1:1) × Any
    =#

DataKnots cannot determine the output type of ``@query resource name``,
and such it's listed as a singular value ``Any``.

    show(as=:shape, @query resource name)
    #=>
    1-element DataKnot:
      name  1:1 × Any
    =#

From inspection, we can see that the output is actually a vector of
dictionaries.

    @query resource name
    #=>
    │ name                                                               …
    ┼────────────────────────────────────────────────────────────────────…
    │ Any[Dict{String,Any}(\"family\"=>\"Chalmers\",\"given\"=>Any[\"Pete…
    =#

We could let DataKnots know that `name` is a vector of dictionaries
using the ``Is`` combinator as follows.

    @query resource name.is(Vector).is(Dict)
    #=>
      │ name                                                             …
    ──┼──────────────────────────────────────────────────────────────────…
    1 │ Dict{String,Any}(\"family\"=>\"Chalmers\",\"given\"=>Any[\"Peter\…
    2 │ Dict{String,Any}(\"given\"=>Any[\"Jim\"],\"use\"=>\"usual\")     …
    3 │ Dict{String,Any}(\"family\"=>\"Windsor\",\"given\"=>Any[\"Peter\"…
    =#

Then, we could return the list of ``family`` names; except this has its
own problem. The second entry provides a nickname, and the family name
is optional, shown here as missing, rather than being omitted.

    @query resource name.is(Vector).is(Dict).family
    #=>
      │ family   │
    ──┼──────────┼
    1 │ Chalmers │
    2 │ missing  │
    3 │ Windsor  │
    =#

    show(as=:shape, @query resource name.is(Vector).is(Dict).family)
    #=>
    3-element DataKnot:
      family  0:N × Any
    =#

This can be addressed by specifying the datatype of ``family`` is
``Union{String, Missing}``. In this case, DataKnots knows that the
``missing`` value should be omitted in the query result.

    @query resource name.is(Vector).is(Dict).family.
                         is(Union{String, Missing})
    #=>
      │ family   │
    ──┼──────────┼
    1 │ Chalmers │
    2 │ Windsor  │
    =#

Providing this detail is what the ``Patient`` profile query does.

    Patient = FHIRProfile(:R4, "Patient")
    @query resource $Patient.name.family
    #=>
      │ family   │
    ──┼──────────┼
    1 │ Chalmers │
    2 │ Windsor  │
    =#

This typing information beings with it another benefit. By default
operations on a dictionary return ``missing`` if a key is omitted.
Hence, if you have a typo, such as, ``resoursType`` instead of
``resourceType``, you'll get a ``missing`` value rather than an error.

    @query resource resoursType
    #=>
    │ resoursType │
    ┼─────────────┼
    │ missing     │
    =#

By applying the the ``Patient`` query, typos like this are errors.

    @query resource $Patient.resoursType
    #=>
    ERROR: cannot find "resoursType" at
    (0:1) × (resourceType = (1:1) × String, …
    =#

Moreover, this ``Patient`` profile can be used for introspection.

    show(as=:shape, @query resource $Patient.name)
    #=>
    3-element DataKnot:
      name           0:N
      ├╴id           0:1 × String
      ├╴extension    0:N × Dict{String,Any}
      ├╴use          0:1 × String
      ├╴text         0:1 × String
      ├╴family       0:1 × String
      ├╴given        0:N × String
    ⋮
    =#

## Exceptional Cases

These generated profiles are not perfect. They are quite large and the
FHIR schema has cycles. Therefore, these profiles stop expanding once an
element has been seen before. Moreover, extensions are not expanded.
Sometimes access to extensions is needed. The `"newborn"`` specification
example has an example of an extension.

    newborn = FHIRExample(:R4, "Patient", "newborn");

    @query newborn $Patient.extension
    #=>
      │ extension                                                      …
    ──┼────────────────────────────────────────────────────────────────…
    1 │ Dict{String,Any}(\"valueString\"=>\"Everywoman\",\"url\"=>\"htt…
    =#

To work with the extension, we could use the ``Extension`` profile.

    Extension = FHIRProfile(:R4, "Extension");

    @query newborn begin
        $Patient.extension.$Extension.
         filter(endswith(url, "patient-mothersMaidenName")).
         valueString
    end
    #=>
      │ valueString │
    ──┼─────────────┼
    1 │ Everywoman  │
    =#

It's often handy to convert these into a query, so they can be reused.
We do this below using DataKnots' Julia syntax. We'll check for equality
on the entire URL and additionally assert there is at most one result.

    MothersMaidenName = Is0to1(
        It.extension >> Extension >>
        Filter(It.url .== string("http://hl7.org/fhir/StructureDefinition/",
                                 "patient-mothersMaidenName")) >>
        It.valueString) >> Label(:mothersMaidenName);

    @query newborn $Patient.$MothersMaidenName
    #=>
    │ mothersMaidenName │
    ┼───────────────────┼
    │ Everywoman        │
    =#

Sometimes scalar field values, such as `birthDate` have an extension; we
do not represent these either. To permit access, at every level of the
hierarchy, we provide a special underscore attribute that gives access
to the underlying JSON source for that component.

    @query resource $Patient._
    #=>
    │ _                                                                  …
    ┼────────────────────────────────────────────────────────────────────…
    │ Dict{String,Any}(\"active\"=>true,\"managingOrganization\"=>Dict{St…
    =#

From there, one could access the extension for `birthDate`.

    @query resource $Patient._._birthDate
    #=>
    │ _birthDate                                                         …
    ┼────────────────────────────────────────────────────────────────────…
    │ Dict{String,Any}(\"extension\"=>Any[Dict{String,Any}(\"valueDateTim…
    =#

However, using the underlying ``Dict`` is complex. In particular, one
must handle not only providing type information as described earlier,
but also, convert missing values into empty lists using ``coalesce``.
There is a helper function that does this for you.

    BirthInfo = FHIRField(:R4, "_birthDate");

    @query resource $Patient.$BirthInfo
    #=>
    │ _birthDate                                                         …
    │ id  extension{id,extension,url,valueBase64Binary,valueBoolean,value…
    ┼────────────────────────────────────────────────────────────────────…
    │     missing, [], http://hl7.org/fhir/StructureDefinition/patient-bi…
    =#

Using this, one could define another custom combinator.

    BirthTime = Is0to1(
        FHIRField(:R4, "_birthDate") >> It.extension >>
        Filter(It.url .== string("http://hl7.org/fhir/StructureDefinition/",
                                 "patient-birthTime")) >>
        It.valueDateTime) >> Label(:birthTime);

    @query newborn $Patient.$BirthTime
    #=>
    │ birthTime                 │
    ┼───────────────────────────┼
    │ 2017-05-09T17:11:00+01:00 │
    =#
