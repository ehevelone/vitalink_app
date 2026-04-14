const Stripe = require("stripe");

/* =========================================================
   🔧 STRIPE KEY (ENV ONLY — REQUIRED)
   ========================================================= */

const stripe = new Stripe(process.env.STRIPE_SECRET_KEY);

exports.handler = async (event) => {

  const headers = {
    "Access-Control-Allow-Origin": "https://myvitalink.app",
    "Access-Control-Allow-Headers": "Content-Type",
    "Access-Control-Allow-Methods": "POST, OPTIONS"
  };

  if (event.httpMethod === "OPTIONS") {
    return {
      statusCode: 200,
      headers,
      body: ""
    };
  }

  try {

    const body = JSON.parse(event.body || "{}");

    const amount = body.amount;
    const order_id = body.order_id;

    console.log("CHECKOUT BODY:", body);

    if (!order_id) {
      return {
        statusCode: 400,
        headers,
        body: JSON.stringify({ success:false, error:"Missing order_id" })
      };
    }

    if (!amount) {
      return {
        statusCode: 400,
        headers,
        body: JSON.stringify({ success:false, error:"Missing amount" })
      };
    }

    // 🔥 REAL STRIPE SESSION (NO TEST BYPASS)
    const session = await stripe.checkout.sessions.create({
      payment_method_types: ["card"],
      mode: "payment",

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

      success_url: `https://myvitalink.app/accessories/checkout-success.html?request_id=${order_id}`,
      cancel_url: "https://myvitalink.app/order.html",

      metadata: {
        order_id: order_id
      }
    });

    return {
      statusCode: 200,
      headers,
      body: JSON.stringify({
        url: session.url
      })
    };

  } catch (err) {

    console.error("Stripe error:", err);

    return {
      statusCode: 500,
      headers,
      body: JSON.stringify({
        success:false,
        error: err.message
      })
    };
  }
};