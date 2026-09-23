const test = require('node:test');
const assert = require('node:assert/strict');

const db = require('../functions/services/db');
const { Pool } = require('pg');
const { handler } = require('../functions/claim_agent_unlock');
const { handler: inviteHandler } = require('../functions/agent-enroll-from-invite');

const originalQuery = db.query;
const originalConnect = db.connect;
const originalPoolConnect = Pool.prototype.connect;

function setup({ agent = null, rsm = null, duplicate = false, selfRsm = null } = {}) {
  const calls = [];
  const client = {
    release() {},
    async query(sql, params = []) {
      calls.push({ sql, params });
      if (sql.includes('FROM agents') && sql.includes('promo_code = $1')) return { rows: agent ? [agent] : [] };
      if (sql.includes('FROM rsms') && sql.includes('FOR UPDATE')) return { rows: rsm ? [rsm] : [] };
      if (sql.includes('FROM agents') && sql.includes('LOWER(email)')) return { rows: duplicate ? [{ id: 99 }] : [] };
      if (sql.includes('FROM rsms') && sql.includes('LOWER(email)')) return { rows: selfRsm ? [{ id: selfRsm }] : [] };
      if (sql.includes('INSERT INTO agents') || sql.includes('UPDATE agents')) {
        const isInsert = sql.includes('INSERT INTO agents');
        const status = params[isInsert ? 14 : 15];
        return { rows: [{ id: 51, email: 'new@example.com', active: params[isInsert ? 11 : 13],
          subscription_status: status, promo_code: isInsert ? params[16] : params[10], role: 'agent' }] };
      }
      return { rows: [] };
    },
  };
  db.query = async () => ({ rows: [] });
  db.connect = async () => client;
  return calls;
}

function request(code = 'RSM-TEST', email = 'new@example.com') {
  return { httpMethod: 'POST', body: JSON.stringify({
    unlockCode: code, email, password: 'StrongPass!1', npn: '1234567890',
    name: 'New Agent', phone: '4025550100', agencyState: 'ne',
  }) };
}

const activeRsm = { id: '00000000-0000-0000-0000-000000000001', billing_active: true,
  billing_mode: 'agent_paid', pricing_tier: 'founders' };

test.after(() => {
  db.query = originalQuery;
  db.connect = originalConnect;
  Pool.prototype.connect = originalPoolConnect;
});

test('direct RSM invite creates pending individually billed agent', async () => {
  const calls = setup({ rsm: activeRsm });
  const response = await handler(request());
  assert.equal(response.statusCode, 200);
  const body = JSON.parse(response.body);
  assert.equal(body.requiresAgentBilling, true);
  assert.equal(body.active, false);
  assert.equal(body.billingOwner, 'agent');
  const insert = calls.find(call => call.sql.includes('INSERT INTO agents'));
  assert.equal(insert.params[12], activeRsm.id);
  assert.equal(insert.params[13], 'agent');
  assert.equal(insert.params[14], 'pending_payment');
  assert.ok(calls.some(call => call.sql === 'COMMIT'));
});

test('office-paid RSM invite activates linked agent', async () => {
  setup({ rsm: { ...activeRsm, billing_mode: 'office_paid' } });
  const body = JSON.parse((await handler(request())).body);
  assert.equal(body.requiresAgentBilling, false);
  assert.equal(body.active, true);
  assert.equal(body.billingOwner, 'agency');
});

test('QR-created agent code cannot bypass individual billing', async () => {
  const calls = setup({ agent: { id: 12, rsm_id: activeRsm.id,
    billing_owner: null, subscription_status: 'active', password_hash: null }, rsm: activeRsm });
  const body = JSON.parse((await handler(request('AGT-TEST'))).body);
  assert.equal(body.requiresAgentBilling, true);
  assert.equal(body.active, false);
  const update = calls.find(call => call.sql.includes('UPDATE agents'));
  assert.equal(update.params[14], 'agent');
  assert.equal(update.params[15], 'pending_payment');
});

test('existing standalone agent code still works', async () => {
  setup({ agent: { id: 12, rsm_id: null, billing_owner: null,
    subscription_status: null, password_hash: null } });
  const body = JSON.parse((await handler(request('AGT-TEST'))).body);
  assert.equal(body.success, true);
  assert.equal(body.requiresAgentBilling, false);
});

test('RSM self-registration via existing agent code remains active', async () => {
  setup({ agent: { id: 12, rsm_id: null, billing_owner: null,
    subscription_status: null, password_hash: null }, selfRsm: activeRsm.id });
  const body = JSON.parse((await handler(request('AGT-TEST'))).body);
  assert.equal(body.success, true);
  assert.equal(body.billingOwner, 'rsm');
  assert.equal(body.requiresAgentBilling, false);
});

test('previously paid agent code does not require a second checkout', async () => {
  setup({ agent: { id: 12, rsm_id: activeRsm.id, billing_owner: 'agent',
    subscription_status: 'active', stripe_subscription_id: 'sub_paid',
    password_hash: null }, rsm: activeRsm });
  const body = JSON.parse((await handler(request('AGT-TEST'))).body);
  assert.equal(body.success, true);
  assert.equal(body.requiresAgentBilling, false);
  assert.equal(body.active, true);
});

test('duplicate email is rejected without inserting', async () => {
  const calls = setup({ rsm: activeRsm, duplicate: true });
  const response = await handler(request());
  assert.equal(response.statusCode, 409);
  assert.ok(!calls.some(call => call.sql.includes('INSERT INTO agents')));
  assert.ok(calls.some(call => call.sql === 'ROLLBACK'));
});

test('inactive RSM billing blocks invite', async () => {
  setup({ rsm: { ...activeRsm, billing_active: false } });
  const response = await handler(request());
  assert.equal(response.statusCode, 402);
});

test('invalid code is rejected', async () => {
  setup();
  const response = await handler(request());
  assert.equal(response.statusCode, 404);
});

test('QR path creates billing-aware agent code and redirects', async () => {
  const calls = [];
  Pool.prototype.connect = async () => ({
    release() {},
    async query(sql, params = []) {
      calls.push({ sql, params });
      if (sql.includes('FROM rsms')) return { rows: [activeRsm] };
      return { rows: [] };
    },
  });
  const response = await inviteHandler({ httpMethod: 'GET', queryStringParameters: { rsm: 'RSM-TEST' } });
  assert.equal(response.statusCode, 302);
  assert.match(response.headers.Location, /agent_enrolled\.html\?code=AGT-/);
  const insert = calls.find(call => call.sql.includes('INSERT INTO agents'));
  assert.equal(insert.params[2], 'agent');
  assert.equal(insert.params[3], 'pending_payment');
  Pool.prototype.connect = originalPoolConnect;
});

test('QR path rejects inactive RSM billing without creating agent', async () => {
  const calls = [];
  Pool.prototype.connect = async () => ({
    release() {},
    async query(sql, params = []) {
      calls.push(sql);
      if (sql.includes('FROM rsms')) return { rows: [{ ...activeRsm, billing_active: false }] };
      return { rows: [] };
    },
  });
  const response = await inviteHandler({ httpMethod: 'GET', queryStringParameters: { rsm: 'RSM-TEST' } });
  assert.equal(response.statusCode, 302);
  assert.ok(!calls.some(sql => sql.includes('INSERT INTO agents')));
  Pool.prototype.connect = originalPoolConnect;
});
