// Selected mappings from the NUCC Health Care Provider Taxonomy Code Set.
// NPPES searches use the descriptions; codes stay beside them for validation.
const NPI_TAXONOMY_MAPPING_VERSION = "26.1";
const NPI_TAXONOMY_MAPPING_RELEASE = "July 2026";

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
  "Psychologist / Clinical Psychologist": [
    { code: "103T00000X", description: "Psychologist" },
    { code: "103TC0700X", description: "Psychologist" },
  ],
  "Clinical Social Worker": [
    { code: "1041C0700X", description: "Social Worker" },
  ],
  "Professional Counselor": [
    { code: "101YP2500X", description: "Professional" },
  ],
  "Mental Health Counselor": [
    { code: "101YM0800X", description: "Mental Health" },
  ],
  "Marriage & Family Therapist": [
    { code: "106H00000X", description: "Marriage & Family Therapist" },
  ],
  "Psychiatric Nurse Practitioner": [
    { code: "363LP0808X", description: "Psych/Mental Health" },
  ],
  "Addiction Counselor": [
    {
      code: "101YA0400X",
      description: "Addiction (Substance Use Disorder)",
    },
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
  NPI_TAXONOMY_MAPPING_RELEASE,
  NPI_TAXONOMY_MAPPING_VERSION,
  taxonomiesForSpecialty,
};
