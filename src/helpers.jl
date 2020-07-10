# This macro lets us `@define` reusable queries using the macro syntax;
# it's not standard DataKnots, but it makes building queries more fluid.
# For now, we handle only zero argument definitions.

macro define(expr)
    @assert Meta.isexpr(expr, :(=))
    call = expr.args[1]
    @assert Meta.isexpr(call, :call, 1)
    name = Expr(:quote, call.args[1])
    body = :(translate($__module__, $(Expr(:quote, expr.args[2]))))
    return :(DataKnots.translate(mod::Module, ::Val{$(name)},
                                 ::Tuple{}) = $(body))
end

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
