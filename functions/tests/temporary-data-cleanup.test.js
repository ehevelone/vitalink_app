const assert = require("node:assert/strict");
const test = require("node:test");

const db = require("../services/db");

test("cleanup removes simulated expired temporary records and is safe to rerun", async () => {
  const originalQuery = db.query;
  let firstRun = true;
  const deleteSql = [];

  db.query = async (text) => {
    const sql = String(text).replace(/\s+/g, " ").trim();
    if (sql.startsWith("SELECT COUNT(*) FILTER")) {
      return {
        rows: [{ expired_count: firstRun ? 2 : 0, incomplete_count: firstRun ? 1 : 0, consumed_count: 0 }],
        rowCount: 1,
      };
    }
    if (sql.includes("to_regclass('public.agent_invites')")) {
      return { rows: [{ name: "agent_invites" }], rowCount: 1 };
    }
    if (sql.startsWith("DELETE FROM")) {
      deleteSql.push(sql);
      const count = firstRun ? 1 : 0;
      return { rows: [], rowCount: count };
    }
    if (sql.startsWith("UPDATE profile_share_links") && sql.includes("status <> 'pending'")) {
      return { rows: [], rowCount: firstRun ? 1 : 0 };
    }
    return { rows: [], rowCount: 0 };
  };

  try {
    delete require.cache[require.resolve("../services/temporary-data-cleanup")];
    const { runTemporaryDataCleanup } = require("../services/temporary-data-cleanup");
    const first = await runTemporaryDataCleanup();
    assert.equal(first.deviceTransfers.expired, 2);
    assert.equal(first.deviceTransfers.incomplete, 1);
    assert.equal(first.caregiverPackages, 1);
    assert.equal(first.caregiverInvites.expiredInvites, 1);
    assert.equal(first.accessCodeAttempts, 2);
    assert.equal(first.agentInvites, 1);

    firstRun = false;
    const second = await runTemporaryDataCleanup();
    assert.equal(second.deviceTransfers.deleted, 0);
    assert.equal(second.caregiverPackages, 0);
    assert.equal(second.caregiverInvites.expiredInvites, 0);
    assert.equal(second.accessCodeAttempts, 0);
    assert.equal(second.agentInvites, 0);

    assert.ok(deleteSql.some((sql) => sql.includes("device_transfer_packages")));
    assert.ok(deleteSql.some((sql) => sql.includes("profile_update_packages")));
    assert.ok(deleteSql.some((sql) => sql.includes("profile_share_links")));
    assert.ok(deleteSql.some((sql) => sql.includes("access_code_attempts")));
  } finally {
    db.query = originalQuery;
  }
});
