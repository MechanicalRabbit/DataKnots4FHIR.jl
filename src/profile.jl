# belAs a profile query is generated, it consists of type assertions;
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

struct Registry
   standard::Symbol
   profile::Dict{Symbol, DataKnots.AbstractQuery}
   complex::Dict{Symbol, DataKnot}
   example::Dict{Tuple{Symbol, Symbol}, DataKnot}
   resource::Dict{Symbol, DataKnot}
   primitive::Dict{Symbol, Tuple{Type, DataKnots.AbstractQuery}}
   Registry(standard::Symbol) =
     new(standard, Dict(), Dict(), Dict(), Dict(), Dict())
end

registries = Dict(:R4 => Registry(:R4), :STU3 => Registry(:STU3))

# As we recursively expand profiles, we need bookkeeping to ensure
# that they are expanded only once. When a profile is encountered for
# a second time, it is unpacked only as a dictonary.
struct Context
   registry::Registry
   seen::Vector{Symbol}

   Context(standard::Symbol) = new(registries[standard],
                                   Vector{Symbol}())
end

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
         :is_variant => endswith.(It.path, "[x]"),
         :mandatory => ((It.min >> IsInt) .!== 0),
         :singular => ((It.max >> IsString) .== "1"),
         :contentReference => It.contentReference >> IsOptString,
         :typecode => It.type >> IsOptVector >> IsVector >> IsDict >>
                          It.code >> IsString >> Unique
        ) >> Drop(1) # initial slot refers to self
  )

# This function constructs a query for a given field that represents
# the field primitive or subordinate structure. The context is used
# to ensure we don't visit profiles recursively.
function make_field(ctx::Context, code::String, singular::Bool,
                    mandatory::Bool)::DataKnots.AbstractQuery
    code = Symbol(code)

    if haskey(ctx.registry.primitive, code)
        # If it is a known primitive, find the associated native type
        # from the registry and cast the incoming value appropriately.
        (basetype, constandard) = ctx.registry.primitive[code]
        return make_declaration(singular, mandatory, basetype) >> constandard
    end

    if haskey(ctx.registry.complex, code)
        if code in ctx.seen || code in profiles_to_ignore
            # Don't process certain nested profiles; instead make them
            # available as dictionaries with the correct cardinality.
            return make_declaration(singular, mandatory, StringDict)
        end
        profile = ctx.registry.complex[code]
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
make_label_postfix(code::String) = "$(uppercase(code)[1])$(code[2:end])"
make_label(name::String, is_variant::Bool, code::String) =
  Symbol(is_variant ? "$(name)$(make_label_postfix(code))" : name)

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
        is_variant = length(row[:typecode]) > 1
        @assert is_variant == row[:is_variant]
        if length(row[:typecode]) < 1
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
        if "BackboneElement" == row[:typecode][1]
            @assert length(row[:typecode]) == 1
            Nested = build_profile(ctx, "$(base).$(name)", elements)
            Declaration = make_declaration(singular, mandatory, StringDict)
            push!(fields, Get(Symbol(name)) >> Declaration >> Nested >>
                          Label(Symbol(name)))
            continue
        end
        for typecode in row[:typecode]
            label = make_label(name, is_variant, typecode)
            Query = make_field(ctx, typecode, singular,
                               mandatory && !is_variant)
            push!(fields, Get(label) >> Query >> Label(label))
        end
        if is_variant
           Q = Get(make_label(name, true, row[:typecode][1]))
           for typecode in row[:typecode][2:end]
               Q = coalesce.(Q, Get(make_label(name, true, typecode)))
           end
           Declaration = make_declaration(singular, mandatory, Any)
           push!(fields, Q >> Declaration >> Label(Symbol(name)))
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

function load_registry(standard::Symbol)::Registry
    registry = registries[standard]
    if length(registry.resource) != 0
        return registry
    end

    prefix = "fhir-$(lowercase(string(standard)))"
    folder = joinpath(@artifact_str(prefix), prefix)
    for fname in readdir(folder)
        if !endswith(fname, ".profile.canonical.json")
            continue
        end
        item = JSON.parsefile(joinpath(folder, fname))
        handle = Symbol(item["id"])
        if item["kind"] == "resource"
            knot = convert(DataKnot, item)[UnpackProfile]
            registry.resource[handle] = knot
            continue
        end
        if item["kind"] == "complex-type"
            knot = convert(DataKnot, item)[UnpackProfile]
            registry.complex[handle] = knot
            continue
        end
        if item["kind"] == "primitive-type"
            # This is used to create the proper type assertion, as
            # loaded from JSON; the String type is the default.
            basetypes = Dict{Symbol, DataType}(
                :boolean => Bool, :decimal => Number, :integer => Int,
                :positiveInt => Int, :unsignedInt => Int)
            constandard = Dict{Symbol, DataKnots.AbstractQuery}(
                 :date => Date.(It), :time => Time.(It),
                 :instant => FHIRInstant.(It),
                 :dateTime => FHIRDateTime.(It),
                 :base64Binary => base64decode.(It))
            registry.primitive[handle] =
                tuple(get(basetypes, handle, String),
                      get(constandard, handle, It))
            continue
        end
    end

    # Support the use of FHIRPath URLs for datatype coding.
    for (key, val) in ("Boolean" => Bool, "String" => String,
                       "Integer" => Integer, "Decimal" => Number)
       # TODO: handle Date, DateTime, Time, Quantity
       handle = string("http://hl7.org/fhirpath/System.", key)
       registry.primitive[Symbol(handle)] = tuple(val, It)
    end

    return registry
end

function load_examples(standard::Symbol)::Registry
    registry = registries[standard]
    if length(registry.example) != 0
        return registry
    end
    conflicts = Set{Tuple{Symbol, Symbol}}()

    prefix = "fhir-$(lowercase(string(standard)))"
    folder = joinpath(@artifact_str(prefix), prefix)
    for fname in readdir(folder)
        if endswith(fname, ".canonical.json") || !contains(fname, "-example")
            continue
        end
        item = JSON.parsefile(joinpath(folder, fname))
        if haskey(item, "id") && haskey(item, "resourceType")
            handle = (Symbol(item["resourceType"]), Symbol(item["id"]))
            if haskey(registry.example, handle)
                push!(conflicts, handle)
            else
                registry.example[handle] = convert(DataKnot, item)
            end
        end
    end
    # unregister resource examples with duplicate identifiers
    for item in conflicts
        pop!(registry.example, item)
    end
    return registry
end

# Loop though the profiles and corresponding examples to see that
# each profile query can be run on its corresponding examples.
function sanity_check(standard::Symbol)
    load_registry(standard)
    load_examples(standard)
    registry = registries[standard]
    for resource in keys(registry.resource)
        println(standard, " ", resource)
        Q = FHIRProfile(standard, resource)
        for (rt, id) in keys(registry.example)
            if rt == resource
                println(standard, " ", resource, " ", id)
                ex = FHIRExample(standard, resource, id)
                try
                    ex[Q]
                catch e
                    println(standard, " ", resource, " ", id, " ! " , e)
                end
            end
        end
    end
end

"""
    FHIRProfile(standard, profile)

This returns a `Query` that reflects the type definition for the given
profile. Note that this generated query profile doesn't expand generic
`Resource` or `Extension` references, nor does it expand recursive occurances
of the same profile.
"""
function FHIRProfile(standard::Symbol, profile)
    registry = load_registry(standard)
    ident = Symbol(profile)
    if haskey(registry.profile, ident)
        return registry.profile[ident]
    end
    if haskey(registry.complex, ident)
        meta = registry.complex[ident]
        return registry.profile[ident] =
            IsDict >>
            build_profile(Context(standard), get(meta[It.id]),
                          meta[It.elements], Symbol("complex-type")) >>
            Label(ident)
    end
    meta = registry.resource[ident]
    return registry.profile[ident] =
        IsDict >>
        Filter((It.resourceType >> IsString) .== get(meta[It.id])) >>
        build_profile(Context(standard), get(meta[It.id]),
                      meta[It.elements], :resource) >>
        Label(ident)
end

"""
    FHIRExample(standard, resourceType, id)

This returns a `DataKnot` for an example of a profile provided
in the FHIR specification.
"""
function FHIRExample(standard::Symbol, profile, id)
    registry = load_examples(standard)
    return registry.example[(Symbol(profile), Symbol(id))]
end

"""
    FHIRField(standard, fieldName)

This function returns glue to access field properties, including `id`
and `extension`. Field values should be accessed though individual, type
specific accessors. The `fieldName` argument should always start with an
underscore, matching the JSON encoding style.
"""
function FHIRField(standard::Symbol, fieldName::String)
    @assert startswith(fieldName, "_")
    fieldName = Symbol(fieldName)
    Extension = FHIRProfile(standard, :Extension)
    return Record(
       :id    => It >> Get(:_) >> Get(fieldName) >>
                 IsOptDict >> Get(:id) >> IsOptString,
       :extension => It >> Get(:_) >> Get(fieldName) >>
                 IsOptDict >> It.extension >>
                 coalesce.(It, Ref([])) >> Is(Vector) >> Extension
    ) >> Label(fieldName)
end

FHIRField(standard::Symbol, fieldName::Symbol) =
    FHIRField(standard, String(fieldName))

# translate to macro forms that use string arguments

translate(mod::Module, ::Val{:fhir_profile}, args::Tuple{String, String}) =
  FHIRProfile(Symbol(args[1]), args[2])

translate(mod::Module, ::Val{:fhir_field}, args::Tuple{String, String}) =
  FHIRField(Symbol(args[1]), args[2])
