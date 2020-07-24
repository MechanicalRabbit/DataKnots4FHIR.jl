# We represent `Coding` as a single value type.

struct Coding
    system::Symbol
    code::Symbol
end

Coding(system::String, code::String) =
   Coding(Symbol(system), Symbol(code))

lookup(ity::Type{Coding}, name::Symbol) =
    lift(getfield, name) |> designate(ity, Symbol)

show(io::IO, c::Coding) = print(io, "Coding(\"$(c.system)\",\"$(c.code)\")")

DataKnots.render_value(c::Coding) = "$(c.code) [$(c.system)]"

# This lets us build a ValueSet query that returns all system/code pairs
# from a UMLS VSAC data source; which is packaged as an artfact.

function ValueSet(oid::String)
    codings = []
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
