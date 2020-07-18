# This macro lets us `@define` reusable queries using the macro syntax;
# it's not standard DataKnots, but it makes building queries more fluid.
# For now, we handle only zero argument definitions.

macro define(expr)
    @assert Meta.isexpr(expr, :(=), 2)
    body = :(translate($__module__, $(Expr(:quote, expr.args[2]))))
    if typeof(expr.args[1]) == Symbol
        name = Expr(:quote, expr.args[1])
        return :(DataKnots.translate(mod::Module, ::Val{$(name)}) = $(body))
    end
    call = expr.args[1]
    @assert Meta.isexpr(call, :call, 1)
    name = Expr(:quote, call.args[1])
    return :(DataKnots.translate(mod::Module, ::Val{$(name)},
                                 ::Tuple{}) = $(body))
end

# For the QDM we deal with symbols having spaces...

DataKnots.Get(s::String) = Get(Symbol(s))

# Temporary sort since it's not implemented yet, it happens that
# group provides the functionality needed though.

DataKnots.Label(::Nothing) = Query(Label, nothing);
DataKnots.Label(::Environment, p::Pipeline, ::Nothing) =
    relabel(p, nothing)

Sort(X) = Given(:source => It, Group(X) >> It.source >> Label(nothing))

translate(mod::Module, ::Val{:sort}, args::Tuple{Any}) =
    Sort(translate.(Ref(mod), args)...)

# Checking to see if a value is within a list

In(Xs...) = in.(It, Lift(tuple, (Xs...,)))

translate(mod::Module, ::Val{:in}, args::Tuple{Vararg{Any}}) =
    In(translate.(Ref(mod), args)...)

#
# Sometimes we wish to do dispatch by the type of input elements. For
# example, if the input is already a date we may wish to treat it a
# particular way, otherwise we may want to make it a date first.
#

DispatchByType(tests::Pair{DataType}...) =
    Query(DispatchByType, collect(Pair{DataType}, tests))

function DispatchByType(env::Environment, p::Pipeline,
                        tests::Vector{Pair{DataType}})
    for (typ, query) in tests
        if fits(target(uncover(p)), BlockOf(ValueOf(typ)))
            return assemble(env, p, query)
        end
    end
    error("doesn't match any type: $(syntaxof(target(p)))")
end

