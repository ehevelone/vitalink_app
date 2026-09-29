const test = require("node:test");
const assert = require("node:assert/strict");

const {
  candidatesWithinRadius,
  nearbyZipPrefixes,
  zipDistanceMiles,
} = require("../functions/services/zip-radius");

test("Omaha ZIP distances distinguish nearby ZIPs from Lincoln", () => {
  assert.ok(zipDistanceMiles("68114", "68124") < 15);
  assert.ok(zipDistanceMiles("68114", "68502") > 15);
});

test("a 15-mile Omaha search includes neighboring postal prefixes", () => {
  const prefixes = nearbyZipPrefixes("68114", 15);
  assert.ok(prefixes.includes("681"));
  assert.ok(prefixes.includes("680"));
  assert.ok(prefixes.includes("515"));
});

test("radius candidates are filtered and sorted nearest-first", () => {
  const candidates = candidatesWithinRadius([
    { npi: "far", postalCode: "68502" },
    { npi: "nearer", postalCode: "68124" },
    { npi: "nearest", postalCode: "68114" },
  ], "68114", 15);
  assert.deepEqual(candidates.map((candidate) => candidate.npi), [
    "nearest", "nearer",
  ]);
  assert.equal(candidates[0].distanceMiles, 0);
});
