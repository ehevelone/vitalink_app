const test = require('node:test');
const assert = require('node:assert/strict');
const Module = require('node:module');
const path = require('node:path');

function loadHandler(mocks) {
  const file = path.resolve(__dirname, '../functions/send_form_email.js');
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

function setup() {
  let mailed;
  let crmPackage;
  const handler = loadHandler({
    './services/db': { query: async () => ({ rows: [] }) },
    './generate-client-report-pdf': async () => Buffer.from('report'),
    './services/mailer': {
      fromAddress: () => 'VitaLink <test@example.com>',
      createMailer: () => ({ sendMail: async (mail) => {
        mailed = mail;
        return { messageId: 'test', accepted: [mail.to] };
      } }),
    },
    './services/crm-sync': { syncVitalinkPackageToCrm: async (data) => {
      crmPackage = data.packageData;
      return { success: true };
    } },
    './services/authorization-status': {
      getAuthorizedUser: async () => ({
        id: 17,
        email: 'client@example.com',
        agent_id: 4,
        agent_email: 'agent@example.com',
      }),
      recordSigning: async () => {},
    },
  });
  return { handler, mailed: () => mailed, crmPackage: () => crmPackage };
}

const combined = { name: 'HIPAA_SOA_Authorization.pdf', content: Buffer.from('combined signed PDF').toString('base64') };

test('new authorization submission requires the combined signed PDF', async () => {
  const { handler, mailed } = setup();
  const response = await handler({ body: JSON.stringify({
    app_user_id: '17',
    sessionToken: 'test-session',
    agent: { email: 'agent@example.com' },
    attachments: [],
  }) });
  assert.equal(response.statusCode, 400);
  assert.equal(mailed(), undefined);
});

test('one combined signed PDF reaches email and CRM as the official record', async () => {
  const { handler, mailed, crmPackage } = setup();
  const response = await handler({ body: JSON.stringify({
    agent: { email: 'agent@example.com' },
    user: 'Client',
    user_email: 'client@example.com',
    app_user_id: '17',
    sessionToken: 'test-session',
    attachments: [combined],
  }) });
  assert.equal(response.statusCode, 200);
  assert.equal(crmPackage().hipaaSoaPdfBase64, combined.content);
  assert.ok(mailed().attachments.some((a) => a.filename === combined.name));
});
