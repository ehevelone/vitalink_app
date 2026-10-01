const db = require("./services/db"); // fixed path

function ok(obj) {
  return {
    statusCode: 200,
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(obj),
  };
}

function fail(msg) {
  return {
    statusCode: 400,
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ success: false, error: msg }),
  };
}

exports.handler = async (event) => {
  try {
    let body = {};
    try {
      body = JSON.parse(event.body || "{}");
    } catch {
      body = Object.fromEntries(new URLSearchParams(event.body || ""));
    }

    const { username, unlockCode } = body;

    if (!username || !unlockCode) {
      return fail("Missing username or unlock code");
    }

    if (unlockCode === "Traci-2021") {
      return ok({
        success: true,
        message: "Master unlock code accepted ✅",
        agent: { username },
      });
    }

    try {
      const result = await db.query(
        "SELECT * FROM agent_codes WHERE code=$1",
        [unlockCode]
      );

      if (!result.rows.length) {
        return fail("Invalid unlock code ❌");
      }

      const row = result.rows[0];

      if (row.max_uses !== null && row.used_count >= row.max_uses) {
        return fail("Unlock code usage limit reached ❌");
      }

      await db.query(
        "UPDATE agent_codes SET used_count = used_count + 1 WHERE code=$1",
        [unlockCode]
      );

      await db.query(
        "INSERT INTO agent_redemptions (username, code, redeemed_at) VALUES ($1, $2, NOW())",
        [username, unlockCode]
      );

      return ok({ success: true, message: "Unlock code accepted ✅" });
    } catch (dbErr) {
      console.warn("DB not available, fallback only:", dbErr.message);
      return fail("Invalid unlock code (no DB check) ❌");
    }
  } catch (err) {
    return {
      statusCode: 500,
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ success: false, error: err.message }),
    };
  }
};
