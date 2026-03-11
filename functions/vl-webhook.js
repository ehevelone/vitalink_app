const Stripe = require("stripe");

const stripe = new Stripe(process.env.STRIPE_SECRET_KEY);

exports.handler = async (event) => {

  const sig = event.headers["stripe-signature"];

  let stripeEvent;

  try {
    stripeEvent = stripe.webhooks.constructEvent(
      event.body,
      sig,
      process.env.STRIPE_WEBHOOK_SECRET
    );
  } catch (err) {
    return {
      statusCode: 400,
      body: `Webhook Error: ${err.message}`,
    };
  }

  if (stripeEvent.type === "checkout.session.completed") {

    const session = stripeEvent.data.object;

    const email = session.customer_details.email;

    console.log("Payment success for:", email);

    // Activation code generation placeholder
    const code = "VL-" + Math.random().toString(36).substring(2,8).toUpperCase();

    console.log("Generated code:", code);

    // Later we will:
    // store in Supabase
    // send email to user

  }

  return {
    statusCode: 200,
    body: JSON.stringify({ received: true }),
  };

};