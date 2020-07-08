module DataKnots4FHIR

using Base64
using DataKnots
using DataKnots: Query, Environment, Pipeline, ValueOf, BlockOf,
                 target, lookup, cover, uncover, lift, compose,
                 syntaxof, relabel, assemble, designate, fits, relabel
using Dates
using JSON
using Pkg.Artifacts
using TimeZones

import Base: show
import DataKnots: translate, lookup, Lift, Label

export
    FHIRProfile,
    FHIRExample,
    FHIRField

include("profile.jl")
include("helpers.jl")
include("temporal.jl")
	
end
