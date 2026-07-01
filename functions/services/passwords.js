const bcrypt = require("bcryptjs");
const crypto = require("crypto");

function isBcryptHash(hash) {
  return /^\$2[aby]\$\d{2}\$/.test(String(hash || ""));
}

function isLegacySha256Hash(hash) {
  return /^[a-f0-9]{64}$/i.test(String(hash || "").trim());
}

function legacySha256(password) {
  return crypto
    .createHash("sha256")
    .update(String(password || ""))
    .digest("hex");
}

async function verifyPassword(password, hash) {
  const storedHash = String(hash || "").trim();

  if (!password || !storedHash) {
    return { valid: false, legacy: false };
  }

  if (isBcryptHash(storedHash)) {
    return {
      valid: await bcrypt.compare(password, storedHash),
      legacy: false,
    };
  }

  if (isLegacySha256Hash(storedHash)) {
    return {
      valid: legacySha256(password) === storedHash,
      legacy: true,
    };
  }

  return { valid: false, legacy: false };
}

async function hashPassword(password, rounds = 12) {
  return bcrypt.hash(password, rounds);
}

module.exports = {
  hashPassword,
  verifyPassword,
};
