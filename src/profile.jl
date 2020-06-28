using Pkg.Artifacts
using JSON

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

profile_registry = Dict{Symbol, DataKnot}()
example_registry = Dict{Tuple{Symbol, Symbol}, DataKnot}()
primitive_registry = Dict{Symbol, Type}()

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

""" Context

As we recursively expand profiles, bookkeep to ensure that they are
only expanded once. Moreover, there are some profiles that are never
expanded and others that are expanded only one level.
"""
mutable struct Context
   seen::Vector{Symbol}
   flatten::Bool
end
Context() = Context(Vector{Symbol}(), false)
profiles_to_flatten = (:Extension, )
profiles_to_ignore = (:Resource, )

""" make_field

To build the query to extract the subordinate structure. This is
complicated since FHIR structures are recursive. The profile
expansion context is used to bookeep what is to be expanded.
"""
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
            # do not further unpack this resource
            return make_declaration(singular, mandatory, Dict)
        end

        profile = profile_registry[code]
        push!(ctx.seen, code)
        ctx.flatten = code in profiles_to_flatten
        Nested = build_profile(ctx, profile[It.elements],
                               get(profile[It.id]))
        ctx.flatten = false
        @assert code == pop!(ctx.seen)
        return make_declaration(singular, mandatory, Dict) >> Nested
    end
    return make_declaration(singular, mandatory, Any)
end

""" make_declaration

This function returns a query that declares a level in the hierarchy,
reflecting singular/mandatory properties and the basetype. The `Is`
combinator makes a type assertion, converting `Any` into a specific
type so that it could be managed at compile time. In the DataKnots
model, the cardinality must also be indicated.
"""
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

""" make_label

Some FHIR fields are variants. When they are converted into a label,
the underlying datatype is appended, after it's first letter is made
uppercase. This is a minor operation, but easier to do in Julia.
"""
make_label(name::String, is_variant::Bool, code::String) =
  Symbol(is_variant ? "$(name)$(uppercase(code)[1])$(code[2:end])" : name)


""" Unpack

"""
UnpackFields(ctx::Context) =
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

function build_profile(ctx::Context, elements::DataKnot, base::String,
                       top::Bool = false)
    fields = DataKnots.AbstractQuery[]
    if top
        push!(fields, Get(:resourceType) >> IsString)
    end
    for row in get(elements[Filter(It.base .== base) >> UnpackFields(ctx)])
       if row[:label] == :extension
           continue  # TODO: enable extension recursion smartly
       end
       push!(fields, Get(row[:label]) >> row[:query] >> Label(row[:label]))
    end
    for row in get(elements[Filter(It.base .== base) >>
                       Filter(It.type >> (It.code .== "BackboneElement"))])
        Nested = build_profile(ctx, elements, "$(base).$(row[:name])")
        Declaration = make_declaration(row[:singular], row[:mandatory], Dict)
        push!(fields, Get(Symbol(row[:name])) >> Declaration >> Nested >>
                                                 Label(Symbol(row[:name])))
    end
    return Record(fields...)
end

function FHIRProfile(version::Symbol, resourceType)
    @assert version == :R4
    if length(profile_registry) == 0
       load_profile_registry()
    end
    meta = profile_registry[Symbol(resourceType)]
    return IsDict >>
           Filter((It.resourceType >> IsString) .== resourceType) >>
           build_profile(Context(), meta[It.elements],
                         get(meta[It.id]), true) >>
           Label(Symbol(resourceType))
end

function FHIRExample(version::Symbol, resourceType, id)
    @assert version == :R4
    if length(example_registry) == 0
       load_example_registry()
    end
    return example_registry[(Symbol(resourceType), Symbol(id))]
end

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

function FHIRSpecificationInventory(version::Symbol)
    @assert version == :R4
    load_profile_registry()
    load_example_registry()
    inventory = Dict{Symbol, Vector{Symbol}}()
    for resourceType in keys(profile_registry)
         examples = Vector{Symbol}()
         for (rt, id) in keys(example_registry)
             if rt == resourceType
                 push!(examples, id)
             end
         end
         inventory[resourceType] = examples
    end
    return inventory
end

function regression()
    println("regression test....")
    inventory = FHIRSpecificationInventory(:R4)
    for profile in keys(inventory)
        println(profile)
        Q = FHIRProfile(:R4, profile)
        for ident in inventory[profile]
            println(profile, " ", ident)
            ex = FHIRExample(:R4, profile, ident)
            try
               ex[Q]
            catch e
               println(profile, " ", ident, " ! " , e)
            end
        end
    end
end

