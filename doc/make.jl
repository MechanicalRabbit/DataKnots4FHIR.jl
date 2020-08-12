#!/usr/bin/env julia

using Documenter
using DataKnots4FHIR

# Highlight indented code blocks as Julia code.
using Documenter.Expanders: ExpanderPipeline, Selectors, Markdown, iscode
abstract type DefaultLanguage <: ExpanderPipeline end
Selectors.order(::Type{DefaultLanguage}) = 99.0
Selectors.matcher(::Type{DefaultLanguage}, node, page, doc) =
    iscode(node, "")
Selectors.runner(::Type{DefaultLanguage}, node, page, doc) =
    page.mapping[node] = Markdown.Code("julia", node.code)

makedocs(
    sitename = "DataKnots4FHIR.jl",
    format = Documenter.HTML(prettyurls=(get(ENV, "CI", nothing) == "true")),
    pages = [
        "Overview" => "overview.md",
        "Profile" => "profile.md",
        "An eCQM" => "ecqm.md",
    ],
    modules = [DataKnots4FHIR])

deploydocs(
    repo = "github.com/rbt-lang/DataKnots4FHIR.jl.git",
)
