struct Coding
     system::Symbol
     code::Symbol
end

Coding(system::String, code::String) =
   Coding(Symbol(system), Symbol(code))

lookup(ity::Type{Coding}, name::Symbol) =
    lift(getfield, name) |> designate(ity, Symbol)

show(io::IO, c::Coding) = print(io, "$(c.code) [$(c.system)]")

IsCoded(system, codes...) =
    DispatchByType(Coding => It, Any => It.code) >>
    Exists(It >> Filter(
      (It.system .== Symbol.(system)) .&
      OneOf(It.code, (Symbol.(code) for code in codes)...)))

translate(mod::Module, ::Val{:iscoded}, args::Tuple{Any,Vararg{Any}}) =
    IsCoded(translate.(Ref(mod), args)...)
