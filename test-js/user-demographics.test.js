const test = require("node:test");
const assert = require("node:assert/strict");

process.env.ENCRYPTION_KEY ||= "00".repeat(32);

const {
  selectUserDemographics,
} = require("../functions/get_user_demographics");

test("registration account backfills blank profile name and phone", () => {
  const result = selectUserDemographics(
    {
      first_name: "Erik",
      last_name: "Hevelone",
      email: "example@example.com",
      phone: "4025551212",
    },
    {},
  );

  assert.equal(result.fullName, "Erik Hevelone");
  assert.equal(result.userPhone, "4025551212");
  assert.equal(result.email, "example@example.com");
});

test("encrypted profile demographics take priority over account fallbacks", () => {
  const result = selectUserDemographics(
    { first_name: "Account", last_name: "Name", phone: "1111111111" },
    {
      fullName: "Profile Name",
      userPhone: "4025559999",
      address: "123 Main St",
      city: "Omaha",
      state: "NE",
      zip: "68114",
      isVeteran: true,
      usesVaHealthcare: true,
    },
  );

  assert.equal(result.fullName, "Profile Name");
  assert.equal(result.userPhone, "4025559999");
  assert.equal(result.address, "123 Main St");
  assert.equal(result.city, "Omaha");
  assert.equal(result.state, "NE");
  assert.equal(result.zip, "68114");
  assert.equal(result.isVeteran, true);
  assert.equal(result.usesVaHealthcare, true);
});
