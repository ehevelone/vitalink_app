// functions/cleanup_devices.js
const db = require("./services/db");
const { requireAdmin } = require("./_adminAuth");

function reply(success, obj = {}) {
  return {
    statusCode: 200,
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ success, ...obj }),
  };
}

exports.handler = async (event) => {
  try {
    const auth = await requireAdmin(event);

    if (auth.error) {
      return {
        statusCode: 401,
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ success: false, error: "Unauthorized" }),
      };
    }

    console.log("🧹 Starting event-based device cleanup...");

    // Count before cleanup
    const before = await db.query(`SELECT COUNT(*) FROM user_devices`);
    console.log(`📊 Devices before cleanup: ${before.rows[0].count}`);

    // 1️⃣ Remove devices where neither agent_id nor user_id exist in parent tables
    const orphanCleanup = await db.query(`
      DELETE FROM user_devices ud
      WHERE
        (ud.user_id IS NOT NULL AND NOT EXISTS (
          SELECT 1 FROM users u WHERE u.id = ud.user_id
        ))
        OR
        (ud.agent_id IS NOT NULL AND NOT EXISTS (
          SELECT 1 FROM agents a WHERE a.id = ud.agent_id
        ))
        OR
        (ud.user_id IS NULL AND ud.agent_id IS NULL);
    `);
    console.log(`🗑️ Removed orphaned or dangling devices: ${orphanCleanup.rowCount}`);

    // Count after cleanup
    const after = await db.query(`SELECT COUNT(*) FROM user_devices`);
    console.log(`📊 Devices after cleanup: ${after.rows[0].count}`);

    return reply(true, {
      message: "Cleanup complete ✅",
      removed: orphanCleanup.rowCount,
      remaining: after.rows[0].count,
    });
  } catch (err) {
    console.error("❌ cleanup_devices error:", err);
    return reply(false, { error: "Server error: " + err.message });
  }
};
