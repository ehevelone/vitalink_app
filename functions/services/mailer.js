const nodemailer = require("nodemailer");

function getRequiredEnv(name) {
  const value = process.env[name];

  if (!value) {
    throw new Error(`${name} is not configured`);
  }

  return value;
}

function createMailer() {
  const host = getRequiredEnv("SMTP_HOST");
  const port = parseInt(process.env.SMTP_PORT || "587", 10);
  const secure = port === 465;

  return nodemailer.createTransport({
    host,
    port,
    secure,
    requireTLS: !secure,
    auth: {
      user: getRequiredEnv("SMTP_USER"),
      pass: getRequiredEnv("SMTP_PASS"),
    },
    tls: {
      minVersion: "TLSv1.2",
    },
  });
}

function fromAddress(label = "VitaLink") {
  return `"${label}" <${getRequiredEnv("SMTP_USER")}>`;
}

module.exports = {
  createMailer,
  fromAddress,
};
