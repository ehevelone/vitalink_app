const assert = require("node:assert/strict");
const test = require("node:test");

process.env.ENCRYPTION_KEY = "11".repeat(32);

const db = require("../services/db");
const { encrypt } = require("../encrypt");

async function loadEmergencyProfile(emergency) {
  const originalQuery = db.query;
  db.query = async () => ({
    rows: [
      {
        id: "profile-1",
        encrypted_data: encrypt(
          JSON.stringify({ fullName: "Jordan Smith", emergency }),
        ),
      },
    ],
  });

  const resolved = require.resolve("../emergency_view");
  delete require.cache[resolved];
  try {
    const { handler } = require("../emergency_view");
    const response = await handler({
      httpMethod: "GET",
      queryStringParameters: { token: "test-token" },
    });
    return JSON.parse(response.body).emergency;
  } finally {
    db.query = originalQuery;
    delete require.cache[resolved];
  }
}

test("emergency QR response includes DNR/POLST location", async () => {
  const emergency = await loadEmergencyProfile({
    dnrPolstOnFile: true,
    dnrPolstLocation: "Refrigerator door",
  });

  assert.equal(emergency.dnrPolstOnFile, true);
  assert.equal(emergency.dnrPolstLocation, "Refrigerator door");
});

test("legacy emergency profiles default to no DNR/POLST", async () => {
  const emergency = await loadEmergencyProfile({ allergies: "Penicillin" });

  assert.equal(emergency.dnrPolstOnFile, false);
  assert.equal(emergency.dnrPolstLocation, "");
});
