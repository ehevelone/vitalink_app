const assert = require("node:assert/strict");
const test = require("node:test");

const { normalizeMedicationList } = require("../parse_label");

test("medication manifests preserve every row, including repeated medications", () => {
  const result = normalizeMedicationList({
    medications: [
      { name: "Aspirin Low Dose", dose: "81 mg", quantity: "28" },
      { name: "Levetiracetam", dose: "250 mg", quantity: "26" },
      { name: "Levetiracetam", dose: "250 mg", quantity: "30" },
    ],
    pharmacy: "Schuyler Drugstore",
  });

  assert.equal(result.medications.length, 3);
  assert.deepEqual(result.medications[1], {
    name: "Levetiracetam",
    dose: "250 mg",
    frequency: "",
    quantity: "26",
  });
  assert.equal(result.medications[2].quantity, "30");
  assert.equal(result.name, "Aspirin Low Dose");
  assert.equal(result.pharmacy, "Schuyler Drugstore");
});

test("single-bottle legacy output remains compatible", () => {
  const result = normalizeMedicationList({
    name: "Metoprolol Succ ER",
    dose: "25 mg",
    frequency: "Take one daily",
  });

  assert.equal(result.medications.length, 1);
  assert.equal(result.medications[0].name, "Metoprolol Succ ER");
  assert.equal(result.frequency, "Take one daily");
});

// A cut-off AI answer must produce a clear "list too long" error, not a 500.
async function parseWithAiResponse(choice) {
  const userAuth = require("../services/user-auth");
  const openaiPath = require.resolve("openai");
  const originalOpenAi = require.cache[openaiPath];
  const originalVerify = userAuth.verifyUserSession;
  class FakeOpenAI {
    constructor() {
      this.chat = { completions: { create: async () => ({ choices: [choice] }) } };
    }
  }
  require.cache[openaiPath] = { id: openaiPath, filename: openaiPath, loaded: true, exports: FakeOpenAI };
  userAuth.verifyUserSession = async () => true;
  const modulePath = require.resolve("../parse_label");
  delete require.cache[modulePath];
  try {
    const { handler } = require("../parse_label");
    return await handler({
      httpMethod: "POST",
      body: JSON.stringify({ userId: "7", sessionToken: "s", imageBase64: "AAAA" }),
    });
  } finally {
    if (originalOpenAi) require.cache[openaiPath] = originalOpenAi;
    else delete require.cache[openaiPath];
    userAuth.verifyUserSession = originalVerify;
    delete require.cache[modulePath];
  }
}

test("a truncated medication list returns LIST_TOO_LONG instead of a server error", async () => {
  const res = await parseWithAiResponse({
    finish_reason: "length",
    message: { content: '{"medications":[{"name":"Aspirin","dose":"81 mg"},{"name":"Lev' },
  });
  assert.equal(res.statusCode, 422);
  assert.equal(JSON.parse(res.body).code, "LIST_TOO_LONG");
});

test("a complete medication list still parses normally", async () => {
  const res = await parseWithAiResponse({
    finish_reason: "stop",
    message: { content: '{"medications":[{"name":"Aspirin","dose":"81 mg"}]}' },
  });
  assert.equal(res.statusCode, 200);
  assert.equal(JSON.parse(res.body).data.name, "Aspirin");
});

test("supplement labels keep their type, serving size and ingredients", () => {
  const result = normalizeMedicationList({
    name: "Ginger Root",
    item_type: "Supplement",
    serving_size: "3 capsules",
    active_ingredients: ["Ginger Root Extract - 700 mg", " "],
    other_ingredients: ["Gelatin", "Rice flour"],
  });
  assert.equal(result.item_type, "supplement");
  assert.equal(result.serving_size, "3 capsules");
  assert.deepEqual(result.active_ingredients, ["Ginger Root Extract - 700 mg"]);
  assert.deepEqual(result.other_ingredients, ["Gelatin", "Rice flour"]);
});

test("the reader never answers unknown; it decides from the label instead", () => {
  const decide = (parsed) => normalizeMedicationList({ name: "X", ...parsed }).item_type;
  assert.equal(decide({ item_type: "OTC" }), "otc", "a valid AI answer is kept");
  assert.equal(decide({ item_type: "unknown", serving_size: "2 gummies" }), "supplement");
  assert.equal(decide({ item_type: "", active_ingredients: ["Vitamin D3 - 25 mcg"] }), "supplement");
  assert.equal(decide({ item_type: "unknown", pharmacy: "CVS" }), "prescription");
  assert.equal(
    decide({ item_type: "unknown", serving_size: "1 tablet", pharmacy: "Walgreens" }),
    "prescription",
    "a pharmacy label wins over supplement signals",
  );
  assert.equal(decide({}), "prescription");
});
