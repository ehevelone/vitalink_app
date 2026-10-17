const assert = require("node:assert/strict");
const test = require("node:test");
const bcrypt = require("bcryptjs");

const db = require("../services/db");
const userAuth = require("../services/user-auth");
const mailer = require("../services/mailer");

const PASSWORD = "Correct-Horse-1";
const PASSWORD_HASH = bcrypt.hashSync(PASSWORD, 4);

// A tiny in-memory stand-in for the tables this function touches.
function fakeDatabase() {
  const state = {
    users: [
      { id: "7", email: "owner@example.com", password_hash: PASSWORD_HASH, first_name: "Jon", last_name: "Smiht" },
      { id: "8", email: "taken@example.com", password_hash: PASSWORD_HASH, first_name: "Other", last_name: "Person" },
    ],
    corrections: [],
    audit: [],
    userUpdates: [],
  };
  const query = async (sql, params = []) => {
    if (/FROM users\s+WHERE id = \$1/.test(sql)) {
      return { rows: state.users.filter((u) => u.id === String(params[0])) };
    }
    if (/FROM users WHERE LOWER\(email\) = \$1 AND id <> \$2/.test(sql)) {
      return { rows: state.users.filter((u) => u.email === params[0] && u.id !== String(params[1])) };
    }
    if (/INSERT INTO account_corrections/.test(sql)) {
      const [id, user_id, new_first_name, new_last_name, new_email, current_code_hash, new_email_code_hash, session_fingerprint] = params;
      state.corrections.push({
        id, user_id, new_first_name, new_last_name, new_email,
        current_code_hash, new_email_code_hash, session_fingerprint, attempts: 0, completed_at: null,
      });
      return { rows: [] };
    }
    if (/SELECT \* FROM account_corrections/.test(sql)) {
      return {
        rows: state.corrections.filter((c) =>
          c.id === params[0] && c.user_id === String(params[1]) && !c.completed_at),
      };
    }
    if (/SET attempts = attempts \+ 1/.test(sql)) {
      const c = state.corrections.find((x) => x.id === params[0]);
      if (c) c.attempts += 1;
      return { rows: [] };
    }
    if (/SET completed_at = NOW\(\)/.test(sql)) {
      const c = state.corrections.find((x) => x.id === params[0]);
      if (c) c.completed_at = new Date();
      return { rows: [] };
    }
    if (/^\s*UPDATE users SET/.test(sql)) {
      state.userUpdates.push({ sql, params });
      const user = state.users.find((u) => u.id === String(params[params.length - 1]));
      const setPart = sql.split("WHERE")[0];
      const assignments = [...setPart.matchAll(/(\w+) = \$(\d+)/g)];
      for (const [, column, index] of assignments) user[column] = params[Number(index) - 1];
      return { rows: [user] };
    }
    if (/INSERT INTO account_correction_audit/.test(sql)) {
      state.audit.push(params);
      return { rows: [] };
    }
    return { rows: [] };
  };
  return { state, query };
}

async function withHandler({ session = true } = {}, run) {
  const original = {
    query: db.query,
    connect: db.connect,
    key: process.env.ENCRYPTION_KEY,
    verify: userAuth.verifyUserSession,
    createMailer: mailer.createMailer,
    fromAddress: mailer.fromAddress,
  };
  const fake = fakeDatabase();
  const sent = [];
  db.query = fake.query;
  db.connect = async () => ({ query: fake.query, release() {} });
  process.env.ENCRYPTION_KEY = "test-only-key";
  userAuth.verifyUserSession = async () => session;
  mailer.createMailer = () => ({ sendMail: async (mail) => sent.push(mail) });
  mailer.fromAddress = () => "VitaLink Support <support@example.com>";
  const path = require.resolve("../account_correction");
  delete require.cache[path];
  try {
    const { handler } = require("../account_correction");
    await run({ handler, state: fake.state, sent });
  } finally {
    db.query = original.query;
    db.connect = original.connect;
    if (original.key === undefined) delete process.env.ENCRYPTION_KEY;
    else process.env.ENCRYPTION_KEY = original.key;
    userAuth.verifyUserSession = original.verify;
    mailer.createMailer = original.createMailer;
    mailer.fromAddress = original.fromAddress;
    delete require.cache[path];
  }
}

const post = (body) => ({ httpMethod: "POST", headers: {}, body: JSON.stringify(body) });
const parse = (res) => JSON.parse(res.body || "{}");
const codeFrom = (mail) => mail.text.match(/\b(\d{6})\b/)[1];

const start = (extra = {}) => post({
  action: "start", userId: "7", sessionToken: "s",
  currentEmail: "owner@example.com", password: PASSWORD, newName: "Jon Smith", ...extra,
});

test("a wrong password changes nothing and sends no code", async () => {
  await withHandler({}, async ({ handler, state, sent }) => {
    const res = await handler(start({ password: "guess" }));
    assert.equal(res.statusCode, 403);
    assert.equal(parse(res).code, "credentials_mismatch");
    assert.equal(sent.length, 0);
    assert.equal(state.corrections.length, 0);
  });
});

test("another account's email with the right password is refused", async () => {
  await withHandler({}, async ({ handler, sent }) => {
    const res = await handler(start({ currentEmail: "taken@example.com" }));
    assert.equal(res.statusCode, 403);
    assert.equal(sent.length, 0);
  });
});

test("without a valid session nothing happens", async () => {
  await withHandler({ session: false }, async ({ handler, sent, state }) => {
    const res = await handler(start());
    assert.equal(res.statusCode, 403);
    assert.equal(sent.length, 0);
    assert.equal(state.corrections.length, 0);
  });
});

test("a name fix needs the code sent to the email on file", async () => {
  await withHandler({}, async ({ handler, state, sent }) => {
    const started = parse(await handler(start()));
    assert.equal(started.success, true);
    assert.equal(started.needsNewEmailCode, false);
    assert.equal(sent.length, 1);
    assert.equal(sent[0].to, "owner@example.com");

    const wrong = await handler(post({
      action: "confirm", userId: "7", sessionToken: "s",
      correctionId: started.correctionId, code: "000000",
    }));
    assert.equal(wrong.statusCode, 400);
    assert.equal(state.userUpdates.length, 0);

    const ok = await handler(post({
      action: "confirm", userId: "7", sessionToken: "s",
      correctionId: started.correctionId, code: codeFrom(sent[0]),
    }));
    assert.equal(ok.statusCode, 200);
    assert.equal(parse(ok).name, "Jon Smith");
    assert.equal(state.users[0].last_name, "Smith");
    assert.equal(state.users[0].email, "owner@example.com");
    assert.equal(state.audit.length, 1);
    assert.equal(state.audit[0][2], "name");
  });
});

test("an email change needs both codes and notifies the old address", async () => {
  await withHandler({}, async ({ handler, state, sent }) => {
    const started = parse(await handler(start({ newName: "", newEmail: "New@Example.com" })));
    assert.equal(started.needsNewEmailCode, true);
    assert.deepEqual(sent.map((m) => m.to), ["owner@example.com", "new@example.com"]);

    const onlyOne = await handler(post({
      action: "confirm", userId: "7", sessionToken: "s",
      correctionId: started.correctionId, code: codeFrom(sent[0]),
    }));
    assert.equal(onlyOne.statusCode, 400);
    assert.equal(state.userUpdates.length, 0);

    const ok = await handler(post({
      action: "confirm", userId: "7", sessionToken: "s",
      correctionId: started.correctionId,
      code: codeFrom(sent[0]), newEmailCode: codeFrom(sent[1]),
    }));
    assert.equal(ok.statusCode, 200);
    assert.equal(state.users[0].email, "new@example.com");
    const notice = sent[sent.length - 1];
    assert.equal(notice.to, "owner@example.com");
    assert.match(notice.subject, /email was changed/i);
  });
});

test("an email already used by another account is refused", async () => {
  await withHandler({}, async ({ handler, sent }) => {
    const res = await handler(start({ newName: "", newEmail: "taken@example.com" }));
    assert.equal(res.statusCode, 409);
    assert.equal(parse(res).code, "email_unavailable");
    assert.equal(sent.length, 0);
  });
});

test("after five wrong codes the request expires", async () => {
  await withHandler({}, async ({ handler, state, sent }) => {
    const started = parse(await handler(start()));
    for (let i = 0; i < 5; i++) {
      await handler(post({
        action: "confirm", userId: "7", sessionToken: "s",
        correctionId: started.correctionId, code: "111111",
      }));
    }
    const late = await handler(post({
      action: "confirm", userId: "7", sessionToken: "s",
      correctionId: started.correctionId, code: codeFrom(sent[0]),
    }));
    assert.equal(late.statusCode, 410);
    assert.equal(state.userUpdates.length, 0);
  });
});

test("a code cannot be used by a different account", async () => {
  await withHandler({}, async ({ handler, state, sent }) => {
    const started = parse(await handler(start()));
    const res = await handler(post({
      action: "confirm", userId: "8", sessionToken: "s",
      correctionId: started.correctionId, code: codeFrom(sent[0]),
    }));
    assert.equal(res.statusCode, 410);
    assert.equal(state.userUpdates.length, 0);
  });
});

test("only the session that asked for the change can confirm it", async () => {
  await withHandler({}, async ({ handler, state, sent }) => {
    const started = parse(await handler(start()));
    const res = await handler(post({
      action: "confirm", userId: "7", sessionToken: "a-different-session",
      correctionId: started.correctionId, code: codeFrom(sent[0]),
    }));
    assert.equal(res.statusCode, 410);
    assert.equal(state.userUpdates.length, 0);
  });
});

test("the change runs inside one transaction", async () => {
  await withHandler({}, async ({ handler, sent }) => {
    const seen = [];
    const db = require("../services/db");
    const inner = await db.connect();
    db.connect = async () => ({
      query: async (sql, params) => {
        seen.push(String(sql).trim().split(/\s+/)[0]);
        return inner.query(sql, params);
      },
      release() {},
    });
    const started = parse(await handler(start()));
    const ok = await handler(post({
      action: "confirm", userId: "7", sessionToken: "s",
      correctionId: started.correctionId, code: codeFrom(sent[0]),
    }));
    assert.equal(ok.statusCode, 200);
    assert.equal(seen[0], "BEGIN");
    assert.equal(seen[seen.length - 1], "COMMIT");
    assert.ok(seen.includes("UPDATE"));
  });
});

test("a database duplicate-email refusal rolls back and is reported generically", async () => {
  await withHandler({}, async ({ handler, state, sent }) => {
    const started = parse(await handler(start({ newName: "", newEmail: "fresh@example.com" })));
    const db = require("../services/db");
    const inner = await db.connect();
    const seen = [];
    db.connect = async () => ({
      query: async (sql, params) => {
        seen.push(String(sql).trim().split(/\s+/)[0]);
        if (/^\s*UPDATE users SET/.test(sql)) {
          const error = new Error("duplicate key");
          error.code = "23505";
          throw error;
        }
        return inner.query(sql, params);
      },
      release() {},
    });
    const res = await handler(post({
      action: "confirm", userId: "7", sessionToken: "s",
      correctionId: started.correctionId,
      code: codeFrom(sent[0]), newEmailCode: codeFrom(sent[1]),
    }));
    assert.equal(res.statusCode, 409);
    assert.equal(parse(res).code, "email_unavailable");
    assert.equal(seen[seen.length - 1], "ROLLBACK");
    assert.equal(state.users[0].email, "owner@example.com");
  });
});

test("stored codes are keyed with the server secret", async () => {
  await withHandler({}, async ({ handler, state }) => {
    await handler(start());
    const stored = state.corrections[0].current_code_hash;
    const crypto = require("crypto");
    for (let n = 100000; n < 100050; n++) {
      const plain = crypto.createHash("sha256").update(state.corrections[0].id + ":" + n).digest("hex");
      assert.notEqual(stored, plain);
    }
  });
});
