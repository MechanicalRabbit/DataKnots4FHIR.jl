AnyOf(Xs...) = Lift(|, (Xs...,))
OneOf(X, Ys...) = AnyOf((X .== Y for Y in Ys)...)

IsCoded(system, codes...) =
   Exists(It.coding >> Filter(
      (It.system .== string.(system)) .&
      OneOf(It.code, (string.(code) for code in codes)...)))

translate(mod::Module, ::Val{:iscoded}, args::Tuple{Any,Vararg{Any}}) =
    IsCoded(translate.(Ref(mod), args)...)
