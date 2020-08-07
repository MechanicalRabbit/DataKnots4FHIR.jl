@valueset EncounterInpatient = "2.16.840.1.113883.3.666.5.307"
@valueset HospiceCareAmbulatory = "2.16.840.1.113762.1.4.1108.15"

@define DischargeForHospiceCare = valueset("SNOMEDCT", "428371000124100",
                                           "428361000124107")
@define HasHospice =
          exists(
            EncounterPerformed.
              filter(code.matches(EncounterInpatient) &&
                dischargeDisposition.matches(DischargeForHospiceCare))) ||
          exists(
            InterventionOrder.
              filter(code.matches(HospiceCareAmbulatory) &&
                authorDateTime.during(MeasurePeriod))) ||
          exists(
            InterventionPerformed.
              filter(code.matches(HospiceCareAmbulatory) &&
                relevantPeriod.overlaps(MeasurePeriod)))
