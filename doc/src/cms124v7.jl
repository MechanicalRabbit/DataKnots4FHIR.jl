## CMS124v7 - Cervical Cancer Screening

module CMS124

using DataKnots
using DataKnots4FHIR

@valueset ONC_Administrative_Sex = "2.16.840.1.113762.1.4.1"
@valueset Race = "2.16.840.1.114222.4.11.836"
@valueset Ethnicity = "2.16.840.1.114222.4.11.837"
@valueset Payer = "2.16.840.1.114222.4.11.3591"
@valueset Female = "2.16.840.1.113883.3.560.100.2"
@valueset Home_Healthcare_Services = "2.16.840.1.113883.3.464.1003.101.12.1016"
@valueset Hysterectomy_with_No_Residual_Cervix = "2.16.840.1.113883.3.464.1003.198.12.1014"
@valueset Office_Visit = "2.16.840.1.113883.3.464.1003.101.12.1001"
@valueset Pap_Test = "2.16.840.1.113883.3.464.1003.108.12.1017"
@valueset Preventative_Care_Services__Established_Office_Visit_18andUp = "2.16.840.1.113883.3.464.1003.101.12.1025"
@valueset Preventative_Care_Services__Initial_Office_Visit_18andUp = "2.16.840.1.113883.3.464.1003.101.12.1023"
@valueset HPV_Test = "2.16.840.1.113883.3.464.1003.110.12.1059"

@define PapTestWithResults =
            LaboratoryTestPerformed.
                filter(code.matches(Pap_Test) & exists(value))

@define PapTestWithin3Years =
          PapTestWithResults.
          filter(relevantPeriod.start >
                 MeasurePeriod.end - 3years)

end
