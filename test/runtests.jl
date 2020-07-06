#!/usr/bin/env julia

using Dates
using NarrativeTest
using Pkg.Artifacts

# pre-download bundles
fhir_r4 = artifact"fhir-r4"
synthea = artifact"synthea-116"

args = !isempty(ARGS) ? ARGS : [relpath(joinpath(dirname(abspath(PROGRAM_FILE)), "../doc/src"))]
exit(!runtests(args))
