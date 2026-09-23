const test = require('node:test');
const assert = require('node:assert/strict');
const Module = require('node:module');
const path = require('node:path');

function loadHandler(mocks) {
  const file = path.resolve(__dirname, '../functions/manage_authorizations.js');
  const original = Module._load;
  Module._load = function (request, parent, isMain) {
    if (Object.hasOwn(mocks, request)) return mocks[request];
    return original.call(this, request, parent, isMain);
  };
  try {
    delete require.cache[require.resolve(file)];
    return require(file).handler;
  } finally {
    Module._load = original;
  }
}

function setup(crmUuid, failFirstEmail = false) {
  const calls = { email: [], crm: [], notified: 0 };
  let notifiedAt = null;
  const user = {
    id: 7,
    first_name: 'Client',
    last_name: 'Test',
    email: 'client@example.com',
    agent_id: 9,
    agent_name: 'Agent Test',
    agent_email: 'agent@example.com',
    crm_uuid: crmUuid,
  };
  const handler = loadHandler({
    './services/mailer': {
      fromAddress: () => 'VitaLink <test@example.com>',
      createMailer: () => ({ sendMail: async (mail) => {
        calls.email.push(mail);
        if (failFirstEmail && calls.email.length === 1) {
          throw new Error('SMTP unavailable');
        }
        return { accepted: [mail.to] };
      } }),
    },
    './services/authorization-status': {
      ensureAuthorizationSchema: async () => {},
      getAuthorizedUser: async (id, token) => id === '7' && token === 'valid' ? user : null,
      getStatus: async () => null,
      recordRevocation: async () => ({
        revoked_at: new Date('2026-09-22T12:00:00Z'),
        agent_notified_at: notifiedAt,
      }),
      markAgentNotified: async () => { calls.notified++; notifiedAt = new Date(); },
      markCrmRevoked: async (...args) => { calls.crm.push(args); return Boolean(crmUuid); },
    },
  });
  const invoke = (action, token = 'valid') => handler({
    httpMethod: 'POST',
    body: JSON.stringify({ action, userId: '7', sessionToken: token }),
  });
  return { invoke, calls };
}

test('revocation reaches an agent even without CRM and repeated sends are idempotent', async () => {
  const { invoke, calls } = setup(null);
  assert.equal((await invoke('revoke')).statusCode, 200);
  assert.equal((await invoke('revoke')).statusCode, 200);
  assert.equal(calls.email.length, 1);
  assert.equal(calls.email[0].to, 'agent@example.com');
  assert.equal(calls.notified, 1);
});

test('CRM-linked agent gets status update and email', async () => {
  const { invoke, calls } = setup('crm-agent-9');
  const response = await invoke('revoke');
  assert.equal(response.statusCode, 200);
  assert.deepEqual(calls.crm[0].slice(0, 2), [7, 'crm-agent-9']);
  assert.equal(calls.email.length, 1);
});

test('invalid client session cannot revoke', async () => {
  const { invoke, calls } = setup('crm-agent-9');
  assert.equal((await invoke('revoke', 'wrong')).statusCode, 403);
  assert.equal(calls.email.length, 0);
  assert.equal(calls.crm.length, 0);
});

test('an unsent agent notice can be retried without undoing the recorded withdrawal', async () => {
  const { invoke, calls } = setup(null, true);
  const first = JSON.parse((await invoke('revoke')).body);
  assert.equal(first.recorded, true);
  assert.equal(calls.notified, 0);
  assert.equal((await invoke('revoke')).statusCode, 200);
  assert.equal(calls.notified, 1);
});
