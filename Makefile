synthea:
	DOCFILE=cms124v7.md julia -L doc/edit.jl
regress:
	julia -e "using DataKnots4FHIR; DataKnots4FHIR.sanity_check()"
