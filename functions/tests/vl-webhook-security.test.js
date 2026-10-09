const assert = require("node:assert/strict");
const Module = require("node:module");
const path = require("node:path");
const test = require("node:test");

function loadWebhook({ eventType, session, query }) {
  const file = path.resolve(__dirname, "../vl-webhook.js");
  const originalLoad = Module._load;
  const client = {
    query,
    release() {},
  };

  class StripeMock {
    constructor() {
      this.webhooks = {
        constructEvent: () => ({
          type: eventType,
          data: { object: { id: session?.id || "evt-object" } },
        }),
      };
      this.checkout = {
        sessions: {
          retrieve: async () => session,
        },
      };
    }
  }

  class PoolMock {
    async connect() {
      return client;
    }
  }

  Module._load = function (request, parent, isMain) {
    if (request === "stripe") return StripeMock;
    if (request === "pg") return { Pool: PoolMock };
    if (request === "./services/stripe-prices") {
      return { getActivationPriceId: () => "price_activation" };
    }
    return originalLoad.call(this, request, parent, isMain);
  };

  try {
    delete require.cache[require.resolve(file)];
    return require(file).handler;
  } finally {
    Module._load = originalLoad;
  }
}

const paidSession = (priceId = "price_activation") => ({
  id: "cs_paid",
  mode: "payment",
  payment_status: "paid",
  metadata: { purchase_type: "consumer_activation" },
  customer_details: { email: "PAT@EXAMPLE.COM" },
  line_items: {
    data: [{ price: { id: priceId }, quantity: 1 }],
  },
});

const invoke = (handler) => handler({
  body: "{}",
  headers: { "stripe-signature": "test" },
});

test("subscription invoice payments never create consumer activation codes", async () => {
  const queries = [];
  const handler = loadWebhook({
    eventType: "invoice.paid",
    session: null,
    query: async (sql) => {
      queries.push(String(sql));
      return { rows: [] };
    },
  });

  const response = await invoke(handler);
  assert.equal(response.statusCode, 200);
  assert.equal(queries.length, 0);
});

test("a paid checkout for another Stripe price is ignored", async () => {
  const queries = [];
  const handler = loadWebhook({
    eventType: "checkout.session.completed",
    session: paidSession("price_agent_subscription"),
    query: async (sql) => {
      queries.push(String(sql));
      return { rows: [] };
    },
  });

  const response = await invoke(handler);
  assert.equal(response.statusCode, 200);
  assert.equal(queries.length, 0);
});

test("a paid activation checkout started before metadata tagging still creates a code", async () => {
  const session = paidSession();
  delete session.metadata;
  const calls = [];
  const handler = loadWebhook({
    eventType: "checkout.session.async_payment_succeeded",
    session,
    query: async (sql) => {
      calls.push(String(sql));
      return { rows: [], rowCount: 1 };
    },
  });
  const response = await invoke(handler);

  assert.equal(response.statusCode, 200);
  assert.equal(JSON.parse(response.body).received, true);
  assert.ok(calls.some((sql) => sql.includes("INSERT INTO activation_codes")));
});

test("a database failure returns 500 so Stripe retries the paid checkout", async () => {
  const handler = loadWebhook({
    eventType: "checkout.session.async_payment_succeeded",
    session: paidSession(),
    query: async (sql) => {
      if (String(sql).includes("INSERT INTO activation_codes")) {
        throw new Error("database unavailable");
      }
      return { rows: [] };
    },
  });

  const response = await invoke(handler);
  assert.equal(response.statusCode, 500);
  assert.equal(JSON.parse(response.body).received, false);
});

