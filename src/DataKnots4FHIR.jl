module DataKnots4FHIR

using Base64
using DataKnots
using Dates
using JSON
using Pkg.Artifacts
using TimeZones

export
    FHIRProfile,
    FHIRExample

# As a profile query is generated, it consists of type assertions;
# since some of those can be complex, we'll define them here.

IsInt       = Is(Int)
IsBool      = Is(Bool)
IsDict      = Is(Dict{String, Any})
IsString    = Is(String)
IsVector    = Is(Vector{Any})
IsOptInt    = Is(Union{Int, Missing})
IsOptBool   = Is(Union{Bool, Missing})
IsOptDict   = Is(Union{Dict{String, Any}, Missing})
IsOptString = Is(Union{String, Missing})
IsOptVector = Is(Union{Vector{Any}, Missing})

# Since profiles refer to each other, we will create all of them
# in one fell swoop rather than doing it dynamically.

profile_registry = Dict{Symbol, DataKnot}()
example_registry = Dict{Tuple{Symbol, Symbol}, DataKnot}()
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

    if haskey(profile_registry, code)
        if code in ctx.seen || code in profiles_to_ignore
            # Don't process certain nested profiles; instead make them
            # available as dictionaries with the correct cardinality.
            return make_declaration(singular, mandatory, Dict{String, Any})
        end

        profile = profile_registry[code]
        push!(ctx.seen, code)
        Nested = build_profile(ctx, get(profile[It.id]),
                     profile[It.elements], get(profile[It.kind]))
        @assert code == pop!(ctx.seen)
        return make_declaration(singular, mandatory, Dict) >> Nested
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
    return coalesce.(It, Ref([])) >> IsVector >> Is(basetype) >> Is0toN
end

# Some FHIR fields are variants. When they are converted into a label,
# the underlying datatype is appended, after it's first letter is made
# uppercase; do this as a Julia scalar function rather than in a query.
make_label(name::String, is_variant::Bool, code::String) =
  Symbol(is_variant ? "$(name)$(uppercase(code)[1])$(code[2:end])" : name)

# The elements of a profile are hierarchical, but are recorded in a
# flat structure using dotted notation. The `BackboneElement` items
# signify a nested structure, which we build recursively.
BackboneElements(ctx::Context, base::String) =
  Filter(It.base .== base) >>
  Filter(It.type >> (It.code .== "BackboneElement"))

# The remaining elements in a profile can be recursive another way,
# they may be nested resources. This case is handled by `make_field`.
FieldElements(ctx::Context, base::String) =
  Filter(It.base .== base) >>
  Filter("BackboneElement" .∉  It.type.code) >>
  Given(
    :is_variant => Count(It.type) .> 1,
    It.name, It.singular, It.mandatory,
    It.type >>
      Record(
        :label => make_label.(It.name, It.is_variant, It.code),
        :query => make_field.(Ref(ctx), It.code, It.singular, It.mandatory)
      )
  )

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
    for row in get(elements[FieldElements(ctx, base)])
        push!(fields, Get(row[:label]) >> row[:query] >> Label(row[:label]))
    end
    for row in get(elements[BackboneElements(ctx, base)])
        Nested = build_profile(ctx, "$(base).$(row[:name])", elements)
        Declaration = make_declaration(row[:singular], row[:mandatory], Dict)
        push!(fields, Get(Symbol(row[:name])) >> Declaration >>
                        Nested >> Label(Symbol(row[:name])))
    end
    return Record(fields...)
end

function FHIRDateTime(value::String)::ZonedDateTime
    if value[end] == 'Z'
       value = value[1:end-1]
    end
    if length(value) < 11
        return ZonedDateTime(Date(value), tz"UTC")
    end
    if contains(value, "+") || contains(value[11:end], "-")
        if contains(value, ".")
            return ZonedDateTime(value, "yyyy-mm-ddTHH:MM:SS.ssszzz")
        else
            return ZonedDateTime(value, "yyyy-mm-ddTHH:MM:SSzzz")
        end
    end
    return ZonedDateTime(DateTime(value), tz"UTC")
end

# We load all profiles in one fell swoop; note that primitive types
# are tracked and handled in a different global `primitive_registry`.
function load_profile_registry()
    for item in load_json(".profile.json")
        handle = Symbol(item["id"])
        if item["kind"] in ("resource", "complex-type")
            @assert !haskey(profile_registry, handle)
            profile_registry[handle] =
                convert(DataKnot, item)[UnpackProfile]
            continue
        end
        if item["kind"] == "primitive-type"
            # This is used to create the proper type assertion, as
            # loaded from JSON; the String type is the default.
            @assert !haskey(primitive_registry, handle)
            basetypes = Dict{Symbol, DataType}(
                :boolean => Bool, :decimal => Float64, :integer => Int,
                :positiveInt => Int, :unsignedInt => Int)
            conversion = Dict{Symbol, DataKnots.AbstractQuery}(
                 :date => Date.(It), :time => Time.(It),
                 :instant => FHIRDateTime.(It),
                 :dateTime => FHIRDateTime.(It),
                 :base64Binary => base64decode.(It))
            primitive_registry[handle] = tuple(get(basetypes, handle, String),
                                               get(conversion, handle, It))
            continue
        end
        # skipping remaining types, which are logical
        @assert item["kind"] == "logical"
    end

    # Support the use of FHIRPath URLs for datatype coding.
    for (key, val) in ("Boolean" => Bool, "String" => String,
                       "Integer" => Integer, "Decimal" => Float64)
       # TODO: handle Date, DateTime, Time, Quantity
       handle = string("http://hl7.org/fhirpath/System.", key)
       primitive_registry[Symbol(handle)] = tuple(val, It)
    end
end

function load_example_registry()
    conflicts = Set{Tuple{Symbol, Symbol}}()
    for item in load_json("-example.json")
        if haskey(item, "id")
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

# Uses the "fhir-r4" package artifact to load a set of JSON files
# representing profiles or examples from the FHIR specification.
function load_json(postfix)
    items = Dict{String, Any}[]
    for fname in readdir(joinpath(artifact"fhir-r4", "fhir-r4"))
        if !endswith(fname, postfix)
            continue
        end
        item = JSON.parsefile(joinpath(artifact"fhir-r4", "fhir-r4", fname))
        item["handle"] = Symbol(lowercase(chop(fname, tail=length(postfix))))
        push!(items, item)
    end
    return items
end

# Loop though the profiles and corresponding examples to see that
# each profile query can be run on its corresponding examples.
function sanity_check(version::Symbol = :R4)
    @assert version == :R4
    load_profile_registry()
    load_example_registry()
    for resource in keys(profile_registry)
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
    if length(profile_registry) == 0
        load_profile_registry()
    end
    base = IsDict
    meta = profile_registry[Symbol(profile)]
    if :resource == get(meta[It.kind])
         base >>= Filter((It.resourceType >> IsString) .== profile)
    end
    return base >>
           build_profile(Context(), get(meta[It.id]),
                         meta[It.elements], get(meta[It.kind])) >>
           Label(Symbol(profile))
end

"""
    FHIRExample(version, resourceType, id)

This returns a `DataKnot` for an example of a profile provided
in the FHIR specification.
"""
function FHIRExample(version::Symbol, profile, id)
    @assert version == :R4
    if length(example_registry) == 0
       load_example_registry()
    end
    return example_registry[(Symbol(profile), Symbol(id))]
end
	
end
