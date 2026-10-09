const assert = require("node:assert/strict");
const test = require("node:test");

const {
  channelLabel,
  deviceLanguage,
  normalizeLanguage,
  notificationText,
  requestLanguage,
  sendLocalizedMulticast,
  topicLabel,
} = require("../services/notification-language");
const { prospectConsentText } = require("../services/account-access");
const { TEMPLATES } = require("../services/prospect-marketing");

test("the app language comes from the body first, then Accept-Language", () => {
  assert.equal(requestLanguage({ headers: {} }, { language: "es" }), "es");
  assert.equal(requestLanguage({ headers: { "Accept-Language": "es-MX,es;q=0.9" } }, {}), "es");
  assert.equal(requestLanguage({ headers: { "accept-language": "en-US" } }, {}), "en");
  // Older apps send nothing; the stored language is then left alone.
  assert.equal(requestLanguage({ headers: {} }, {}), null);
  assert.equal(normalizeLanguage(""), null);
});

test("phones without a stored language get English", () => {
  assert.equal(deviceLanguage({}), "en");
  assert.equal(deviceLanguage({ app_language: null }), "en");
  assert.equal(deviceLanguage({ app_language: "es" }), "es");
});

test("notification text is translated and keeps the fill-ins", () => {
  assert.equal(notificationText("messageFrom", "en", { name: "Ana" }), "Message from Ana");
  assert.equal(notificationText("messageFrom", "es", { name: "Ana" }), "Mensaje de Ana");
  assert.match(notificationText("profileUpdateBody", "es", { profile: "Mamá" }), /^Mamá tiene una actualización/);
  assert.equal(channelLabel("call", "es"), "llamada");
  assert.equal(topicLabel("Life Insurance", "es"), "seguro de vida");
  assert.equal(topicLabel("Life Insurance", "en"), "Life Insurance");
});

test("each language group gets its own message and results stay in order", async () => {
  const sent = [];
  const messaging = {
    sendEachForMulticast: async (message) => {
      sent.push(message);
      return {
        successCount: message.tokens.length,
        failureCount: 0,
        responses: message.tokens.map((token) => ({ success: true, token })),
      };
    },
  };
  const targets = [
    { token: "a", language: "en" },
    { token: "b", language: "es" },
    { token: "c", language: "en" },
  ];
  const result = await sendLocalizedMulticast(messaging, targets, (language, tokens) => ({
    tokens,
    notification: { title: notificationText("sharingEndedTitle", language) },
  }));

  assert.equal(sent.length, 2);
  assert.deepEqual(sent.find((m) => m.tokens.includes("b")).tokens, ["b"]);
  assert.equal(sent.find((m) => m.tokens.includes("b")).notification.title, "Se dejó de compartir el perfil");
  assert.equal(result.successCount, 3);
  assert.deepEqual(result.responses.map((r) => r.token), ["a", "b", "c"]);
});

test("prospect consent is shown and recorded in Spanish for Spanish users", () => {
  const es = prospectConsentText("medicare", "Ana Ruiz", "es");
  const en = prospectConsentText("medicare", "Ana Ruiz");
  assert.match(es, /^Acepto recibir mensajes de mercadeo/);
  assert.match(es, /Ana Ruiz/);
  assert.match(en, /^I agree to receive in-app and push marketing messages/);
  assert.match(prospectConsentText("life", "Ana", "es"), /seguro de vida/);
});

test("every prospect message template has Spanish text", () => {
  for (const [id, template] of Object.entries(TEMPLATES)) {
    assert.equal(typeof template.textEs, "function", id);
    assert.match(template.textEs("Ana"), /Ana/, id);
  }
});
