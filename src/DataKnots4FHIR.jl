module DataKnots4FHIR

using Base64
using DataKnots
using Dates
using JSON
using Pkg.Artifacts
using TimeZones

export
    FHIRProfile,
    FHIRExample,
    FHIRField

# As a profile query is generated, it consists of type assertions;
# since some of those can be complex, we'll define them here.

StringDict  = Dict{String, Any}
IsInt       = Is(Int)
IsBool      = Is(Bool)
IsDict      = Is(StringDict)
IsString    = Is(String)
IsVector    = Is(Vector{Any})
IsOptInt    = Is(Union{Int, Missing})
IsOptBool   = Is(Union{Bool, Missing})
IsOptDict   = Is(Union{StringDict, Missing})
IsOptString = Is(Union{String, Missing})
IsOptVector = Is(Union{Vector{Any}, Missing})
AsVector    = coalesce.(It, Ref([])) >> IsVector

# Since profiles refer to each other, we will create all of them
# in one fell swoop rather than doing it dynamically.

profile_registry = Dict{Symbol, DataKnots.AbstractQuery}()
complex_registry = Dict{Symbol, DataKnot}()
example_registry = Dict{Tuple{Symbol, Symbol}, DataKnot}()
resource_registry = Dict{Symbol, DataKnot}()
primitive_registry = Dict{Symbol, Tuple{Type, DataKnots.AbstractQuery}}()

# As we recursively expand profiles, we need bookkeeping to ensure
# that they are expanded only once. When a profile is encountered for
# a second time, it is unpacked only as a dictonary.
mutable struct Context
   seen::Vector{Symbol}
end

Context() = Context(Vector{Symbol}())

# Do not expand any `Extension` or `Resource` children, these can be
# expressly cast into an appropriate type by the user as required.
profiles_to_ignore = (:Resource, :Extension )

# After we load the profile data from JSON, we use a DataKnot
# query to do the 1st round of processing.

get_base(path::String) = join(split(path, ".")[1:end-1],".")
get_name(path::String) = replace(split(path, ".")[end], "[x]" => "")

UnpackProfile =
  Record(
    It.id >> IsString,
    :kind => Symbol.(It.kind >> IsString),
    :elements =>
       It.snapshot >> IsDict >>
       It.element >> IsVector >> IsDict >>
       Filter((It.max >> IsString) .!= "0") >>
       Record(
         :base => get_base.(It.path),
         :name => get_name.(It.path),
         :mandatory => ((It.min >> IsInt) .!== 0) .&
                        (.! contains.(It.path, "[x]")),
         :singular => ((It.max >> IsString) .== "1"),
         :contentReference => It.contentReference >> IsOptString,
         :type =>
           It.type >> IsOptVector >>
           IsVector >> IsDict >>
           Record(
             :code => It.code >> IsString,
             :extension => It.extension >> IsOptVector >>
               IsVector >> IsDict >>
               Record(
                 :valueUrl => It.valueUrl >> IsOptString,
                 :url => It.url >> IsString,
                 :valueBoolean => It.valueBoolean >> IsOptBool
               )
           )
        ) >> Drop(1) # initial slot refers to self
  )

# This function constructs a query for a given field that represents
# the field primitive or subordinate structure. The context is used
# to ensure we don't visit profiles recursively.
function make_field(ctx::Context, code::String, singular::Bool,
                    mandatory::Bool)::DataKnots.AbstractQuery
    code = Symbol(code)

    if haskey(primitive_registry, code)
        # If it is a known primitive, find the associated native type
        # from the registry and cast the incoming value appropriately.
        (basetype, conversion) = primitive_registry[code]
        return make_declaration(singular, mandatory, basetype) >> conversion
    end

    if haskey(complex_registry, code)
        if code in ctx.seen || code in profiles_to_ignore
            # Don't process certain nested profiles; instead make them
            # available as dictionaries with the correct cardinality.
            return make_declaration(singular, mandatory, StringDict)
        end
        profile = complex_registry[code]
        push!(ctx.seen, code)
        Nested = build_profile(ctx, get(profile[It.id]),
                     profile[It.elements], Symbol("complex-type"))
        @assert code == pop!(ctx.seen)
        return make_declaration(singular, mandatory, StringDict) >> Nested
    end

    return make_declaration(singular, mandatory, Any)
end

# This function returns a query that declares a level in the hierarchy,
# reflecting singular/mandatory properties and the basetype. The `Is`
# combinator makes a type assertion, converting `Any` into a specific
# type so that it could be managed at compile time. In the DataKnots
# model, the cardinality must also be indicated.
function make_declaration(singular::Bool, mandatory::Bool,
                          basetype::Type)::DataKnots.AbstractQuery
    if mandatory
        if singular
            return Is(basetype) >> Is1to1
        end
        return IsVector >> Is(basetype) >> Is1toN
    end
    if singular
        return Is(Union{Missing, basetype}) >> Is0to1
    end
    return AsVector >> Is(basetype) >> Is0toN
end

# Some FHIR fields are variants. When they are converted into a label,
# the underlying datatype is appended, after it's first letter is made
# uppercase; do this as a Julia scalar function rather than in a query.
make_label(name::String, is_variant::Bool, code::String) =
  Symbol(is_variant ? "$(name)$(uppercase(code)[1])$(code[2:end])" : name)

# Essentially, our profile queries build records of fields that are
# nested records or concrete types properly cast.
function build_profile(ctx::Context, base::String, elements::DataKnot,
                       kind::Symbol = :backbone)
    fields = DataKnots.AbstractQuery[]
    if kind == :resource
        # In the XML format, the resource type is the elementname; hence,
        # it is not listed in the profile definition. Regardless, it is
        # a required field for JSON based FHIR data, so we add it here.
        push!(fields, Get(:resourceType) >> IsString)
    end
    for row in get(elements)
        if row[:base] != base
            continue
        end
        name = row[:name]
        singular = row[:singular]
        mandatory = row[:mandatory]
        is_variant = length(row[:type]) > 1
        if length(row[:type]) < 1
            references = row[:contentReference][2:end]
            Declaration = make_declaration(singular, mandatory, StringDict)
            if Symbol(references) in ctx.seen
                push!(fields, Get(Symbol(name)) >> Declaration >>
                                 Label(Symbol(name)))
                continue
            end
            push!(ctx.seen, Symbol(references))
            Nested = build_profile(ctx, references, elements)
            @assert Symbol(references) == pop!(ctx.seen)
            Declaration = make_declaration(singular, mandatory, StringDict)
            push!(fields, Get(Symbol(name)) >> Declaration >> Nested >>
                          Label(Symbol(name)))
            continue
        end
        if "BackboneElement" == row[:type][1][:code]
            Nested = build_profile(ctx, "$(base).$(name)", elements)
            Declaration = make_declaration(singular, mandatory, StringDict)
            push!(fields, Get(Symbol(name)) >> Declaration >> Nested >>
                          Label(Symbol(name)))
            continue
        end
        for alt in row[:type]
            typecode = alt[:code]
            label = make_label(name, is_variant, typecode)
            Query = make_field(ctx, typecode, singular, mandatory)
            push!(fields, Get(label) >> Query >> Label(label))
        end
    end
    push!(fields, It >> Label(:_))
    return Record(fields...)
end

function FHIRInstant(value::String)::ZonedDateTime
    if contains(value, ".")
        return ZonedDateTime(value, "yyyy-mm-ddTHH:MM:SS.ssszzz")
    end
    return ZonedDateTime(value, "yyyy-mm-ddTHH:MM:SSzzz")
end

function FHIRDateTime(value::String)::Union{DateTime, ZonedDateTime}
    if occursin("+", value) ||
       occursin("Z", value) ||
       occursin("-", value[11:end])
        return FHIRInstant(value)
    end
    if occursin("T", value)
        return DateTime(value)
    end
    return DateTime(Date(value))
end

function load_resource_registry()
    if length(resource_registry) != 0
        return
    end

    for fname in readdir(joinpath(artifact"fhir-r4", "fhir-r4"))
        if !endswith(fname, ".profile.canonical.json")
            continue
        end
        item = JSON.parsefile(joinpath(artifact"fhir-r4", "fhir-r4", fname))
        handle = Symbol(item["id"])
        if item["kind"] == "resource"
            knot = convert(DataKnot, item)[UnpackProfile]
            resource_registry[handle] = knot
            continue
        end
        if item["kind"] == "complex-type"
            knot = convert(DataKnot, item)[UnpackProfile]
            complex_registry[handle] = knot
            continue
        end
        if item["kind"] == "primitive-type"
            # This is used to create the proper type assertion, as
            # loaded from JSON; the String type is the default.
            basetypes = Dict{Symbol, DataType}(
                :boolean => Bool, :decimal => Number, :integer => Int,
                :positiveInt => Int, :unsignedInt => Int)
            conversion = Dict{Symbol, DataKnots.AbstractQuery}(
                 :date => Date.(It), :time => Time.(It),
                 :instant => FHIRInstant.(It),
                 :dateTime => FHIRDateTime.(It),
                 :base64Binary => base64decode.(It))
            primitive_registry[handle] =
                tuple(get(basetypes, handle, String),
                      get(conversion, handle, It))
            continue
        end
    end

    # Support the use of FHIRPath URLs for datatype coding.
    for (key, val) in ("Boolean" => Bool, "String" => String,
                       "Integer" => Integer, "Decimal" => Number)
       # TODO: handle Date, DateTime, Time, Quantity
       handle = string("http://hl7.org/fhirpath/System.", key)
       primitive_registry[Symbol(handle)] = tuple(val, It)
    end

end

function load_example_registry()
    if length(example_registry) != 0
        return
    end

    conflicts = Set{Tuple{Symbol, Symbol}}()
    for fname in readdir(joinpath(artifact"fhir-r4", "fhir-r4"))
        if endswith(fname, ".canonical.json") || !contains(fname, "-example")
            continue
        end
        item = JSON.parsefile(joinpath(artifact"fhir-r4", "fhir-r4", fname))
        if haskey(item, "id") && haskey(item, "resourceType")
            handle = (Symbol(item["resourceType"]), Symbol(item["id"]))
            if haskey(example_registry, handle)
                push!(conflicts, handle)
            else
                example_registry[handle] = convert(DataKnot, item)
            end
        end
    end
    # unregister resource examples with duplicate identifiers
    for item in conflicts
        pop!(example_registry, item)
    end
end

# Loop though the profiles and corresponding examples to see that
# each profile query can be run on its corresponding examples.
function sanity_check(version::Symbol = :R4)
    @assert version == :R4
    load_resource_registry()
    load_example_registry()
    for resource in keys(resource_registry)
        println(resource)
        Q = FHIRProfile(version, resource)
        for (rt, id) in keys(example_registry)
            if rt == resource
                println(resource, " ", id)
                ex = FHIRExample(version, resource, id)
                try
                    ex[Q]
                catch e
                    println(resource, " ", id, " ! " , e)
                end
            end
        end
    end
end

"""
    FHIRProfile(version, profile)

This returns a `Query` that reflects the type definition for the given
profile. Note that this generated query profile doesn't expand generic
`Resource` or `Extension` references, nor does it expand recursive occurances
of the same profile.
"""
function FHIRProfile(version::Symbol, profile)
    @assert version == :R4
    ident = Symbol(profile)
    if haskey(profile_registry, ident)
        return profile_registry[ident]
    end
    load_resource_registry()
    if haskey(complex_registry, ident)
        meta = complex_registry[ident]
        return profile_registry[ident] =
            IsDict >>
            build_profile(Context(), get(meta[It.id]),
                          meta[It.elements], Symbol("complex-type")) >>
            Label(ident)
    end
    meta = resource_registry[ident]
    return profile_registry[ident] =
        Filter((It.resourceType >> IsString) .== get(meta[It.id])) >>
        build_profile(Context(), get(meta[It.id]),
                      meta[It.elements], :resource) >>
        Label(ident)
end

"""
    FHIRExample(version, resourceType, id)

This returns a `DataKnot` for an example of a profile provided
in the FHIR specification.
"""
function FHIRExample(version::Symbol, profile, id)
    @assert version == :R4
    load_example_registry()
    return example_registry[(Symbol(profile), Symbol(id))]
end

"""
    FHIRField(version, fieldName)

This function returns glue to access field properties, including `id`
and `extension`. Field values should be accessed though individual, type
specific accessors. The `fieldName` argument should always start with an
underscore, matching the JSON encoding style.
"""
function FHIRField(version::Symbol, fieldName::String)
    @assert startswith(fieldName, "_")
    fieldName = Symbol(fieldName)
    Extension = FHIRProfile(version, :Extension)
    return Record(
       :id    => It >> Get(:_) >> Get(fieldName) >>
                 IsOptDict >> Get(:id) >> IsOptString,
       :extension => It >> Get(:_) >> Get(fieldName) >>
                 IsOptDict >> It.extension >>
                 coalesce.(It, Ref([])) >> Is(Vector) >> Extension
    ) >> Label(fieldName)
end

FHIRField(version::Symbol, fieldName::Symbol) =
    FHIRField(version, String(fieldName))
	
end
