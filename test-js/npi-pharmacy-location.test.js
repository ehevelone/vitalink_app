const test = require('node:test');
const assert = require('node:assert/strict');
const Module = require('node:module');
const path = require('node:path');
const registry = require('../functions/services/npi-registry');

function lookupWith(searchNpi, cached = [], taxonomyResolver = () => []) {
  const absolutePath = path.resolve(__dirname, '../functions/npi_lookup.js');
  const originalLoad = Module._load;
  Module._load = function (request, parent, isMain) {
    if (request === './services/npi-registry') return { ...registry, searchNpi };
    if (request === './services/npi-taxonomies') return { taxonomiesForSpecialty: taxonomyResolver };
    if (request === './services/npi-verification') {
      return {
        authenticate: async () => ({ actor: 'test' }),
        findCachedCandidates: async () => cached,
        cacheConfirmedCandidate: async () => {},
      };
    }
    return originalLoad.call(this, request, parent, isMain);
  };
  try {
    delete require.cache[require.resolve(absolutePath)];
    return require(absolutePath).handler;
  } finally {
    Module._load = originalLoad;
  }
}

async function run(handler, body) {
  const response = await handler({ httpMethod: 'POST', body: JSON.stringify({
    entityType: 'pharmacy', name: 'Walgreens', ...body,
  }) });
  assert.equal(response.statusCode, 200);
  return JSON.parse(response.body);
}

function candidate(npi, city, state, postalCode, phone = '') {
  return { npi, displayName: 'Walgreens', city, state, postalCode, phone };
}

test('Omaha name-only search excludes out-of-state practice locations and does not auto-verify', async () => {
  const scopes = [];
  const handler = lookupWith(async (scope) => {
    scopes.push(scope);
    if (scope.postalCode) return [];
    return [
      candidate('1111111111', 'Omaha', 'NE', '68114'),
      candidate('2222222222', 'Glenview', 'IL', '60026'),
    ];
  });
  const result = await run(handler, {
    city: 'Omaha', state: 'Nebraska', postalCode: '68104',
  });
  assert.deepEqual(scopes.map((scope) => [scope.city, scope.state, scope.postalCode]), [
    [undefined, 'NE', '68104'],
    ['Omaha', 'NE', undefined],
  ]);
  assert.equal(result.verificationStatus, 'needs_review');
  assert.equal(result.npi, null);
  assert.deepEqual(result.candidates.map((item) => item.npi), ['1111111111']);
});

test('alternate pharmacy ZIP can find a store outside the home state', async () => {
  const scopes = [];
  const handler = lookupWith(async (scope) => {
    scopes.push(scope);
    return [candidate('3333333333', 'Port Orchard', 'WA', '98366')];
  });
  const result = await run(handler, { postalCode: '98366' });
  assert.equal(scopes.length, 1);
  assert.equal(scopes[0].postalCode, '98366');
  assert.equal(scopes[0].state, undefined);
  assert.equal(result.verificationStatus, 'needs_review');
  assert.equal(result.candidates[0].state, 'WA');
});

test('location search widens only within the home state when city has no match', async () => {
  const scopes = [];
  const handler = lookupWith(async (scope) => {
    scopes.push(scope);
    return scope.city
      ? []
      : [candidate('4444444444', 'Lincoln', 'NE', '68501')];
  });
  const result = await run(handler, { city: 'Omaha', state: 'NE' });
  assert.deepEqual(scopes.map((scope) => scope.state), ['NE', 'NE']);
  assert.equal(result.candidates[0].city, 'Lincoln');
});

test('exact phone match may identify an out-of-state pharmacy without offering random nationwide matches', async () => {
  const handler = lookupWith(async (scope) => scope.state
    ? [candidate('5555555555', 'Omaha', 'NE', '68114', '4025551111')]
    : [candidate('6666666666', 'Council Bluffs', 'IA', '51501', '7125552222')]);
  const result = await run(handler, {
    city: 'Omaha', state: 'NE', phone: '712-555-2222',
  });
  assert.equal(result.verificationStatus, 'verified');
  assert.equal(result.npi, '6666666666');
});

test('missing location and phone leaves pharmacy unresolved rather than showing arbitrary states', async () => {
  let searched = false;
  const handler = lookupWith(async () => { searched = true; return []; });
  const result = await run(handler, {});
  assert.equal(result.verificationStatus, 'unverified');
  assert.deepEqual(result.candidates, []);
  assert.equal(searched, false);
});

test('cached name-only candidates outside the requested location are ignored', async () => {
  const handler = lookupWith(async () => [], [
    candidate('7777777777', 'Glenview', 'IL', '60026'),
  ]);
  const result = await run(handler, { city: 'Omaha', state: 'NE' });
  assert.equal(result.verificationStatus, 'unverified');
  assert.deepEqual(result.candidates, []);
});

test('mail-order choice searches the mail-order taxonomy nationwide and never auto-verifies', async () => {
  const searches = [];
  const handler = lookupWith(async (scope) => {
    searches.push(scope);
    return [
      candidate('8888888888', 'Phoenix', 'AZ', '85001'),
      candidate('9999999999', 'Austin', 'TX', '78701'),
    ];
  });
  const result = await run(handler, {
    name: 'Optum Pharmacy', city: 'Omaha', state: 'NE', postalCode: '68114',
    phone: '4025551111', mailOrder: true,
  });
  assert.equal(searches.length, 1);
  assert.equal(searches[0].name, 'Optum Pharmacy*');
  assert.equal(searches[0].taxonomyDescription, 'Mail Order Pharmacy');
  assert.deepEqual(searches[0].taxonomyCodes, ['3336M0002X']);
  assert.equal(searches[0].state, undefined);
  assert.equal(searches[0].postalCode, undefined);
  assert.equal(result.verificationStatus, 'needs_review');
  assert.equal(result.npi, null);
  assert.equal(result.candidates.length, 2);
});

test('local pharmacy search excludes mail-order taxonomy', async () => {
  const searches = [];
  const handler = lookupWith(async (scope) => {
    searches.push(scope);
    return [];
  });
  const result = await run(handler, { state: 'NE', mailOrder: false });
  assert.equal(result.verificationStatus, 'unverified');
  assert.deepEqual(searches[0].excludedTaxonomyCodes, ['3336M0002X']);
});

test('VA Pharmacy searches the official VA pharmacy taxonomy by ZIP', async () => {
  const searches = [];
  const handler = lookupWith(async (scope) => {
    searches.push(scope);
    return [{
      npi: '1366491524',
      displayName: 'OMAHA VAMC',
      taxonomy: 'Department of Veterans Affairs (VA) Pharmacy',
      city: 'OMAHA',
      state: 'NE',
      postalCode: '681051850',
      phone: '4029954903',
    }];
  });

  const result = await run(handler, {
    name: 'VA Pharmacy',
    state: 'NE',
    postalCode: '68105',
    mailOrder: false,
  });

  assert.equal(searches.length, 1);
  assert.equal(searches[0].name, '');
  assert.equal(
    searches[0].taxonomyDescription,
    'Department of Veterans Affairs (VA) Pharmacy',
  );
  assert.deepEqual(searches[0].taxonomyCodes, ['332100000X']);
  assert.equal(searches[0].postalCode, '68105');
  assert.equal(result.candidates[0].npi, '1366491524');
});

test('plain VA pharmacy label uses the VA taxonomy search', async () => {
  const searches = [];
  const handler = lookupWith(async (scope) => {
    searches.push(scope);
    return [{
      npi: '1366491524',
      displayName: 'OMAHA VAMC',
      taxonomy: 'Department of Veterans Affairs (VA) Pharmacy',
      city: 'OMAHA',
      state: 'NE',
      postalCode: '681051850',
      phone: '4029954903',
    }];
  });

  const result = await run(handler, {
    name: 'VA',
    state: 'NE',
    postalCode: '68105',
    mailOrder: false,
  });

  assert.equal(searches[0].name, '');
  assert.deepEqual(searches[0].taxonomyCodes, ['332100000X']);
  assert.equal(result.candidates[0].displayName, 'OMAHA VAMC');
});

test('mail-order wildcard-only name is rejected', async () => {
  const handler = lookupWith(async () => []);
  const response = await handler({
    httpMethod: 'POST',
    body: JSON.stringify({ entityType: 'pharmacy', name: '**', mailOrder: true }),
  });
  assert.equal(response.statusCode, 400);
});

test('provider search uses only the requested ZIP and requires confirmation', async () => {
  const searches = [];
  const handler = lookupWith(async (scope) => {
    searches.push(scope);
    return [{
      ...candidate('1234567890', 'Omaha', 'NE', '68114'),
      displayName: 'John Smith, MD',
    }];
  });
  const result = await run(handler, {
    entityType: 'provider',
    name: 'Smith',
    postalCode: '68114',
  });
  assert.equal(searches.length, 1);
  assert.equal(searches[0].postalCode, '68114');
  assert.equal(searches[0].city, '');
  assert.equal(searches[0].state, '');
  assert.equal(result.verificationStatus, 'needs_review');
  assert.equal(result.npi, null);
  assert.equal(result.candidates.length, 1);
});

test('provider search does not widen when the requested ZIP has no results', async () => {
  const searches = [];
  const handler = lookupWith(async (scope) => {
    searches.push(scope);
    return [];
  });
  const result = await run(handler, {
    entityType: 'provider',
    name: 'Smith',
    postalCode: '68114',
  });
  assert.equal(searches.length, 1);
  assert.equal(searches[0].postalCode, '68114');
  assert.equal(result.verificationStatus, 'unverified');
  assert.deepEqual(result.candidates, []);
});

test('provider search retries without specialty when the specialty has no match', async () => {
  const searches = [];
  const handler = lookupWith(async (scope) => {
    searches.push(scope);
    if (scope.taxonomyDescription) return [];
    return [{
      ...candidate('1689454357', 'Columbus', 'NE', '68601'),
      displayName: 'KARMEN SUE VAN DE WALLE',
      taxonomy: 'Counselor',
    }];
  }, [], () => [{ code: '101YM0800X', description: 'Mental Health Counselor' }]);

  const result = await run(handler, {
    entityType: 'provider',
    name: 'Karmen VanDeWalle',
    postalCode: '68601',
    specialty: 'Mental Health Counselor',
  });

  assert.equal(searches.length, 2);
  assert.equal(searches[0].taxonomyDescription, 'Mental Health Counselor');
  assert.equal(searches[1].taxonomyDescription, undefined);
  assert.deepEqual(searches.map((scope) => scope.postalCode), ['68601', '68601']);
  assert.equal(result.candidates[0].npi, '1689454357');
});

test('provider specialty search also returns other exact surname-variant matches', async () => {
  const searches = [];
  const karmen = {
    ...candidate('1689454357', 'Columbus', 'NE', '68601'),
    displayName: 'KARMEN SUE VAN DE WALLE',
    taxonomy: 'Counselor',
  };
  const michelle = {
    ...candidate('1619882255', 'Columbus', 'NE', '68601'),
    displayName: 'MICHELLE VANDEWALLE',
    taxonomy: 'Case Manager/Care Coordinator',
  };
  const handler = lookupWith(async (scope) => {
    searches.push(scope);
    return scope.taxonomyDescription ? [karmen] : [michelle, karmen];
  }, [], () => [{ code: '101Y00000X', description: 'Counselor' }]);

  const result = await run(handler, {
    entityType: 'provider',
    name: 'karmen vandewalle',
    postalCode: '68601',
    specialty: 'Mental Health Counselor',
  });

  assert.equal(searches.length, 2);
  assert.deepEqual(result.candidates.map((item) => item.npi), [
    '1689454357', '1619882255',
  ]);
});
