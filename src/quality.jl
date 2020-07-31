# To run eCQMs on FHIR data could be done by first converting the
# incoming data to the Quality Data Model (QDM).

# First, we need a way to convert FHIR's CodableConcept into something
# that is compatible with the code/system records produced
system_code(url) = Dict{String, String}(
    "http://loinc.org" => "LOINC",
    "http://snomed.info/sct" => "SNOMEDCT",
    "http://www.nlm.nih.gov/research/umls/rxnorm" => "RXNORM",
    "http://unitsofmeasure.org" => "UCUM")[url]

years_between(lhs::Date, rhs::Date) =
    year(lhs) - year(rhs) -
     (month(lhs) > month(rhs) ? 0 :
     (month(lhs) < month(rhs) ? 1 :
     (day(lhs) >= day(rhs) ? 0 : 1)))

years_between(lhs::DateTime, rhs::DateTime) =
     years_between(Date(lhs), Date(rhs))

#translate(mod::Module, ::Val{:years_between}, args::Tuple{Any, 2}) =
#    years_between.(translate.(Ref(mod), args)...)

CodableConcept =
    Set{Coding}.(It.coding >> Coding.(system_code.(It.system), It.code))

QDM_LabTest =
    It.entry.resource >>
    FHIRProfile(:STU3, "Observation") >>
    Filter(It.status .∈  ["final", "amended", "corrected",
                          "preliminary"]) >>
    Record(
      :code => It.code >> CodableConcept >> Is1to1,
      :value => It.valueCodeableConcept >> CodableConcept >> Is1to1,
      :relevantPeriod =>
          DateTime.(It.effectiveDateTime, UTC) >> Is1to1 >>
          ClosedInterval{DateTime}.(It, It)
    ) >> Label(:LaboratoryTestPerformed)

QDM_Encounter =
    It.entry.resource >>
    FHIRProfile(:STU3, "Encounter") >>
    Filter(It.status .∈  ["finished"]) >>
    Record(
     :code => It.type >> CodableConcept >> Is1to1,
     :relevantPeriod =>
         ClosedInterval{DateTime}.(
             DateTime.(It.period.start, UTC) >> Is1to1,
             DateTime.(It.period.end, UTC) >> Is1to1),
    ) >> Label(:EncounterPerformed)

QDM_PatientCharacteristicBirthdate =
    #TODO: use patient-birthTime extension if possible
    It.entry.resource >>
    FHIRProfile(:STU3, "Patient") >> Is1to1 >>
    Record(
     :code => Set{Coding}([Coding(:LOINC, Symbol("21112-8"))]),
     :birthDateTime => DateTime.(It.birthDate) >> Is1to1
    ) >> Label(:PatientCharacteristicBirthdate)

QDM = FHIRProfile(:STU3, "Bundle") >>
      Record(
            QDM_PatientCharacteristicBirthdate,
            QDM_LabTest,
            QDM_Encounter
      )

@define QDM = $QDM
