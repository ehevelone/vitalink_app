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

const hipaa = { name: 'Health_Information_Authorization.pdf', content: Buffer.from('hipaa PDF').toString('base64') };
const soa = { name: 'Medicare_Scope_of_Appointment.pdf', content: Buffer.from('soa PDF').toString('base64') };

test('new authorization submission requires both PDFs and SOA choices', async () => {
  const { handler, mailed } = setup();
  const response = await handler({ body: JSON.stringify({
    agent: { email: 'agent@example.com' },
    attachments: [hipaa],
    soa_product_types: ['Medicare Advantage (Part C)'],
  }) });
  assert.equal(response.statusCode, 400);
  assert.equal(mailed(), undefined);
});

test('distinct signed PDFs and selected products reach email and CRM', async () => {
  const { handler, mailed, crmPackage } = setup();
  const response = await handler({ body: JSON.stringify({
    agent: { email: 'agent@example.com' },
    user: 'Client',
    user_email: 'client@example.com',
    app_user_id: '17',
    sessionToken: 'test-session',
    attachments: [hipaa, soa],
    soa_product_types: ['Medicare Advantage (Part C)'],
  }) });
  assert.equal(response.statusCode, 200);
  assert.deepEqual(crmPackage().soaProductTypes, ['Medicare Advantage (Part C)']);
  assert.equal(crmPackage().hipaaPdfBase64, hipaa.content);
  assert.equal(crmPackage().soaPdfBase64, soa.content);
  assert.notEqual(crmPackage().hipaaPdfBase64, crmPackage().soaPdfBase64);
  assert.ok(mailed().attachments.some((a) => a.filename === hipaa.name));
  assert.ok(mailed().attachments.some((a) => a.filename === soa.name));
});
