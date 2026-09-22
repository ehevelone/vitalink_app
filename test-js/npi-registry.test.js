const test = require("node:test");
const assert = require("node:assert/strict");

const {
  buildSearchParams,
  candidatesMatchingPhone,
  getNpiByNumber,
  mapNppesResult,
  normalizePhone,
  normalizeText,
  searchNpi,
  splitProviderName,
} = require("../functions/services/npi-registry");

test("provider names are split for both common formats", () => {
  assert.deepEqual(splitProviderName("Jane Marie Smith, MD"), {
    firstName: "Jane",
    lastName: "Smith",
  });
  assert.deepEqual(splitProviderName("Smith, Jane"), {
    firstName: "Jane",
    lastName: "Smith",
  });
});

test("provider search includes location filters and NPI-1", () => {
  const params = buildSearchParams({
    entityType: "provider",
    name: "Jane Smith",
    city: "Omaha",
    state: "NE",
    postalCode: "68114",
  });
  assert.equal(params.get("enumeration_type"), "NPI-1");
  assert.equal(params.get("first_name"), "Jane");
  assert.equal(params.get("last_name"), "Smith");
  assert.equal(params.get("city"), "Omaha");
  assert.equal(params.get("state"), "NE");
  assert.equal(params.get("postal_code"), "68114");
});

test("specialty searches use the exact NPPES taxonomy description", () => {
  const params = buildSearchParams({
    entityType: "provider",
    name: "Jane Smith",
    taxonomyDescription: "Cardiovascular Disease",
  });
  assert.equal(
    params.get("taxonomy_description"),
    "Cardiovascular Disease",
  );
});

test("pharmacy search uses organization name and NPI-2", () => {
  const params = buildSearchParams({
    entityType: "pharmacy",
    name: "Example Pharmacy",
  });
  assert.equal(params.get("enumeration_type"), "NPI-2");
  assert.equal(params.get("organization_name"), "Example Pharmacy");
});

test("registry result mapping returns only integration-safe fields", () => {
  const mapped = mapNppesResult({
    number: "1234567890",
    enumeration_type: "NPI-1",
    basic: {
      first_name: "JANE",
      last_name: "SMITH",
      credential: "MD",
    },
    addresses: [
      {
        address_purpose: "LOCATION",
        address_1: "1 MAIN ST",
        city: "OMAHA",
        state: "NE",
        postal_code: "681140000",
        telephone_number: "4025551212",
      },
    ],
    taxonomies: [{ primary: true, code: "207Q00000X", desc: "Family Medicine" }],
  });
  assert.equal(mapped.npi, "1234567890");
  assert.equal(mapped.displayName, "JANE SMITH");
  assert.equal(mapped.taxonomy, "Family Medicine");
  assert.equal(mapped.city, "OMAHA");
});

test("deactivated and malformed records are excluded", async () => {
  const fakeFetch = async () => ({
    ok: true,
    json: async () => ({
      results: [
        { number: "1111111111", basic: { status: "D" } },
        { number: "bad", basic: { status: "A" } },
        {
          number: "2222222222",
          enumeration_type: "NPI-2",
          basic: { status: "A", organization_name: "GOOD PHARMACY" },
        },
      ],
    }),
  });
  const results = await searchNpi(
    { entityType: "pharmacy", name: "Good Pharmacy" },
    fakeFetch,
  );
  assert.deepEqual(results.map((item) => item.npi), ["2222222222"]);
});

test("specialty lookup keeps only providers with an expected taxonomy code", async () => {
  const fakeFetch = async () => ({
    ok: true,
    json: async () => ({
      results: [
        {
          number: "1111111111",
          enumeration_type: "NPI-1",
          basic: { status: "A", first_name: "JANE", last_name: "SMITH" },
          taxonomies: [
            { primary: true, code: "208VP0000X", desc: "Pain Medicine" },
          ],
        },
        {
          number: "2222222222",
          enumeration_type: "NPI-1",
          basic: { status: "A", first_name: "JANE", last_name: "SMITH" },
          taxonomies: [
            { primary: true, code: "207R00000X", desc: "Internal Medicine" },
            {
              primary: false,
              code: "1041C0700X",
              desc: "Clinical Social Worker",
            },
          ],
        },
      ],
    }),
  });

  const results = await searchNpi(
    {
      entityType: "provider",
      name: "Jane Smith",
      taxonomyDescription: "Clinical",
      taxonomyCodes: ["1041C0700X"],
    },
    fakeFetch,
  );

  assert.equal(results.length, 1);
  assert.equal(results[0].npi, "2222222222");
  assert.equal(results[0].taxonomyCode, "1041C0700X");
  assert.equal(results[0].taxonomy, "Clinical Social Worker");
});

test("number confirmation only accepts the requested NPI", async () => {
  const fakeFetch = async () => ({
    ok: true,
    json: async () => ({
      results: [
        {
          number: "3333333333",
          enumeration_type: "NPI-1",
          basic: { status: "A", first_name: "J", last_name: "D" },
        },
      ],
    }),
  });
  assert.equal((await getNpiByNumber("3333333333", fakeFetch)).npi, "3333333333");
  assert.equal(await getNpiByNumber("invalid", fakeFetch), null);
});

test("cache keys normalize punctuation and spacing", () => {
  assert.equal(normalizeText("  Smith,  Jane M.D. "), "smith jane m d");
});

test("phone matching compares the final ten digits", () => {
  assert.equal(normalizePhone("+1 (402) 555-1212 ext 9"), "4025551212");
  assert.equal(normalizePhone("(402) 555-1212"), "4025551212");
});

test("pharmacy phone matching isolates a single chain location", () => {
  const candidates = [
    { npi: "1111111111", phone: "402-555-1111" },
    { npi: "2222222222", phone: "(402) 555-2222" },
    { npi: "3333333333", phone: "402-555-3333" },
  ];
  assert.deepEqual(
    candidatesMatchingPhone(candidates, "+1 402 555 2222").map(
      (candidate) => candidate.npi,
    ),
    ["2222222222"],
  );
});
