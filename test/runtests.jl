#!/usr/bin/env julia

using DataKnots
using DataKnots4FHIR
using NarrativeTest

args = !isempty(ARGS) ? ARGS : [relpath(joinpath(dirname(abspath(PROGRAM_FILE)), "../doc/src"))]
exit(!runtests(args))
