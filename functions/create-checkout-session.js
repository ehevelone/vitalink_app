const Stripe = require("stripe");
const stripe = new Stripe(process.env.STRIPE_SECRET_KEY);

exports.handler = async (event) => {

  if (event.httpMethod === "OPTIONS") {
    return {
      statusCode: 200,
      headers: {
        "Access-Control-Allow-Origin": "https://myvitalink.app",
        "Access-Control-Allow-Headers": "Content-Type",
        "Access-Control-Allow-Methods": "POST, OPTIONS"
      },
      body: ""
    };
  }

  try {

    const body = JSON.parse(event.body || "{}");

    const amount = body.amount;
    const request_id = body.request_id;

    // 🔥 FIX: HANDLE STRING + BOOL
    const isTest = body.test === true || body.test === "true";

    // 🔥 DEBUG LOG
    console.log("CHECKOUT BODY:", body);

    if (!request_id) {
      return {
        statusCode: 400,
        headers: { "Access-Control-Allow-Origin": "https://myvitalink.app" },
        body: JSON.stringify({ success:false, error:"Missing request_id" })
      };
    }

    // ✅ TEST MODE — ALWAYS WORK
    if (isTest) {
      return {
        statusCode: 200,
        headers: { "Access-Control-Allow-Origin": "https://myvitalink.app" },
        body: JSON.stringify({
          url: `https://myvitalink.app/checkout-success.html?test=true&request_id=${request_id}`
        })
      };
    }

    if (!amount) {
      return {
        statusCode: 400,
        headers: { "Access-Control-Allow-Origin": "https://myvitalink.app" },
        body: JSON.stringify({ success:false, error:"Missing amount" })
      };
    }

    const session = await stripe.checkout.sessions.create({
      payment_method_types: ["card"],

      line_items: [
        {
          price_data: {
            currency: "usd",
            product_data: {
              name: "VitaLink Order"
            },
            unit_amount: amount
          },
          quantity: 1
        }
      ],

      mode: "payment",

      success_url: `https://myvitalink.app/checkout-success.html?request_id=${request_id}`,
      cancel_url: "https://myvitalink.app/order.html"
    });

    return {
      statusCode: 200,
      headers: { "Access-Control-Allow-Origin": "https://myvitalink.app" },
      body: JSON.stringify({
        url: session.url
      })
    };

  } catch (err) {
    console.error("Stripe error:", err);

    return {
      statusCode: 500,
      headers: { "Access-Control-Allow-Origin": "https://myvitalink.app" },
      body: JSON.stringify({
        success:false,
        error: err.message
      })
    };
  }
};