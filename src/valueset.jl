struct Coding
     code::Symbol
     system::Symbol
end

Coding(code::String, system::String) =
   Coding(Symbol(code), Symbol(system))

lookup(ity::Type{Coding}, name::Symbol) =
    lift(getfield, name) |> designate(ity, Symbol)

show(io::IO, c::Coding) = print(io, "Coding(\"$(c.code)\",\"$(c.system)\")")

DataKnots.render_value(c::Coding) = "$(c.code) [$(c.system)]"

IsCoded(system::String, codes::String...) =
    Exists(
       DispatchByType(Coding => It, Any => It.code) >>
       Filter((It.system .== Symbol(system)) .&
         OneOf(It.code, (Symbol(code) for code in codes)...)))

system_lookup = Dict(
    "LOINC" => "http://loinc.org",
    "SNOMEDCT" => "http://snomed.info/sct",
    "RXNORM" => "http://www.nlm.nih.gov/research/umls/rxnorm",
    "UCUM" => "http://unitsofmeasure.org")

function get_valueset(uuid::String)
    codings = []
    for line in readlines(joinpath(artifact"vsac-2020", "vsac-2020", uuid))
        (system, code) = split(line, ",")
        coding = Coding(Symbol(code), Symbol(system_lookup[system]))
        push!(codings, Ref(coding))
    end
    return Tuple(codings)
end

IsCoded(uuid::String) =
    Exists(
       DispatchByType(Coding => It, Any => It.code) >>
       Filter(OneOf(It, get_valueset(uuid)...)))

translate(mod::Module, ::Val{:iscoded}, args::Tuple{Any,Vararg{Any}}) =
    IsCoded(args...)
