module DataKnots4FHIR

using Base64
using DataKnots
using DataKnots: Query, Environment, Pipeline, ValueOf, BlockOf,
                 target, lookup, cover, uncover, lift, compose,
                 syntaxof, relabel, assemble, designate, fits,
                 relabel, render_value
using Dates
using JSON
using Pkg.Artifacts
using IntervalSets
using TimeZones

import Base: show, parse
import DataKnots: translate, lookup, render_value, Lift, Label, Get

export
    FHIRProfile,
    FHIRExample,
    FHIRField,
    Coding,
    DateTimePeriod,
    years_between,
    @define,
    @valueset

include("helpers.jl")
include("temporal.jl")
include("valueset.jl")
include("profile.jl")
include("quality.jl")

end
