// Selected mappings from the NUCC Health Care Provider Taxonomy Code Set,
// version 26.1 (July 2026). NPPES searches use the descriptions; codes are
// retained beside them so the mapping stays auditable.
const DOCTOR_SPECIALTY_TAXONOMIES = Object.freeze({
  Primary: [
    { code: "207Q00000X", description: "Family Medicine" },
    { code: "207R00000X", description: "Internal Medicine" },
    { code: "208D00000X", description: "General Practice" },
  ],
  Cardiologist: [
    { code: "207RC0000X", description: "Cardiovascular Disease" },
  ],
  Orthopedic: [
    { code: "207X00000X", description: "Orthopaedic Surgery" },
  ],
  Neurologist: [
    { code: "2084N0400X", description: "Neurology" },
  ],
  Endocrinologist: [
    {
      code: "207RE0101X",
      description: "Endocrinology, Diabetes & Metabolism",
    },
  ],
  Pulmonologist: [
    { code: "207RP1001X", description: "Pulmonary Disease" },
  ],
  Gastroenterologist: [
    { code: "207RG0100X", description: "Gastroenterology" },
  ],
  Nephrologist: [
    { code: "207RN0300X", description: "Nephrology" },
  ],
  Urologist: [
    { code: "208800000X", description: "Urology" },
  ],
  Oncologist: [
    { code: "207RX0202X", description: "Medical Oncology" },
    { code: "207RH0003X", description: "Hematology & Oncology" },
  ],
  Dermatologist: [
    { code: "207N00000X", description: "Dermatology" },
  ],
  Psychiatrist: [
    { code: "2084P0800X", description: "Psychiatry" },
  ],
  "Pain Management": [
    { code: "208VP0000X", description: "Pain Medicine" },
    { code: "207LP2900X", description: "Pain Medicine" },
    { code: "2081P2900X", description: "Pain Medicine" },
  ],
});

function taxonomiesForSpecialty(specialty) {
  return DOCTOR_SPECIALTY_TAXONOMIES[String(specialty || "").trim()] || [];
}

module.exports = {
  DOCTOR_SPECIALTY_TAXONOMIES,
  taxonomiesForSpecialty,
};
