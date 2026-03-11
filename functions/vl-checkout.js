const Stripe = require("stripe");

const stripe = new Stripe(process.env.STRIPE_SECRET_KEY);

exports.handler = async (event) => {
  try {

    const session = await stripe.checkout.sessions.create({
      payment_method_types: ["card", "us_bank_account"],

      mode: "payment",

      line_items: [
        {
          price: process.env.STRIPE_ACTIVATION_PRICE_ID,
          quantity: 1,
        },
      ],

      success_url: "https://myvitalink.app/activate-success.html",
      cancel_url: "https://myvitalink.app/activate.html",
    });

    return {
      statusCode: 200,
      body: JSON.stringify({ url: session.url }),
    };

  } catch (err) {
    return {
      statusCode: 500,
      body: JSON.stringify({ error: err.message }),
    };
  }
};