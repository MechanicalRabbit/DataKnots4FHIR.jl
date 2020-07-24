# To run eCQMs on FHIR data could be done by first converting the
# incoming data to the Quality Data Model (QDM).

# First, we need a way to convert FHIR's CodableConcept into something
# that is compatible with the code/system records produced
system_lookup = Dict{String, String}(
    "http://loinc.org" => "LOINC",
    "http://snomed.info/sct" => "SNOMEDCT",
    "http://www.nlm.nih.gov/research/umls/rxnorm" => "RXNORM",
    "http://unitsofmeasure.org" => "UCUM")

CodableConcept =
    It.coding >> Coding.(
            Lift(x->system_lookup[x], (It.system,)) >> Is(String),
            It.code >> Is1to1)

QDM_LabTest =
    It.entry.resource >>
    FHIRProfile(:STU3, "Observation") >>
    Filter(It.status .∈  ["final", "amended", "corrected",
                          "preliminary"]) >>
    Record(
      :code => It.code >> CodableConcept >> Is1toN,
      :value => It.valueCodeableConcept >> CodableConcept >> Is1toN,
      :relevantPeriod =>
          DateTime.(It.effectiveDateTime, UTC) >> Is1to1 >>
          DateTimePeriod.(It, It)
    ) >> Label(:LaboratoryTestPerformed)

QDM = FHIRProfile(:STU3, "Bundle") >>
      Record(
         QDM_LabTest
      )

@define QDM = $QDM
