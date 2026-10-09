// Schema setup (CREATE/ALTER ... IF NOT EXISTS) takes table locks even when
// nothing changes, so running it on every request queues requests behind each
// other. Run each setup once per warm function instance instead; a failure is
// not cached, so the next request retries it.
const pending = new Map();

function schemaOnce(key, setup) {
  return function runSchemaSetupOnce(...args) {
    if (!pending.has(key)) {
      const run = Promise.resolve()
        .then(() => setup(...args))
        .catch((error) => {
          pending.delete(key);
          throw error;
        });
      pending.set(key, run);
    }
    return pending.get(key);
  };
}

module.exports = { schemaOnce };
