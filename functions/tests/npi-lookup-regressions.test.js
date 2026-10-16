const assert = require("node:assert/strict");
const test = require("node:test");

function loadLookup(searchNpi) {
  const registryPath = require.resolve("../services/npi-registry");
  const lookupPath = require.resolve("../npi_lookup");
  const verificationPath = require.resolve("../services/npi-verification");
  const originalRegistry = require.cache[registryPath];
  const originalVerification = require.cache[verificationPath];
  const registry = require("../services/npi-registry");
  require.cache[registryPath] = {
    id: registryPath,
    filename: registryPath,
    loaded: true,
    exports: { ...registry, searchNpi },
  };
  require.cache[verificationPath] = {
    id: verificationPath,
    filename: verificationPath,
    loaded: true,
    exports: {
      authenticate: async () => ({ userId: "1" }),
      cacheConfirmedCandidate: async () => {},
      findCachedCandidates: async () => [],
    },
  };
  delete require.cache[lookupPath];
  const loaded = require("../npi_lookup")._test;
  return {
    loaded,
    restore() {
      delete require.cache[lookupPath];
      if (originalRegistry) require.cache[registryPath] = originalRegistry;
      else delete require.cache[registryPath];
      if (originalVerification) require.cache[verificationPath] = originalVerification;
      else delete require.cache[verificationPath];
    },
  };
}

test("pharmacy lookup matches name and phone within 15 miles of the home ZIP", async () => {
  const calls = [];
  const fixture = {
    npi: "1234567890",
    displayName: "WAL-MART STORES EAST LP",
    postalCode: "68114",
    state: "NE",
    phone: "402-697-1742",
    taxonomy: "Community/Retail Pharmacy",
  };
  const harness = loadLookup(async (options) => {
    calls.push(options);
    return options.name === "Wal-Mart*" && options.postalCode === "681*"
      ? [fixture]
      : [];
  });
  try {
    const result = await harness.loaded.searchPharmacy({
      name: "Walmart Pharmacy",
      state: "NE",
      postalCode: "68114",
      phone: "(402) 697-1742",
    });
    assert.equal(result.phoneMatched, true);
    assert.equal(result.candidates[0].npi, "1234567890");
    assert.ok(calls.some((call) =>
      call.name === "Wal-Mart*" && call.postalCode === "681*"));
  } finally {
    harness.restore();
  }
});

test("provider lookup retries reversed comma names only after the saved order misses", async () => {
  const names = [];
  const candidate = {
    npi: "1093000000",
    displayName: "DAVID MEISINGER",
    postalCode: "68123",
    state: "NE",
  };
  const harness = loadLookup(async (options) => {
    names.push(options.name);
    return options.name === "MEISINGER, DAVID" ? [candidate] : [];
  });
  try {
    const result = await harness.loaded.searchRegistry({
      entityType: "provider",
      name: "DAVID, MEISINGER",
      postalCode: "68123",
      state: "NE",
      specialty: "",
    });
    assert.equal(result[0].npi, "1093000000");
    assert.ok(names.includes("DAVID, MEISINGER"));
    assert.ok(names.includes("MEISINGER, DAVID"));
  } finally {
    harness.restore();
  }
});
