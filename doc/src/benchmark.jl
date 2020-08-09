using DataKnots
using DataKnots4FHIR
using Dates
using IntervalSets
using JSON
using Pkg.Artifacts
using BenchmarkTools

folder = joinpath(artifact"synthea-79", "synthea-79", "CMS124v7", "numerator")
ten = []
for fname in readdir(folder)
    push!(ten, JSON.parsefile(joinpath(folder, fname)))
end
db = convert(DataKnot, (bundle=ten,))
@define MeasurePeriod = interval("[2018-01-01..2019-01-01)")
print("defining query...")
@time include("cms124v7.jl")
print("binding to QDM...")
@time q = @query bundle.QDM.{Numerator, Denominator, DenominatorExclusions}
print("assemble query...")
@time p = DataKnots.assemble(db, q) 
print("compiling........")
@time p(db)
print("again............")
@btime p(db) samples=5
data = []
chunk = [] # let's do 25000 patients blocks
for x in 1:2500
   append!(chunk, ten)
end
while true
    global data
    print("sz=$(length(data))")
    @btime p(convert(DataKnot, (bundle=data,))) samples=5
    append!(data, chunk)
end
