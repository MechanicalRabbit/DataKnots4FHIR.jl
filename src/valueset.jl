# This lets us build a ValueSet query that returns all system/code pairs
# from a UMLS VSAC data source; which is packaged as an artfact.

function ValueSet(oid::String)
    systems = String[]
    codings = String[]
    for line in readlines(joinpath(artifact"vsac-2020", "vsac-2020", oid))
        (system, code) = split(line, ",")
        push!(systems, system)
        push!(codings, code)
    end
    tv = DataKnots.TupleVector(:system => systems, :code => codings)
    return Lift(DataKnot(Any, DataKnots.BlockVector([1, length(tv)+1], tv)))
end

macro valueset(expr)
    @assert Meta.isexpr(expr, :(=), 2)
    name = Expr(:quote, expr.args[1])
    knot = ValueSet(string(expr.args[2]))
    return :(DataKnots.translate(mod::Module, ::Val{$(name)}) =
                 $(knot) >> Label($(name)))
end
