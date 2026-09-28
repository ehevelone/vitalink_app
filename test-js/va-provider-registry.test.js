const test = require("node:test");
const assert = require("node:assert/strict");

const {
  extractSearchResults,
  mergeProviderCandidates,
  searchVaProviders,
} = require("../functions/services/va-provider-registry");

const hoa = {
  firstName: "HOA",
  lastName: "NGUYEN",
  serviceProductLine: " Primary Care",
  vaFacility: "Nebraska/Western Iowa HCS (636)",
  facilityAddress: "4101 Woolworth Avenue",
  city: "Omaha",
  state: "Nebraska",
  zipCode: "68105     ",
  occupation: "Advance Practice Nurse",
};

function directoryHtml(results = [hoa]) {
  return `<script>hydrate({"lastUpdated":"09/04/2026","searchResults":${JSON.stringify(results)},"selectedState":28})</script>`;
}

test("extracts VA provider results from the public directory payload", () => {
  assert.deepEqual(extractSearchResults(directoryHtml()), [hoa]);
});

test("VA search supports first-initial names and maps affiliation details", async () => {
  let requestedUrl = "";
  const fakeFetch = async (url) => {
    requestedUrl = url;
    return { ok: true, text: async () => directoryHtml() };
  };

  const results = await searchVaProviders(
    { name: "H, Nguyen", state: "NE" },
    fakeFetch,
  );

  assert.match(requestedUrl, /s=28/);
  assert.match(requestedUrl, /n=Nguyen/i);
  assert.equal(results.length, 1);
  assert.equal(results[0].displayName, "HOA NGUYEN");
  assert.equal(results[0].isVaProvider, true);
  assert.equal(results[0].vaServiceLine, "Primary Care");
});

test("VA evidence is merged into the matching NPPES record", () => {
  const merged = mergeProviderCandidates(
    [{ npi: "1234567890", displayName: "HOA THUY NGUYEN", city: "OMAHA" }],
    [{ ...hoa, displayName: "HOA NGUYEN", isVaProvider: true }],
  );

  assert.equal(merged.length, 1);
  assert.equal(merged[0].npi, "1234567890");
  assert.equal(merged[0].isVaProvider, true);
  assert.equal(merged[0].registry, "nppes_va");
});
