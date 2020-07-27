# We represent `Coding` as a structured value, so that it can be
# worked with as a single value. In a similar way, a `CodeableConcept`
# could be represented as a `Set{Coding}`.

struct Coding
    system::Symbol
    code::Symbol
end

Coding(system::String, code::String) =
    Coding(Symbol(system), Symbol(code))

lookup(ity::Type{Coding}, name::Symbol) =
    lift(getfield, name) |> designate(ity, Symbol)

show(io::IO, c::Coding) =
    print(io, "Coding(\"$(c.system)\",\"$(c.code)\")")

DataKnots.render_value(c::Coding) =
    "$(c.code) [$(c.system)]"

DataKnots.render_value(s::Set{Coding}) =
   join([DataKnots.render_value(x) for x in s], "; ")

# This lets us build a ValueSet query that returns all system/code pairs
# from a UMLS VSAC data source; which is packaged as an artfact.

function ValueSet(oid::String)::Vector{Coding}
    codings = Coding[]
    for line in readlines(joinpath(artifact"vsac-2020", "vsac-2020", oid))
        (system, code) = split(line, ",")
        coding = Coding(Symbol(system), Symbol(code))
        push!(codings, coding)
    end
    return codings
end

macro valueset(expr)
    @assert Meta.isexpr(expr, :(=), 2)
    name = Expr(:quote, expr.args[1])
    query = Lift(ValueSet(string(expr.args[2]))) >> Label(expr.args[1])
    return :(DataKnots.translate(mod::Module, ::Val{$(name)}) = $(query))
end

# The matches() operator lets you verify if a `Coding` matches
# what is in a given value set.

matches(s::Set{Coding}, v::Vector{Coding}) =
    !isempty(intersect(s,v))

Matches(Test) =
    DispatchByType(Set{Coding} => It,
                   Coding => Set{Coding}.(It),
                   Any => It.code) >>
    matches.(It, Test)

translate(mod::Module, ::Val{:matches}, args::Tuple{Any,Vararg{Any}}) =
    Matches(translate.(Ref(mod), args)...)
