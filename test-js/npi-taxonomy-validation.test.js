const test = require("node:test");
const assert = require("node:assert/strict");

const {
  detectPublishedVersion,
  emailText,
  mappedTaxonomies,
  validateTaxonomyMappings,
} = require("../functions/services/npi-taxonomy-validation");

function fakeFetch(url) {
  if (String(url).includes("nucc.org")) {
    return Promise.resolve({
      ok: true,
      text: async () => "<h2>Version 26.1, 7/1/26</h2>",
    });
  }

  const parsed = new URL(url);
  const description = parsed.searchParams.get("taxonomy_description");
  const matching = mappedTaxonomies().filter(
    (item) => item.description === description,
  );
  return Promise.resolve({
    ok: true,
    json: async () => ({
      results: matching.map((item, index) => ({
        number: String(index + 1).padStart(10, "0"),
        basic: { status: "A" },
        taxonomies: [{ code: item.code, desc: item.description }],
      })),
    }),
  });
}

test("published NUCC version metadata is detected without downloading the CSV", async () => {
  assert.equal(await detectPublishedVersion(fakeFetch), "26.1");
});

test("hierarchical NPPES titles still validate their audited subspecialty", async () => {
  const hierarchicalFetch = async () => ({
    ok: true,
    json: async () => ({
      results: [
        {
          number: "1234567890",
          basic: { status: "A" },
          taxonomies: [
            {
              code: "207RC0000X",
              desc: "Internal Medicine, Cardiovascular Disease",
            },
          ],
        },
      ],
    }),
  });

  const { observedTaxonomyCodes } = require(
    "../functions/services/npi-taxonomy-validation"
  );
  assert.deepEqual(
    await observedTaxonomyCodes(
      "Cardiovascular Disease",
      hierarchicalFetch,
      ["207RC0000X"],
    ),
    ["207RC0000X"],
  );
});

test("all current mappings pass when NPPES observes each code and title", async () => {
  const report = await validateTaxonomyMappings(fakeFetch);
  assert.equal(report.status, "passed");
  assert.equal(report.reviewCount, 0);
  assert.equal(report.confirmedCount, mappedTaxonomies().length);
  assert.match(emailText(report), /No VitaLink taxonomy mapping was changed automatically/);
});

test("a new published version requires review but never rewrites mappings", async () => {
  const changedVersionFetch = async (url) => {
    if (String(url).includes("nucc.org")) {
      return {
        ok: true,
        text: async () => "<h2>Version 27.0, 1/1/27</h2>",
      };
    }
    return fakeFetch(url);
  };

  const report = await validateTaxonomyMappings(changedVersionFetch);
  assert.equal(report.status, "review");
  assert.equal(report.versionReview, true);
  assert.equal(report.mappingVersion, "26.1");
});

test("a low-frequency code that is not observed always remains review required", async () => {
  const rareCaseFetch = async (url) => {
    if (String(url).includes("nucc.org")) return fakeFetch(url);

    const parsed = new URL(url);
    const description = parsed.searchParams.get("taxonomy_description");
    const matching = mappedTaxonomies().filter(
      (item) =>
        item.description === description && item.code !== "208VP0000X",
    );
    return {
      ok: true,
      json: async () => ({
        results: matching.map((item, index) => ({
          number: String(index + 1).padStart(10, "0"),
          basic: { status: "A" },
          taxonomies: [{ code: item.code, desc: item.description }],
        })),
      }),
    };
  };

  const report = await validateTaxonomyMappings(rareCaseFetch);
  const rare = report.mappings.find((item) => item.code === "208VP0000X");
  assert.equal(report.status, "review");
  assert.equal(rare.status, "review");
});
