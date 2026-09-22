const test = require("node:test");
const assert = require("node:assert/strict");

const {
  DOCTOR_SPECIALTY_TAXONOMIES,
  taxonomiesForSpecialty,
} = require("../functions/services/npi-taxonomies");

test("every filterable doctor dropdown option has an audited taxonomy mapping", () => {
  const filterableOptions = [
    "Primary",
    "Cardiologist",
    "Orthopedic",
    "Neurologist",
    "Endocrinologist",
    "Pulmonologist",
    "Gastroenterologist",
    "Nephrologist",
    "Urologist",
    "Oncologist",
    "Dermatologist",
    "Psychiatrist",
    "Psychologist / Clinical Psychologist",
    "Clinical Social Worker",
    "Professional Counselor",
    "Mental Health Counselor",
    "Marriage & Family Therapist",
    "Psychiatric Nurse Practitioner",
    "Addiction Counselor",
    "Pain Management",
  ];

  for (const option of filterableOptions) {
    const mappings = DOCTOR_SPECIALTY_TAXONOMIES[option];
    assert.ok(mappings?.length, `${option} is missing a taxonomy mapping`);
    for (const mapping of mappings) {
      assert.match(mapping.code, /^[A-Z0-9]{10}$/);
      assert.ok(mapping.description.length > 2);
    }
  }
});

test("mental health provider types map to exact audited taxonomy codes", () => {
  assert.deepEqual(
    taxonomiesForSpecialty("Psychologist / Clinical Psychologist").map(
      (item) => item.code,
    ),
    ["103T00000X", "103TC0700X"],
  );
  assert.deepEqual(
    taxonomiesForSpecialty("Clinical Social Worker").map((item) => item.code),
    ["1041C0700X"],
  );
  assert.deepEqual(
    taxonomiesForSpecialty("Psychiatric Nurse Practitioner").map(
      (item) => item.code,
    ),
    ["363LP0808X"],
  );
});

test("free-text Other is intentionally never sent as a taxonomy filter", () => {
  assert.deepEqual(taxonomiesForSpecialty("Other"), []);
  assert.deepEqual(taxonomiesForSpecialty("made up specialty"), []);
});

test("primary care searches all mapped primary-care classifications", () => {
  assert.deepEqual(
    taxonomiesForSpecialty("Primary").map((item) => item.code),
    ["207Q00000X", "207R00000X", "208D00000X"],
  );
});
