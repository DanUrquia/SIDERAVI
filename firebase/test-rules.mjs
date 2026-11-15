import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';

// Use only the isolated localhost demo project started by firebase emulators:exec.
const project = 'demo-sideravi';
const origin = 'http://127.0.0.1:9000';
const identity = 'http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:';
const session = 'test-' + randomUUID();
const root = '/missions/jezero/sessions/' + session;
const write = (value) => ({
  method: 'PUT', body: JSON.stringify(value), headers: {'content-type': 'application/json'}
});

async function account() {
  const credentials = {
    email: randomUUID() + '@example.test', password: randomUUID(), returnSecureToken: true,
  };
  async function auth(method) {
    const response = await fetch(identity + method + '?key=demo', {
      ...write(credentials), method: 'POST',
    });
    assert.equal(response.status, 200, await response.clone().text());
    return response.json();
  }
  const created = await auth('signUp');
  const signedIn = await auth('signInWithPassword');
  assert.equal(signedIn.localId, created.localId);
  return signedIn;
}

function uri(path, token) {
  const target = new URL(path + '.json', origin);
  target.searchParams.set('ns', project + '-default-rtdb');
  if (token) target.searchParams.set('auth', token);
  return target;
}

async function expectStatus(path, token, status, options) {
  const admin = token === 'owner';
  const result = await fetch(uri(path, admin ? null : token), {
    ...options,
    headers: {...options?.headers, ...(admin ? {authorization: 'Bearer owner'} : {})},
  });
  const body = await result.text();
  assert.equal(result.status, status, body);
}

const [dan, adrian, outsider] = await Promise.all([account(), account(), account()]);
const seed = {
  metadata: {state: 'active', baseLat: 18, baseLon: 77},
  members: {'ARES-01': dan.localId, 'ARES-02': adrian.localId},
};
await expectStatus(root, 'owner', 200, write(seed));
const pose = {
  marsLon: 77, marsLat: 18, mode: 'live', quality: 'uncertain',
  online: true, updated: {'.sv': 'timestamp'}, relativeHeading: 20,
};
const presence = root + '/presence';
await expectStatus(presence, null, 401);
await expectStatus(presence, outsider.idToken, 401);
await expectStatus(presence, adrian.idToken, 200);
await expectStatus(root + '/members', adrian.idToken, 401);
await expectStatus(root + '/members/ARES-01', null, 401);
await expectStatus(root + '/members/ARES-01', outsider.idToken, 401);
await expectStatus(root + '/members/ARES-01', dan.idToken, 200);
await expectStatus(root + '/members/ARES-02', adrian.idToken, 200);
await expectStatus(root + '/members/ARES-01', adrian.idToken, 401);
await expectStatus(root + '/members/ARES-02', dan.idToken, 401);
await expectStatus(root + '/members/ARES-01', dan.idToken, 401, write(outsider.localId));
await expectStatus(root.replace('jezero', 'gale') + '/presence', dan.idToken, 401);
await expectStatus(presence + '/ARES-02', dan.idToken, 401, write(pose));
await expectStatus(presence + '/ARES-01', dan.idToken, 401, write({...pose, earthLatitude: 0}));
await expectStatus(presence + '/ARES-01', dan.idToken, 401, write({...pose, marsLat: 91}));
await expectStatus(presence + '/ARES-01', dan.idToken, 401, write({...pose, updated: 1}));
await expectStatus(presence + '/ARES-01', dan.idToken, 200, write(pose));
await expectStatus(presence + '/ARES-02', adrian.idToken, 200, write(pose));

const abort = new AbortController();
const stopwatch = setTimeout(() => abort.abort(), 5000);
try {
  const response = await fetch(uri(presence, adrian.idToken), {
    headers: {accept: 'text/event-stream'}, signal: abort.signal,
  });
  assert.equal(response.status, 200);
  const reader = response.body.pipeThrough(new TextDecoderStream()).getReader();
  assert.match((await reader.read()).value, /"ARES-01"/);
  await expectStatus(presence + '/ARES-01', dan.idToken, 200, write({...pose, relativeHeading: 95}));
  let event = '';
  while (!event.includes('"relativeHeading":95')) {
    const {value, done} = await reader.read();
    assert.equal(done, false);
    event += value;
  }
} finally {
  clearTimeout(stopwatch);
  abort.abort();
}

await expectStatus(root + '/metadata/state', 'owner', 200, write('ended'));
await expectStatus(root + '/members/ARES-01', dan.idToken, 401);
await expectStatus(presence, adrian.idToken, 401);
await expectStatus(presence + '/ARES-01', dan.idToken, 401, write(pose));
console.log('Firebase emulator passed password sign-in, own-slot membership and writes, session isolation, rejection of extra fields, streamed updates, and termination.');
