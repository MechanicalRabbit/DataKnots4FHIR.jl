synthea:
	DOCFILE=synthea.md julia -L doc/edit.jl
regress:
	julia -e "using DataKnots4FHIR; DataKnots4FHIR.sanity_check()"
