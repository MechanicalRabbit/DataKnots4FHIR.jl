struct Coding
     system::Symbol
     code::Symbol
end

Coding(system::String, code::String) =
   Coding(Symbol(system), Symbol(code))

show(io::IO, c::Coding) = print(io, "$(c.code) [$(c.system)]")

AnyOf(Xs...) = Lift(|, (Xs...,))
OneOf(X, Ys...) = AnyOf((X .== Y for Y in Ys)...)

IsCoded(system, codes...) =
   Exists(It.coding >> Filter(
      (It.system .== string.(system)) .&
      OneOf(It.code, (string.(code) for code in codes)...)))

translate(mod::Module, ::Val{:iscoded}, args::Tuple{Any,Vararg{Any}}) =
    IsCoded(translate.(Ref(mod), args)...)
