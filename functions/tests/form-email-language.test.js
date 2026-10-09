const assert = require("node:assert/strict");
const test = require("node:test");

const db = require("../services/db");
const mailer = require("../services/mailer");
const crmSync = require("../services/crm-sync");
const authorizationStatus = require("../services/authorization-status");

async function sendForm(body) {
  const sent = [];
  const crmCalls = [];
  const signingCalls = [];
  const originals = {
    query: db.query,
    createMailer: mailer.createMailer,
    fromAddress: mailer.fromAddress,
    sync: crmSync.syncVitalinkPackageToCrm,
    getAuthorizedUser: authorizationStatus.getAuthorizedUser,
    recordSigning: authorizationStatus.recordSigning,
  };
  db.query = async () => ({ rows: [], rowCount: 0 });
  authorizationStatus.getAuthorizedUser = async () => ({ id: 7, agent_id: 9 });
  authorizationStatus.recordSigning = async (...args) => signingCalls.push(args);
  mailer.createMailer = () => ({ sendMail: async (m) => { sent.push(m); return { messageId: "1" }; } });
  mailer.fromAddress = (name) => name + " <test@example.com>";
  crmSync.syncVitalinkPackageToCrm = async (args) => { crmCalls.push(args); return { ok: true }; };

  const modulePath = require.resolve("../send_form_email");
  delete require.cache[modulePath];
  try {
    const { handler } = require("../send_form_email");
    const res = await handler({ httpMethod: "POST", body: JSON.stringify(body) });
    return { res, mail: sent[0], crmCalls, signingCalls };
  } finally {
    db.query = originals.query;
    mailer.createMailer = originals.createMailer;
    mailer.fromAddress = originals.fromAddress;
    crmSync.syncVitalinkPackageToCrm = originals.sync;
    authorizationStatus.getAuthorizedUser = originals.getAuthorizedUser;
    authorizationStatus.recordSigning = originals.recordSigning;
    delete require.cache[modulePath];
  }
}

const pdf = Buffer.alloc(200, 1).toString("base64");
const base = {
  app_user_id: "7",
  sessionToken: "s",
  agent: { email: "agent@example.com", name: "Agent" },
  user: "Pat Client",
  medications: [],
  providers: [],
};

test("a Spanish-signed form tells the agent which PDF is the signed record", async () => {
  const { res, mail } = await sendForm({
    ...base,
    signed_language: "es",
    attachments: [
      { name: "HIPAA_SOA_Authorization_Signed_Spanish.pdf", content: pdf },
      { name: "English_Translation_For_Agent_Reference.pdf", content: pdf },
      { name: "vitalink_user_info.csv", content: pdf },
    ],
  });
  assert.equal(res.statusCode, 200);
  assert.match(mail.subject, /signed in Spanish/);
  assert.match(mail.text, /in Spanish - this is the signed document and official record/);
  assert.match(mail.text, /for your reference only \(not the signed document\)/);
  const names = mail.attachments.map((a) => a.filename);
  assert.ok(
    names.indexOf("HIPAA_SOA_Authorization_Signed_Spanish.pdf") <
      names.indexOf("English_Translation_For_Agent_Reference.pdf"),
  );
});

test("an English-signed form email is unchanged", async () => {
  const { mail, signingCalls } = await sendForm({
    ...base,
    signed_at: "2026-10-08T12:00:00.000Z",
    attachments: [{ name: "HIPAA_SOA_Authorization.pdf", content: pdf }],
  });
  assert.doesNotMatch(mail.subject, /Spanish/);
  assert.doesNotMatch(mail.text, /translation/i);
  assert.deepEqual(signingCalls, [[7, 9, "2026-10-08T12:00:00.000Z"]]);
});
