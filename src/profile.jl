using Pkg.Artifacts
using JSON

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
primitive_registry = Dict{Symbol, Type}()

# As we recursively expand profiles, we need bookkeeping to ensure
# that they are expanded only once. Moreover, there are some profiles
# that should only have its primitive attributes expanded, leaving
# referenced profile data to be `Any` in the incoming data.
mutable struct Context
   seen::Vector{Symbol}
   flatten::Bool
end

Context() = Context(Vector{Symbol}(), false)

# At this time, we leave `Resource` elements unexpanded and we
# do not expand any `Resource` children of `Extension` profiles.
profiles_to_flatten = (:Extension, )
profiles_to_ignore = (:Resource, )

# After we load the profile data from JSON, we use a DataKnot
# query to do the 1st round of processing.

get_base(path::String) = join(split(path, ".")[1:end-1],".")
get_name(path::String) = replace(split(path, ".")[end], "[x]" => "")

UnpackProfile =
  Record(
    It.id >> IsString,
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
        return make_declaration(singular, mandatory, primitive_registry[code])
    end

    if haskey(profile_registry, code)
        if ctx.flatten || code in ctx.seen || code in profiles_to_ignore
            # Don't process certain nested profiles; instead make them
            # available as dictionaries with the correct cardinality.
            return make_declaration(singular, mandatory, Dict)
        end

        profile = profile_registry[code]
        push!(ctx.seen, code)
        ctx.flatten = code in profiles_to_flatten
        Nested = build_profile(ctx, get(profile[It.id]), profile[It.elements])
        ctx.flatten = false
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
                       top::Bool = false)
    fields = DataKnots.AbstractQuery[]
    if top
        # In the XML format, the resource type is the elementname; hence,
        # it is not listed in the profile definition. Regardless, it is
        # a required field for JSON based FHIR data, so we add it here.
        push!(fields, Get(:resourceType) >> IsString)
    end
    for row in get(elements[FieldElements(ctx, base)])
        if row[:label] == :extension
            # TODO: at this time, don't expand extensions till we know
            # usage considerations; expanding extensions more than doubles
            # the profile construction time.
            continue
        end
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

# We load all profiles in one fell swoop; note that primitive types
# are tracked and handled in a different global `primitive_registry`.
function load_profile_registry()
    for item in load_json(".profile.json")
        handle = Symbol(item["id"])
        if item["kind"] != "primitive-type"
            @assert !haskey(profile_registry, handle)
            profile_registry[handle] =
                convert(DataKnot, item)[UnpackProfile]
            continue
        end
        @assert !haskey(primitive_registry, handle)
        lookup = Dict{Symbol, DataType}(
           :string => String,
           :boolean => Bool,
           :integer => Int,
           :code => String,
           :uri => String,
           :text => String)
        primitive_registry[handle] = get(lookup, handle, Any)
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
    for profile in keys(profile_registry)
        println(profile)
        Q = FHIRProfile(version, profile)
        for (rt, id) in keys(example_registry)
            if rt == profile
                println(profile, " ", id)
                ex = FHIRExample(version, profile, id)
                try
                    ex[Q]
                catch e
                    println(profile, " ", id, " ! " , e)
                end
            end
        end
    end
end

"""
    FHIRProfile(version, resourceType)

This returns a `Query` that reflects the type definition for the given
ResourceType. Note that this query profile doesn't expand generic
`Resource` references, nor does it expand recursive occurances of the
same resource type.
"""
function FHIRProfile(version::Symbol, resourceType)
    @assert version == :R4
    if length(profile_registry) == 0
        load_profile_registry()
    end
    meta = profile_registry[Symbol(resourceType)]
    return IsDict >>
           Filter((It.resourceType >> IsString) .== resourceType) >>
           build_profile(Context(), get(meta[It.id]),
                         meta[It.elements], true) >>
           Label(Symbol(resourceType))
end

"""
    FHIRExample(version, resourceType, id)

This returns a `DataKnot` for an example of a resource type provided
in the FHIR specification.
"""
function FHIRExample(version::Symbol, resourceType, id)
    @assert version == :R4
    if length(example_registry) == 0
       load_example_registry()
    end
    return example_registry[(Symbol(resourceType), Symbol(id))]
end
