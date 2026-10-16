const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const { createRxNavClient } = require("../drug_lookup");

function fixture(name) {
  return JSON.parse(fs.readFileSync(
    path.join(__dirname, "fixtures", "rxnav", `${name}.json`),
    "utf8",
  ));
}

function fakeFetch(overrides = {}) {
  return async (url) => {
    const parsed = new URL(url);
    const ndc = parsed.searchParams.get("ndc");
    overrides.onRequest?.(parsed);
    let body;
    if (parsed.pathname.endsWith("/ndcstatus.json")) {
      body = overrides[ndc] || fixture("ndc-active");
    } else if (parsed.pathname.endsWith("/drugs.json")) {
      body = overrides.drugsByName?.[parsed.searchParams.get("name")] ||
        overrides.drugs || fixture("methocarbamol-drugs");
    } else if (parsed.pathname.endsWith("/displaynames.json")) {
      body = overrides.displayNames || fixture("display-names");
    } else if (parsed.pathname.endsWith("/approximateTerm.json")) {
      body = fixture("approximate-methocarbamol");
    } else if (parsed.pathname.endsWith("/properties.json")) {
      const rxcui = parsed.pathname.split("/").at(-2);
      body = overrides.properties?.[rxcui] || fixture("methocarbamol-properties");
    } else if (parsed.pathname.endsWith("/ndcs.json")) {
      body = fixture("methocarbamol-ndcs");
    } else {
      throw new Error(`Unexpected RxNav fixture request: ${parsed}`);
    }
    return { ok: true, status: 200, json: async () => body };
  };
}

test("an active label NDC is a sure match and remains a label NDC", async () => {
  const result = await createRxNavClient(fakeFetch()).verify({
    name: "Methocarbamol",
    ndc: "00000-0000-01",
  });
  assert.equal(result.status, "sure");
  assert.equal(result.match.rxcui, "197943");
  assert.equal(result.match.ndcSource, "label");
  assert.equal(result.match.drugType, "generic");
});

test("an obsolete NDC is accepted only when it maps to an active RxCUI", async () => {
  const result = await createRxNavClient(fakeFetch({
    "00000-0000-02": fixture("ndc-obsolete"),
  })).verify({ name: "Methocarbamol", ndc: "00000-0000-02" });
  assert.equal(result.status, "sure");
  assert.equal(result.match.rxcui, "197943");
  assert.equal(result.match.ndcSource, "label");
});

test("ALIEN and UNKNOWN NDCs are rejected", async () => {
  const client = createRxNavClient(fakeFetch({
    "00000-0000-03": fixture("ndc-alien"),
    "00000-0000-04": { ndcStatus: { status: "UNKNOWN" } },
  }));
  assert.deepEqual(await client.verify({ ndc: "00000-0000-03" }), { status: "no_match" });
  assert.deepEqual(await client.verify({ ndc: "00000-0000-04" }), { status: "no_match" });
});

test("exact name plus a real strength and form is a sure match", async () => {
  const result = await createRxNavClient(fakeFetch()).verify({
    name: "Methocarbamol",
    dose: "500 mg",
    form: "tablet",
  });
  assert.equal(result.status, "sure");
  assert.equal(result.match.displayName, "methocarbamol 500 MG Oral Tablet");
  assert.equal(result.match.ndcSource, "representative");
});

test("invented names and nonexistent strengths are not verified", async () => {
  const noDrugs = { drugGroup: { name: null, conceptGroup: [] } };
  const invented = await createRxNavClient(fakeFetch({ drugs: noDrugs })).verify({
    name: "Cyclobenzapramol",
    dose: "500 mg",
  });
  const wrongStrength = await createRxNavClient(fakeFetch()).verify({
    name: "Methocarbamol",
    dose: "900 mg",
    form: "tablet",
  });
  assert.deepEqual(invented, { status: "no_match" });
  assert.deepEqual(wrongStrength, { status: "no_match" });
});

test("brand and generic names select only their corresponding term types", async () => {
  const client = createRxNavClient(fakeFetch({
    drugs: fixture("clinical-verification-drugs"),
  }));
  const brand = await client.strengths("Coreg");
  const generic = await client.strengths("Carvedilol");
  assert.ok(brand.length > 0 && brand.every((option) => option.drugType === "brand"));
  assert.ok(generic.length > 0 && generic.every((option) => option.drugType === "generic"));
});

test("Methocarbamol strengths include 500 mg and 750 mg oral tablets", async () => {
  const options = await createRxNavClient(fakeFetch()).strengths("Methocarbamol");
  const generic = options.filter((option) => option.drugType === "generic");
  assert.deepEqual(generic.map((option) => option.strength), ["500 MG", "750 MG"]);
  assert.ok(generic.every((option) => option.form === "Oral Tablet"));
  assert.ok(generic.every((option) => option.ndcSource === ""));
});

test("type-ahead search returns display names before using fuzzy fallback", async () => {
  const client = createRxNavClient(fakeFetch());
  const results = await client.search("metho");
  assert.ok(results.some((result) => result.name === "methocarbamol"));
  assert.ok(
    results.findIndex((result) => result.name === "methotrexate") <
      results.findIndex((result) => result.name === "oxymetholone"),
    "prefix matches must remain ahead of contains matches",
  );
});

test("numeric strength matching rejects substrings and preserves generic identity", async () => {
  const client = createRxNavClient(fakeFetch({
    drugs: fixture("clinical-verification-drugs"),
  }));
  const carvedilol = await client.verify({ name: "carvedilol", dose: "25 mg", form: "tablet" });
  const lisinopril = await client.verify({ name: "lisinopril", dose: "10 mg", form: "tablet" });
  assert.equal(carvedilol.match.displayName, "carvedilol 25 MG Oral Tablet");
  assert.equal(lisinopril.match.displayName, "lisinopril 10 MG Oral Tablet");
  assert.equal(carvedilol.match.drugType, "generic");
  assert.equal(lisinopril.match.drugType, "generic");
});

test("strength comparison converts mcg and mg without accepting a combination", async () => {
  const result = await createRxNavClient(fakeFetch({
    drugs: fixture("clinical-verification-drugs"),
  })).verify({ name: "levothyroxine", dose: "25 mcg", form: "tablet" });
  assert.equal(result.status, "sure");
  assert.equal(result.match.displayName, "levothyroxine 0.025 MG Oral Tablet");
});

test("a generic label excludes combination products and prefers unmarked immediate release", async () => {
  const client = createRxNavClient(fakeFetch({
    drugs: fixture("clinical-verification-drugs"),
  }));
  const result = await client.verify({ name: "metformin", dose: "500 mg", form: "tablet" });
  const options = await client.strengths("metformin");
  assert.equal(result.status, "sure");
  assert.equal(result.match.displayName, "metformin hydrochloride 500 MG Oral Tablet");
  assert.ok(options.every((option) => !option.displayName.includes("sitagliptin")));
  assert.ok(options.every((option) => option.drugType === "generic"));
});

test("an NDC is rejected when its product does not match the scanned name", async () => {
  const carvedilol = {
    properties: {
      rxcui: "200032",
      name: "carvedilol 25 MG Oral Tablet",
      synonym: "",
      tty: "SCD",
      suppress: "N",
    },
  };
  const result = await createRxNavClient(fakeFetch({
    properties: { "197943": carvedilol },
  })).verify({ name: "Methocarbamol", ndc: "00000-0000-01" });
  assert.deepEqual(result, { status: "no_match" });
});

test("strength listing makes no NDC calls and select fetches one representative NDC", async () => {
  const paths = [];
  const client = createRxNavClient(fakeFetch({
    onRequest: (url) => paths.push(url.pathname),
  }));
  await client.strengths("Methocarbamol");
  assert.equal(paths.filter((value) => value.endsWith("/ndcs.json")).length, 0);
  const selected = await client.select("197943");
  assert.equal(selected.ndcSource, "representative");
  assert.equal(paths.filter((value) => value.endsWith("/ndcs.json")).length, 1);
});

test("plain amlodipine tablet excludes the disintegrating tablet", async () => {
  const result = await createRxNavClient(fakeFetch({
    drugs: fixture("dosage-form-modifiers"),
  })).verify({ name: "amlodipine", dose: "5 mg", form: "tablet" });
  assert.equal(result.status, "sure");
  assert.equal(result.match.displayName, "amlodipine 5 MG Oral Tablet");
});

test("metformin ER sees prefixed products but remains ambiguous", async () => {
  const client = createRxNavClient(fakeFetch({
    drugs: fixture("dosage-form-modifiers"),
  }));
  const result = await client.verify({ name: "metformin ER", dose: "500 mg", form: "tablet" });
  const options = await client.strengths("metformin");
  assert.deepEqual(result, { status: "no_match" });
  assert.ok(options.some((option) => option.displayName.startsWith("24 HR metformin")));
  assert.ok(options.some((option) => option.displayName.startsWith("Modified 24 HR metformin")));
  assert.ok(options.some((option) => option.displayName.startsWith("Osmotic 24 HR metformin")));
  assert.equal(options[0].displayName, "metformin hydrochloride 500 MG Oral Tablet");
});

test("a default delayed-release capsule remains sure when every candidate is delayed-release", async () => {
  const result = await createRxNavClient(fakeFetch({
    drugs: fixture("dosage-form-modifiers"),
  })).verify({ name: "omeprazole", dose: "40 mg", form: "capsule" });
  assert.equal(result.status, "sure");
  assert.equal(result.match.displayName, "omeprazole 40 MG Delayed Release Oral Capsule");
});

test("ODT on the label selects only the disintegrating tablet", async () => {
  const result = await createRxNavClient(fakeFetch({
    drugs: fixture("dosage-form-modifiers"),
  })).verify({ name: "ondansetron ODT", dose: "4 mg", form: "tablet" });
  assert.equal(result.status, "sure");
  assert.equal(result.match.displayName, "ondansetron 4 MG Disintegrating Oral Tablet");
});

test("strengths sort extended-release doses numerically", async () => {
  const options = await createRxNavClient(fakeFetch({
    drugs: fixture("outpatient-strengths"),
  })).strengths("metoprolol succinate");
  assert.deepEqual(
    options.map((option) => option.displayName.match(/succinate (\d+) MG/)?.[1]),
    ["25", "50", "100", "200"],
  );
});

test("package-prefixed insulin pens remain available", async () => {
  const options = await createRxNavClient(fakeFetch({
    drugs: fixture("outpatient-strengths"),
  })).strengths("insulin glargine");
  assert.ok(options.some((option) => option.displayName.startsWith("3 ML insulin glargine")));
  assert.match(options[0].displayName, /Pen Injector/);
});

test("outpatient forms sort ahead of injectable products", async () => {
  const client = createRxNavClient(fakeFetch({
    drugs: fixture("outpatient-strengths"),
  }));
  const albuterol = await client.strengths("albuterol");
  const potassium = await client.strengths("potassium chloride");
  assert.match(albuterol[0].displayName, /Metered Dose Inhaler/);
  assert.match(potassium[0].displayName, /Extended Release Oral Tablet/);
});

test("actuation and application prefixes do not hide inhalers or reach display names", async () => {
  const options = await createRxNavClient(fakeFetch({
    drugs: fixture("outpatient-strengths"),
  })).strengths("albuterol");
  const prefixed = options.find((option) => option.rxcui === "745752");
  assert.ok(prefixed);
  assert.equal(
    prefixed.displayName,
    "200 ACTUAT albuterol 0.09 MG/ACTUAT Metered Dose Inhaler",
  );
  assert.doesNotMatch(prefixed.displayName, /NDA|ANDA|BLA/i);
});

test("salt-form strength searches fall back to the base ingredient", async () => {
  const empty = { drugGroup: { name: null, conceptGroup: [] } };
  const options = await createRxNavClient(fakeFetch({
    drugsByName: {
      "albuterol sulfate": empty,
      albuterol: fixture("outpatient-strengths"),
    },
  })).strengths("albuterol sulfate");
  assert.ok(options.some((option) =>
    option.displayName === "albuterol 0.09 MG/ACTUAT Metered Dose Inhaler",
  ));
});

test("common vitamin D name falls back to ergocalciferol with the label unit hint", async () => {
  const empty = { drugGroup: { name: null, conceptGroup: [] } };
  const options = await createRxNavClient(fakeFetch({
    drugsByName: {
      "vitamin D": empty,
      ergocalciferol: fixture("outpatient-strengths"),
    },
  })).strengths("vitamin D");
  assert.equal(options.length, 1);
  assert.match(options[0].displayName, /50,000 units/);
});
