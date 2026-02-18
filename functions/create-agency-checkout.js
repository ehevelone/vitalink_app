import Stripe from "stripe";

export async function handler(event) {
  try {
    const stripe = new Stripe(process.env.STRIPE_SECRET_KEY);

    const { agencyId, quantity } = JSON.parse(event.body || "{}");

    if (!agencyId || !quantity) {
      return {
        statusCode: 400,
        body: "Missing agencyId or quantity"
      };
    }

    const session = await stripe.checkout.sessions.create({
      mode: "subscription",
      payment_method_types: ["card", "us_bank_account"],

      line_items: [
        {
          price: process.env.VITALINK_PRICE_ID,
          quantity: quantity
        }
      ],

      success_url:
        "https://myvitalink.app/core-node/billing-success.html",
      cancel_url:
        "https://myvitalink.app/core-node/billing-cancel.html",

      metadata: {
        agencyId: agencyId
      }
    });

    return {
      statusCode: 200,
      body: JSON.stringify({ url: session.url })
    };

  } catch (err) {
    console.error(err);
    return {
      statusCode: 500,
      body: "Checkout creation failed"
    };
  }
}
