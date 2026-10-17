// functions/account_correction.js
//
// "Fix my name or email" for the account holder. Name and email are locked
// after registration; they change only here, and only when ALL of these match
// the same account in the database:
//   1. the logged-in session (account ID + session token),
//   2. the account's current email,
//   3. the account's password,
//   4. a 6-digit code emailed to the email on file (and, for an email change,
//      a second code emailed to the new address).
// Saved login details on a phone are therefore never enough on their own.
// Wrong passwords and wrong codes count toward a lockout (5 tries, 15 minutes).
// Every completed change is written to an audit table, and an email change
// sends a notice to the old address.
//
// action "start":   { userId, sessionToken, currentEmail, password, newName?, newEmail? }
// action "confirm": { userId, sessionToken, correctionId, code, newEmailCode? }

const crypto = require("crypto");
const db = require("./services/db");
const { verifyUserSession } = require("./services/user-auth");
const { verifyPassword } = require("./services/passwords");
const { createMailer, fromAddress } = require("./services/mailer");
const { requestLanguage } = require("./services/notification-language");
const { schemaOnce } = require("./services/schema-once");
const {
  checkAccessCodeLimit,
  clearAccessCodeFailures,
  rateLimitScope,
  recordAccessCodeFailure,
} = require("./services/access-code-rate-limit");

const CODE_MINUTES = 20;
const MAX_CODE_ATTEMPTS = 5;

function reply(statusCode, body) {
  return {
    statusCode,
    headers: {
      "Content-Type": "application/json",
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Headers": "Content-Type",
      "Access-Control-Allow-Methods": "POST, OPTIONS",
    },
    body: JSON.stringify(body),
  };
}

function text(value) {
  return String(value || "").trim();
}

function normalizeEmail(value) {
  return text(value).toLowerCase();
}

function isValidEmail(value) {
  return /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(value) && !value.includes("..");
}

function splitName(fullName) {
  const parts = text(fullName).split(/\s+/).filter(Boolean);
  return { firstName: parts.shift() || "", lastName: parts.join(" ") };
}

function maskEmail(email) {
  const [local, domain] = String(email || "").split("@");
  if (!domain) return "";
  return `${local.slice(0, 1)}***@${domain}`;
}

function newCode() {
  return String(crypto.randomInt(100000, 1000000));
}

// Codes and session fingerprints are keyed with a server-only secret, so a
// copy of the database alone cannot be used to work out a 6-digit code.
function serverKey() {
  const secret = process.env.ENCRYPTION_KEY;
  if (!secret) throw new Error("ENCRYPTION_KEY is not configured");
  return crypto
    .createHmac("sha256", secret)
    .update("vitalink:account-correction:v1")
    .digest();
}

function keyedHash(value) {
  return crypto.createHmac("sha256", serverKey()).update(value).digest("hex");
}

function hashCode(code, correctionId) {
  return keyedHash(`code:${correctionId}:${text(code)}`);
}

function codesMatch(code, correctionId, storedHash) {
  if (!storedHash) return false;
  const a = Buffer.from(hashCode(code, correctionId), "hex");
  const b = Buffer.from(String(storedHash), "hex");
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

function sessionFingerprint(sessionToken) {
  return keyedHash(`session:${String(sessionToken || "")}`);
}

function sameFingerprint(a, b) {
  const left = Buffer.from(String(a || ""), "hex");
  const right = Buffer.from(String(b || ""), "hex");
  return left.length > 0 && left.length === right.length &&
    crypto.timingSafeEqual(left, right);
}

const ensureSchema = schemaOnce("account-correction:schema", async () => {
  await db.query(`
    CREATE TABLE IF NOT EXISTS account_corrections (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      new_first_name TEXT,
      new_last_name TEXT,
      new_email TEXT,
      current_code_hash TEXT NOT NULL,
      new_email_code_hash TEXT,
      attempts INTEGER NOT NULL DEFAULT 0,
      session_fingerprint TEXT,
      expires_at TIMESTAMPTZ NOT NULL,
      completed_at TIMESTAMPTZ,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
  `);
  await db.query(`
    CREATE TABLE IF NOT EXISTS account_correction_audit (
      id BIGSERIAL PRIMARY KEY,
      user_id TEXT NOT NULL,
      correction_id TEXT NOT NULL,
      field TEXT NOT NULL,
      old_value TEXT,
      new_value TEXT,
      session_fingerprint TEXT,
      changed_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
  `);
  // The database itself refuses two accounts with the same email (any case).
  // If existing duplicate rows prevent creating the index, the change still
  // runs under a per-email lock inside its transaction; log it for cleanup.
  try {
    await db.query(`
      CREATE UNIQUE INDEX IF NOT EXISTS users_email_lower_unique
      ON users ((LOWER(email)))
    `);
  } catch (error) {
    console.error(
      "account_correction: users_email_lower_unique not created " +
        "(existing duplicate emails?):",
      error.message
    );
  }
});

const MESSAGES = {
  codeSubject: {
    en: "Your VitaLink verification code",
    es: "Su código de verificación de VitaLink",
  },
  codeBody: {
    en: (code) => `Hi,

Someone asked to correct the name or email on your VitaLink account.
Your verification code is:

${code}

This code expires in ${CODE_MINUTES} minutes.

If you did not ask for this, do not share this code with anyone and contact VitaLink support.

- VitaLink Support`,
    es: (code) => `Hola:

Alguien solicitó corregir el nombre o el correo de su cuenta de VitaLink.
Su código de verificación es:

${code}

Este código vence en ${CODE_MINUTES} minutos.

Si usted no lo solicitó, no comparta este código con nadie y comuníquese con el soporte de VitaLink.

- Soporte de VitaLink`,
  },
  changedSubject: {
    en: "Your VitaLink email was changed",
    es: "Se cambió el correo de su cuenta de VitaLink",
  },
  changedBody: {
    en: (newEmail) => `Hi,

The email on your VitaLink account was changed to ${newEmail}.

If you did not make this change, contact VitaLink support right away.

- VitaLink Support`,
    es: (newEmail) => `Hola:

El correo de su cuenta de VitaLink se cambió a ${newEmail}.

Si usted no hizo este cambio, comuníquese de inmediato con el soporte de VitaLink.

- Soporte de VitaLink`,
  },
};

function message(key, language, ...args) {
  const entry = MESSAGES[key];
  const value = entry[language] || entry.en;
  return typeof value === "function" ? value(...args) : value;
}

async function sendCode(to, code, language) {
  await createMailer().sendMail({
    from: fromAddress("VitaLink Support"),
    to,
    subject: message("codeSubject", language),
    text: message("codeBody", language, code),
  });
}

async function startCorrection(event, body, language) {
  const userId = text(body.userId);
  const sessionToken = text(body.sessionToken);
  const currentEmail = normalizeEmail(body.currentEmail);
  const password = String(body.password || "");
  const newName = text(body.newName);
  const newEmail = normalizeEmail(body.newEmail);

  if (!userId || !currentEmail || !password) {
    return reply(400, { success: false, error: "Email and password are required" });
  }
  if (!(await verifyUserSession(userId, sessionToken))) {
    return reply(403, { success: false, error: "Unauthorized" });
  }

  const scope = rateLimitScope("account-correction", userId);
  const limit = await checkAccessCodeLimit(scope);
  if (!limit.allowed) {
    return reply(429, {
      success: false,
      code: "too_many_attempts",
      error: "Too many attempts. Please try again later.",
      retryAfterSeconds: limit.retryAfterSeconds,
    });
  }

  const account = await db.query(
    `SELECT id, email, password_hash, first_name, last_name
     FROM users WHERE id = $1 LIMIT 1`,
    [userId]
  );
  const user = account.rows[0];
  const emailMatches = user && normalizeEmail(user.email) === currentEmail;
  const passwordMatches = emailMatches &&
    (await verifyPassword(password, user.password_hash)).valid;
  if (!passwordMatches) {
    await recordAccessCodeFailure(scope, "account-correction");
    // One message for every mismatch, so it never reveals which part was wrong.
    return reply(403, {
      success: false,
      code: "credentials_mismatch",
      error: "The email or password does not match this account.",
    });
  }

  const currentName = [text(user.first_name), text(user.last_name)]
    .filter(Boolean)
    .join(" ");
  const nameChanging = Boolean(newName) && newName !== currentName;
  const emailChanging = Boolean(newEmail) && newEmail !== currentEmail;
  if (!nameChanging && !emailChanging) {
    return reply(400, { success: false, code: "nothing_to_change", error: "Nothing to change" });
  }
  if (nameChanging && (newName.length > 100 || splitName(newName).firstName.length === 0)) {
    return reply(400, { success: false, code: "invalid_name", error: "Enter a valid name" });
  }
  if (emailChanging) {
    if (!isValidEmail(newEmail)) {
      return reply(400, { success: false, code: "invalid_email", error: "Enter a valid email address" });
    }
    const duplicate = await db.query(
      `SELECT id FROM users WHERE LOWER(email) = $1 AND id <> $2 LIMIT 1`,
      [newEmail, userId]
    );
    if (duplicate.rows.length) {
      return reply(409, { success: false, code: "email_unavailable", error: "This email cannot be used for this account" });
    }
  }

  await ensureSchema();
  // Only the newest request can be confirmed.
  await db.query(
    `UPDATE account_corrections SET expires_at = NOW()
     WHERE user_id = $1 AND completed_at IS NULL AND expires_at > NOW()`,
    [userId]
  );

  const correctionId = crypto.randomUUID();
  const currentCode = newCode();
  const newEmailCode = emailChanging ? newCode() : null;
  const { firstName, lastName } = nameChanging ? splitName(newName) : {};
  await db.query(
    `INSERT INTO account_corrections
       (id, user_id, new_first_name, new_last_name, new_email,
        current_code_hash, new_email_code_hash, session_fingerprint, expires_at)
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8, NOW() + INTERVAL '${CODE_MINUTES} minutes')`,
    [
      correctionId,
      userId,
      nameChanging ? firstName : null,
      nameChanging ? lastName : null,
      emailChanging ? newEmail : null,
      hashCode(currentCode, correctionId),
      newEmailCode ? hashCode(newEmailCode, correctionId) : null,
      sessionFingerprint(sessionToken),
    ]
  );

  // The first code always goes to the email in the database, never to an
  // address typed on the phone.
  await sendCode(user.email, currentCode, language);
  if (newEmailCode) await sendCode(newEmail, newEmailCode, language);

  return reply(200, {
    success: true,
    correctionId,
    needsNewEmailCode: Boolean(newEmailCode),
    sentTo: maskEmail(user.email),
    newEmailSentTo: newEmailCode ? maskEmail(newEmail) : null,
    expiresInMinutes: CODE_MINUTES,
  });
}

async function confirmCorrection(event, body, language) {
  const userId = text(body.userId);
  const sessionToken = text(body.sessionToken);
  const correctionId = text(body.correctionId);
  const code = text(body.code);
  const newEmailCode = text(body.newEmailCode);

  if (!userId || !correctionId || !code) {
    return reply(400, { success: false, error: "The code is required" });
  }
  if (!(await verifyUserSession(userId, sessionToken))) {
    return reply(403, { success: false, error: "Unauthorized" });
  }

  const scope = rateLimitScope("account-correction", userId);
  const limit = await checkAccessCodeLimit(scope);
  if (!limit.allowed) {
    return reply(429, {
      success: false,
      code: "too_many_attempts",
      error: "Too many attempts. Please try again later.",
      retryAfterSeconds: limit.retryAfterSeconds,
    });
  }

  await ensureSchema();

  // Everything below happens in ONE transaction: the request row is locked,
  // so two simultaneous confirmations cannot both use the same code, and the
  // account update, completion, and audit either all happen or none do.
  const client = await db.connect();
  let outcome;
  try {
    await client.query("BEGIN");
    const found = await client.query(
      `SELECT * FROM account_corrections
       WHERE id = $1 AND user_id = $2 AND completed_at IS NULL
         AND expires_at > NOW()
       LIMIT 1
       FOR UPDATE`,
      [correctionId, userId]
    );
    const correction = found.rows[0];
    if (
      !correction ||
      Number(correction.attempts) >= MAX_CODE_ATTEMPTS ||
      // Only the session that asked for the change can confirm it.
      !sameFingerprint(correction.session_fingerprint, sessionFingerprint(sessionToken))
    ) {
      await client.query("ROLLBACK");
      return reply(410, {
        success: false,
        code: "code_expired",
        error: "This code has expired. Please start again.",
      });
    }

    const currentOk = codesMatch(code, correctionId, correction.current_code_hash);
    const newEmailOk = !correction.new_email_code_hash ||
      codesMatch(newEmailCode, correctionId, correction.new_email_code_hash);
    if (!currentOk || !newEmailOk) {
      await client.query(
        `UPDATE account_corrections SET attempts = attempts + 1 WHERE id = $1`,
        [correctionId]
      );
      await client.query("COMMIT");
      outcome = { kind: "wrong_code" };
    } else {
      const account = await client.query(
        `SELECT id, email, first_name, last_name FROM users
         WHERE id = $1 LIMIT 1 FOR UPDATE`,
        [userId]
      );
      const user = account.rows[0];
      if (!user) {
        await client.query("ROLLBACK");
        return reply(404, { success: false, error: "Account not found" });
      }
      // Captured before the update so the notice always reaches the old address.
      const oldEmail = text(user.email);
      const oldName = [text(user.first_name), text(user.last_name)]
        .filter(Boolean)
        .join(" ");

      if (correction.new_email) {
        // Serializes every change to this email address, even if the unique
        // index could not be created.
        await client.query(
          `SELECT pg_advisory_xact_lock(hashtext($1))`,
          [`vitalink-email:${correction.new_email}`]
        );
        const duplicate = await client.query(
          `SELECT id FROM users WHERE LOWER(email) = $1 AND id <> $2 LIMIT 1`,
          [correction.new_email, userId]
        );
        if (duplicate.rows.length) {
          await client.query("ROLLBACK");
          return reply(409, { success: false, code: "email_unavailable", error: "This email cannot be used for this account" });
        }
      }

      const updates = [];
      const values = [];
      const audit = [];
      if (correction.new_first_name !== null && correction.new_first_name !== undefined) {
        updates.push(`first_name = $${values.push(correction.new_first_name)}`);
        updates.push(`last_name = $${values.push(correction.new_last_name || "")}`);
        audit.push([
          "name",
          oldName,
          [correction.new_first_name, correction.new_last_name].filter(Boolean).join(" "),
        ]);
      }
      if (correction.new_email) {
        updates.push(`email = $${values.push(correction.new_email)}`);
        audit.push(["email", oldEmail, correction.new_email]);
      }
      values.push(userId);
      const updated = await client.query(
        `UPDATE users SET ${updates.join(", ")}
         WHERE id = $${values.length}
         RETURNING id, email, first_name, last_name`,
        values
      );
      await client.query(
        `UPDATE account_corrections SET completed_at = NOW() WHERE id = $1`,
        [correctionId]
      );
      for (const [field, oldValue, newValue] of audit) {
        await client.query(
          `INSERT INTO account_correction_audit
             (user_id, correction_id, field, old_value, new_value, session_fingerprint)
           VALUES ($1,$2,$3,$4,$5,$6)`,
          [userId, correctionId, field, oldValue, newValue, sessionFingerprint(sessionToken)]
        );
      }
      await client.query("COMMIT");
      outcome = {
        kind: "changed",
        row: updated.rows[0] || {},
        oldEmail,
        emailChanged: Boolean(correction.new_email),
        newEmail: correction.new_email,
      };
    }
  } catch (error) {
    try {
      await client.query("ROLLBACK");
    } catch (_) {}
    if (error && error.code === "23505") {
      // The unique email index refused a duplicate.
      return reply(409, { success: false, code: "email_unavailable", error: "This email cannot be used for this account" });
    }
    throw error;
  } finally {
    client.release();
  }

  if (outcome.kind === "wrong_code") {
    await recordAccessCodeFailure(scope, "account-correction");
    return reply(400, {
      success: false,
      code: "code_incorrect",
      error: "That code is not correct.",
    });
  }

  // The change is committed; nothing after this point can undo it.
  try {
    await clearAccessCodeFailures(scope);
  } catch (error) {
    console.error("account_correction: clearing attempts failed:", error.message);
  }
  if (outcome.emailChanged) {
    try {
      await createMailer().sendMail({
        from: fromAddress("VitaLink Support"),
        to: outcome.oldEmail,
        subject: message("changedSubject", language),
        text: message("changedBody", language, outcome.newEmail),
      });
    } catch (error) {
      console.error("account_correction notice failed:", error.message);
    }
  }

  const row = outcome.row;
  return reply(200, {
    success: true,
    name: [text(row.first_name), text(row.last_name)].filter(Boolean).join(" "),
    email: text(row.email),
  });
}

exports.handler = async (event) => {
  if (event.httpMethod === "OPTIONS") return reply(200, {});
  if (event.httpMethod !== "POST") {
    return reply(405, { success: false, error: "Method Not Allowed" });
  }

  let body = {};
  try {
    body = JSON.parse(event.body || "{}");
  } catch (_) {
    return reply(400, { success: false, error: "Invalid request body" });
  }

  const language = requestLanguage(event, body) || "en";
  try {
    if (body.action === "start") return await startCorrection(event, body, language);
    if (body.action === "confirm") return await confirmCorrection(event, body, language);
    return reply(400, { success: false, error: "Unknown action" });
  } catch (error) {
    console.error("account_correction error:", error.message);
    return reply(500, { success: false, error: "Server error. Please try again." });
  }
};

exports._test = { hashCode, maskEmail, splitName };
