const test = require("node:test");
const assert = require("node:assert/strict");
const Module = require("node:module");
const path = require("node:path");

const root = path.resolve(__dirname, "..");

function loadWithMocks(relativePath, mocks) {
  const absolutePath = path.join(root, relativePath);
  const originalLoad = Module._load;
  Module._load = function mockLoad(request, parent, isMain) {
    if (Object.prototype.hasOwnProperty.call(mocks, request)) {
      return mocks[request];
    }
    return originalLoad.call(this, request, parent, isMain);
  };

  try {
    delete require.cache[require.resolve(absolutePath)];
    return require(absolutePath);
  } finally {
    Module._load = originalLoad;
  }
}

test("checkout accepts card and ACH and identifies the activation purchase", async () => {
  let checkoutParams;
  class StripeMock {
    constructor() {
      this.checkout = {
        sessions: {
          create: async (params) => {
            checkoutParams = params;
            return { url: "https://checkout.example/session" };
          }
        }
      };
    }
  }

  const { handler } = loadWithMocks("functions/vl-checkout.js", {
    stripe: StripeMock,
    "./services/stripe-prices": {
      getActivationPriceId: () => "price_activation"
    }
  });

  const response = await handler({ httpMethod: "POST" });
  assert.equal(response.statusCode, 200);
  assert.deepEqual(checkoutParams.payment_method_types, ["card", "us_bank_account"]);
  assert.deepEqual(checkoutParams.name_collection, {
    individual: { enabled: true, optional: false }
  });
  assert.equal(checkoutParams.metadata.purchase_type, "consumer_activation");
  assert.equal(checkoutParams.line_items[0].price, "price_activation");
});

test("webhook creates one verified paid activation record", async () => {
  const queries = [];
  const client = {
    query: async (sql, params) => {
      queries.push({ sql, params });
      if (sql.includes("INSERT INTO activation_codes")) {
        return { rows: [{ id: 9, code: params[0] }] };
      }
      return { rows: [] };
    },
    release() {}
  };

  class StripeMock {
    constructor() {
      this.webhooks = {
        constructEvent: () => ({
          type: "checkout.session.completed",
          created: 1770000000,
          data: { object: { id: "cs_test_paid" } }
        })
      };
      this.checkout = {
        sessions: {
          retrieve: async () => ({
            id: "cs_test_paid",
            mode: "payment",
            payment_status: "paid",
            payment_intent: "pi_test_paid",
            metadata: { purchase_type: "consumer_activation" },
            currency: "usd",
            amount_total: 4995,
            customer_details: {
              individual_name: "Test Person",
              email: "TEST@example.com"
            },
            line_items: {
              data: [{ price: { id: "price_activation" }, quantity: 1 }]
            }
          })
        }
      };
    }
  }

  class PoolMock {
    async connect() {
      return client;
    }
  }

  const { handler } = loadWithMocks("functions/vl-webhook.js", {
    stripe: StripeMock,
    pg: { Pool: PoolMock },
    "./services/stripe-prices": {
      getActivationPriceId: () => "price_activation"
    }
  });

  const response = await handler({
    body: "{}",
    headers: { "stripe-signature": "test" }
  });
  assert.equal(response.statusCode, 200);
  const insert = queries.find((entry) =>
    entry.sql.includes("INSERT INTO activation_codes")
  );
  assert.ok(insert);
  assert.match(insert.params[0], /^VL-[A-Z2-9]{4}-[A-Z2-9]{4}$/);
  assert.equal(insert.params[1], "test@example.com");
  assert.equal(insert.params[2], "cs_test_paid");
});

function registrationMocks({ agent, activation }) {
  const queries = [];
  let userInsertParams;
  const client = {
    query: async (sql, params = []) => {
      queries.push(sql);
      if (sql.includes("FROM agents WHERE unlock_code")) {
        return { rows: agent ? [agent] : [] };
      }
      if (sql.includes("FROM activation_codes")) {
        return { rows: activation ? [{ ...activation }] : [] };
      }
      if (sql.includes("INSERT INTO users")) {
        userInsertParams = params;
        return {
          rows: [{
            id: 77,
            email: params[2],
            first_name: params[0],
            last_name: params[1],
            agent_id: params[5],
            purchase_code: params[6]
          }]
        };
      }
      if (sql.includes("UPDATE activation_codes") && sql.includes("redeemed=true")) {
        return { rows: activation ? [{ code: activation.code }] : [] };
      }
      return { rows: [] };
    },
    release() {}
  };
  const db = {
    query: (...args) => client.query(...args),
    connect: async () => client
  };
  class StripeMock {
    constructor() {
      this.checkout = { sessions: { retrieve: async () => null } };
    }
  }
  return { queries, client, db, StripeMock, getUserInsertParams: () => userInsertParams };
}

async function runRegistration(mocks, code, email = "person@example.com") {
  const { handler } = loadWithMocks("functions/register_user.js", {
    "./services/db": mocks.db,
    bcryptjs: { hash: async () => "password-hash" },
    stripe: mocks.StripeMock,
    "./services/stripe-prices": {
      getActivationPriceId: () => "price_activation"
    },
    "./services/account-access": { ensureAccountAccessSchema: async () => {} },
    "./services/user-auth": { ensureUserSessionColumns: async () => {} },
    "./services/device-security": {
      ensureDeviceSecuritySchema: async () => {},
      recordDeviceEvent: async () => {},
    },
    "./services/notification-language": { requestLanguage: () => "en" },
    "./services/access-code-rate-limit": {
      checkAccessCodeLimit: async () => ({ allowed: true }),
      clearAccessCodeFailures: async () => {},
      rateLimitScope: () => "test-scope",
      recordAccessCodeFailure: async () => ({ locked: false }),
      requestIp: () => "127.0.0.1",
    },
  });
  return handler({
    httpMethod: "POST",
    body: JSON.stringify({
      firstName: "Test",
      lastName: "Person",
      email,
      phone: "4025551212",
      password: "test-password",
      promoCode: code,
      platform: "android"
    })
  });
}

test("agent registration preserves the existing agent association", async () => {
  const mocks = registrationMocks({
    agent: { id: 42, active: true },
    activation: null
  });
  const response = await runRegistration(mocks, "AGENT-CODE");
  const body = JSON.parse(response.body);
  assert.equal(body.success, true);
  assert.equal(mocks.getUserInsertParams()[5], 42);
  assert.equal(mocks.getUserInsertParams()[6], null);
  assert.equal(mocks.queries.includes("COMMIT"), false);
});

test("paid consumer registration creates no agent and redeems atomically", async () => {
  const mocks = registrationMocks({
    agent: null,
    activation: {
      id: 12,
      code: "VL-TEST-CODE",
      name: "Test Person",
      email: "person@example.com",
      stripe_session: "cs_test_paid",
      purchase_type: "consumer_activation",
      payment_status: "paid",
      redeemed: false
    }
  });
  const response = await runRegistration(mocks, "VL-TEST-CODE");
  const body = JSON.parse(response.body);
  assert.equal(body.success, true);
  assert.equal(mocks.getUserInsertParams()[5], null);
  assert.equal(mocks.getUserInsertParams()[6], "VL-TEST-CODE");
  assert.ok(mocks.queries.some((sql) => sql.includes("redeemed=false")));
  assert.ok(mocks.queries.includes("COMMIT"));
});
