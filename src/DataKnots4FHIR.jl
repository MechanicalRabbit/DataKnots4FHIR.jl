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
using TimeZones

import Base: show
import DataKnots: translate, lookup, render_value, Lift, Label, Get

export
    FHIRProfile,
    FHIRExample,
    FHIRField,
    Coding,
    DateTimePeriod,
    @define

include("helpers.jl")
include("temporal.jl")
include("valueset.jl")
include("profile.jl")
include("model.jl")

end
