const assert = require("node:assert/strict");
const Module = require("node:module");
const path = require("node:path");
const test = require("node:test");

function loadCrmSync(db) {
  const file = path.resolve(__dirname, "../functions/services/crm-sync.js");
  const originalLoad = Module._load;
  Module._load = function (request, parent, isMain) {
    if (request === "./db") return db;
    if (request === "./schema-once") {
      return { schemaOnce: (_key, fn) => fn };
    }
    return originalLoad.call(this, request, parent, isMain);
  };
  try {
    delete require.cache[require.resolve(file)];
    return require(file);
  } finally {
    Module._load = originalLoad;
  }
}

test("an app-sent signed package restores its archived CRM client", async () => {
  const calls = [];
  const db = {
    async query(sql, params = []) {
      const text = String(sql);
      calls.push({ sql: text, params });

      if (text.includes("FROM agents")) {
        return { rows: [{
          id: 7,
          crm_uuid: "crm-agent-1",
          crm_subscription_status: "active",
          crm_subscription_valid: true,
        }] };
      }
      if (text.includes("FROM crm_clients")) {
        return { rows: [{
          id: "crm-client-1",
          first_name: "Pat",
          last_name: "Client",
          archived_at: "2026-09-01T12:00:00Z",
        }] };
      }
      if (text.includes("UPDATE crm_clients") && text.includes("RETURNING *")) {
        return { rows: [{
          id: "crm-client-1",
          first_name: "Pat",
          last_name: "Client",
          archived_at: "2026-09-01T12:00:00Z",
        }] };
      }
      if (text.includes("INSERT INTO crm_vitalink_packages")) {
        return { rows: [{ id: "package-1" }] };
      }
      if (text.includes("INSERT INTO crm_client_documents")) {
        return { rows: [{ id: "document-1" }] };
      }
      return { rows: [] };
    },
  };

  const crmSync = loadCrmSync(db);
  const result = await crmSync.syncVitalinkPackageToCrm({
    agentEmail: "agent@example.com",
    clientData: { name: "Pat Client", email: "pat@example.com" },
    packageData: {
      signedAt: "2026-10-08T12:00:00Z",
      hipaaSoaPdfBase64: Buffer.from("signed PDF").toString("base64"),
    },
  });

  assert.equal(result.success, true);
  const schema = calls.find(({ sql }) =>
    sql.includes("ALTER TABLE crm_clients") && sql.includes("archived_at"));
  assert.ok(schema);

  const restore = calls.find(({ sql }) =>
    sql.includes("UPDATE crm_clients") && sql.includes("archived_at = NULL"));
  assert.ok(restore);
  assert.match(restore.sql, /archived_by = NULL/);

  const restoreAudit = calls.find(({ sql, params }) =>
    sql.includes("INSERT INTO crm_audit_log") && params[2] === "client_restored");
  assert.ok(restoreAudit);
  const metadata = JSON.parse(restoreAudit.params[4]);
  assert.equal(metadata.source, "new_signed_vitalink_package");
  assert.equal(metadata.previousArchivedAt, "2026-09-01T12:00:00Z");
});
