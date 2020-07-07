using NarrativeTest

make() = withenv("LINES"=>11, "COLUMNS"=>72) do
             Base.active_repl.options.
                iocontext[:displaysize] = (convert(Integer, 
                   trunc(displaysize(Base.stdout)[1] * 2/3)), 72)
             runtests(joinpath("doc/src", ENV["DOCFILE"]), mod=Main)
         end

atreplinit() do repl
    try
        @eval using BenchmarkTools: @btime
        @eval using Revise
        @eval make()
        @eval using DataKnots
        @eval using DataKnots4FHIR
        @async Revise.wait_steal_repl_backend()
    catch
        @warn "startup error?"
    end
end

