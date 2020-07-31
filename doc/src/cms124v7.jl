## CMS124v7 - Cervical Cancer Screening

module CMS124

using DataKnots
using DataKnots4FHIR

@valueset ONCAdministrativeSex = "2.16.840.1.113762.1.4.1"
@valueset Race = "2.16.840.1.114222.4.11.836"
@valueset Ethnicity = "2.16.840.1.114222.4.11.837"
@valueset Payer = "2.16.840.1.114222.4.11.3591"
@valueset Female = "2.16.840.1.113883.3.560.100.2"
@valueset HomeHealthcareServices = "2.16.840.1.113883.3.464.1003.101.12.1016"
@valueset HysterectomywithNoResidualCervix = "2.16.840.1.113883.3.464.1003.198.12.1014"
@valueset OfficeVisit = "2.16.840.1.113883.3.464.1003.101.12.1001"
@valueset PapTest = "2.16.840.1.113883.3.464.1003.108.12.1017"
@valueset PreventativeCareServices_EstablishedOfficeVisit18andUp = "2.16.840.1.113883.3.464.1003.101.12.1025"
@valueset PreventativeCareServices_InitialOfficeVisit18andUp = "2.16.840.1.113883.3.464.1003.101.12.1023"
@valueset HPVTest = "2.16.840.1.113883.3.464.1003.110.12.1059"

@define PapTestWithResults =
          LaboratoryTestPerformed.
            filter(code.matches(PapTest) && exists(value))

@define PapTestWithin3Years =
          let previous3years => MeasurePeriod.end.and_previous(3years)
            PapTestWithResults.
            filter(relevantPeriod.during(previous3years))
          end

@define QualifyingEncounters =
          EncounterPerformed.
            filter(relevantPeriod.during(MeasurePeriod) &&
              code.matches(
                OfficeVisit,
                PreventativeCareServices_EstablishedOfficeVisit18andUp,
                PreventativeCareServices_InitialOfficeVisit18andUp,
                HomeHealthcareServices))

@define PapTestWithin5Years =
          let birthDate => PatientCharacteristicBirthdate.birthDateTime,
              previous5years => MeasurePeriod.end.and_previous(5years)
            PapTestWithResults.
            filter(years_between(relevantPeriod.start, birthDate) >= 30 &&
                   relevantPeriod.during(previous5years))
          end

@define PapTestWithHPVWithin5Years =
          let NearbyTest => LaboratoryTestPerformed.
                            filter(code.matches(HPVTest) && exists(value))
            PapTestWithin5Years.
            filter(relevantPeriod.start.
                    and_previous(1days).
                    and_subsequent(1days).
                    includes_any(NearbyTest.relevantPeriod.start))
          end 

end
