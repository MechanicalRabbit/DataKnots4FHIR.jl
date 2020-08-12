#!/usr/bin/env julia

using DataKnots
using DataKnots4FHIR
using Dates
using IntervalSets
using JSON
using Pkg.Artifacts
using BenchmarkTools
using Statistics

increment = 1000 # 1000 patients
stopat = 16000 # 16gb

# use an external process to log memory over the course of a sample
sizings = tempname()
memfile = "/proc/$(Base.Libc.getpid())/statm"
bashcmd = `/bin/bash -c "while :; do cat $(memfile); sleep .05; done"`
parse_sizing(line::String)::Tuple{Float64, Float64} =
   tuple([round(parse(Int, size)*4096 /1000/1000, digits=2)
             for size in split(strip(line), " ")[1:2]]...)
the95th(v::Vector{Float64}) = 
   sort(v)[length(v)-Int64(floor(length(v) *.05))]

# we're going to replicate a 10 person sample database, again and again
folder = joinpath(artifact"synthea-79", "synthea-79", "CMS124v7", "numerator")
ten = []
for fname in readdir(folder)
    push!(ten, JSON.parsefile(joinpath(folder, fname)))
end
db = convert(DataKnot, (bundle=ten,))
@define MeasurePeriod = interval("[2018-01-01..2019-01-01)")
print("defining query...")
@time include(joinpath(@__DIR__, "../doc/src/cms124v7.jl"))
print("binding to QDM...")
@time q = @query bundle.QDM.{Numerator, Denominator, DenominatorExclusions}
print("assemble query...")
@time p = DataKnots.assemble(db, q)
print("compiling........")
@time p(db)
data = []
chunk = []
for x in 1:Int(increment/10)
   append!(chunk, deepcopy(ten))
end
size = round(Base.summarysize(chunk)/1000/1000, digits=2)
println("chunks are $(length(chunk)) patients, $(size)mb")
while true
    global data
    GC.gc(); sleep(1)
    (svirt, sresm) = parse_sizing(read(memfile,String))
    print("$(length(data)), ($(svirt), $(sresm)) ... ")
    timer = run(pipeline(bashcmd, stdout=sizings), wait=false)
    @btime p(convert(DataKnot, (bundle=data,))) samples=5
    kill(timer)
    samples = [parse_sizing(string(line)) for line in
                split(strip(read(sizings, String)), "\n")]
    rm(sizings)
    proc_virt = max([a for (a,b) in samples]...)
    proc_resm = max([b for (a,b) in samples]...)
    diff_virt = round(proc_virt-svirt, digits=2)
    diff_resm = round(proc_resm-sresm, digits=2)
    println(" ($(proc_virt), $(proc_resm)) / (+$(diff_virt), +$(diff_resm))")
    if proc_virt > stopat
       break
    end
    append!(data, deepcopy(chunk))
end
