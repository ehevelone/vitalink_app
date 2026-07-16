const nodemailer = require("nodemailer");

function getRequiredEnv(name) {
  const value = process.env[name];

  if (!value) {
    throw new Error(`${name} is not configured`);
  }

  return String(value).trim();
}

function createMailer() {
  const host = getRequiredEnv("SMTP_HOST");
  const port = parseInt(process.env.SMTP_PORT || "587", 10);
  const secure = port === 465;
  const isOutlook =
    /office365|outlook|microsoft/i.test(host) || /outlook|hotmail|live/i.test(process.env.SMTP_USER || "");

  return nodemailer.createTransport({
    host,
    port,
    secure,
    requireTLS: !secure || isOutlook,
    auth: {
      user: getRequiredEnv("SMTP_USER"),
      pass: getRequiredEnv("SMTP_PASS"),
    },
    authMethod: isOutlook ? "LOGIN" : undefined,
    connectionTimeout: 15000,
    greetingTimeout: 15000,
    socketTimeout: 20000,
    tls: {
      minVersion: "TLSv1.2",
      servername: host,
    },
  });
}

function fromAddress(label = "VitaLink") {
  const from = String(process.env.SMTP_FROM || process.env.SMTP_USER || "").trim();

  if (!from) {
    throw new Error("SMTP_FROM or SMTP_USER is not configured");
  }

  return `"${label}" <${from}>`;
}

module.exports = {
  createMailer,
  fromAddress,
};
