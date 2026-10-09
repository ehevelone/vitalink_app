const assert = require("node:assert/strict");
const test = require("node:test");

const { schemaOnce } = require("../services/schema-once");

test("schema setup runs once per instance, even for concurrent callers", async () => {
  let runs = 0;
  const ensure = schemaOnce("test:concurrent", async () => {
    runs += 1;
    await new Promise((resolve) => setTimeout(resolve, 10));
  });

  await Promise.all([ensure(), ensure(), ensure()]);
  await ensure();
  assert.equal(runs, 1);
});

test("a failed schema setup is retried on the next call", async () => {
  let runs = 0;
  const ensure = schemaOnce("test:retry", async () => {
    runs += 1;
    if (runs === 1) throw new Error("lock timeout");
  });

  await assert.rejects(ensure(), /lock timeout/);
  await ensure();
  await ensure();
  assert.equal(runs, 2);
});
