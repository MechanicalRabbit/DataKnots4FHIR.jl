synthea:
	DOCFILE=building.md julia -L doc/edit.jl
regress:
	julia -e "using DataKnots4FHIR; DataKnots4FHIR.sanity_check(:R4); DataKnots4FHIR.sanity_check(:STU3)"
