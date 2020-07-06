#!/usr/bin/env julia

using DataKnots
using DataKnots4FHIR
using NarrativeTest
using Pkg.Artifacts

# pre-download bundles
fhir_r4 = artifact"fhir-r4"
synthea = artifact"synthea-116"

args = !isempty(ARGS) ? ARGS : [relpath(joinpath(dirname(abspath(PROGRAM_FILE)), "../doc/src"))]
exit(!runtests(args))
