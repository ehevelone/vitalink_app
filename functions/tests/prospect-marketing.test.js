const assert = require("node:assert/strict");
const test = require("node:test");

const {
  PROSPECT_CATEGORIES,
  prospectConsentText,
} = require("../services/account-access");
const {
  TEMPLATES,
  marketingEnabled,
} = require("../services/prospect-marketing");

test("prospect categories have independent consent text", () => {
  const medicare = prospectConsentText("medicare", "Test Agent");
  const life = prospectConsentText("life", "Test Agent");

  assert.match(medicare, /Medicare coverage options/);
  assert.match(life, /life insurance information/);
  assert.match(medicare, /does not authorize phone calls, text messages, or email/);
  assert.match(life, /does not authorize phone calls, text messages, or email/);
  assert.equal(PROSPECT_CATEGORIES.medicare.durationDays > 0, true);
  assert.equal(PROSPECT_CATEGORIES.life.durationDays > 0, true);
});

test("only approved generic prospect templates are exposed", () => {
  assert.deepEqual(
    Object.keys(TEMPLATES).sort(),
    ["life_awareness", "life_family", "medicare_aep", "medicare_options", "medicare_window"]
  );
  for (const template of Object.values(TEMPLATES)) {
    const text = template.text("Test Agent");
    assert.doesNotMatch(text, /\$\d|premium|copay|benefit amount|plan name/i);
    assert.match(text, /Test Agent/);
  }
});

test("global prospect marketing kill switch stops sends", () => {
  const original = process.env.PROSPECT_MARKETING_ENABLED;
  process.env.PROSPECT_MARKETING_ENABLED = "false";
  try {
    assert.equal(marketingEnabled("medicare"), false);
    assert.equal(marketingEnabled("life"), false);
  } finally {
    if (original === undefined) delete process.env.PROSPECT_MARKETING_ENABLED;
    else process.env.PROSPECT_MARKETING_ENABLED = original;
  }
});
