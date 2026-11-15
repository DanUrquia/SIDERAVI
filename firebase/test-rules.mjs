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

async function anonymousAccount() {
  const response = await fetch(identity + 'signUp?key=demo', {
    ...write({returnSecureToken: true}), method: 'POST',
  });
  assert.equal(response.status, 200, await response.clone().text());
  return response.json();
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
  return JSON.parse(body);
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

const [danPhone, adrianPhone, sparePhone] = await Promise.all(
  Array.from({length: 3}, anonymousAccount),
);
const missionIds = ['endeavour', 'gale', 'columbia-hills', 'valles-marineris', 'jezero'];
const sessionAt = mission => '/missions/' + mission + '/sessions/field-test-01';

// Reuse the legacy account membership for every mission. The first anonymous
// sign-in by itself is insufficient to grant either slot any permissions.
for (const mission of missionIds) {
  const session = sessionAt(mission);
  await expectStatus(session, 'owner', 200, write(seed));
  await expectStatus(session + '/presence', danPhone.idToken, 401);
  await expectStatus(session + '/presence/ARES-01', danPhone.idToken, 401, write(pose));
  await expectStatus(
    session + '/deviceMembers/ARES-01',
    danPhone.idToken,
    401,
    write(danPhone.localId),
  );
  await expectStatus(session + '/deviceMembers/ARES-01', 'owner', 200, write(danPhone.localId));
  await expectStatus(session + '/deviceMembers/ARES-02', 'owner', 200, write(adrianPhone.localId));
}

for (const [index, mission] of missionIds.entries()) {
  const session = sessionAt(mission);
  const path = session + '/presence';
  await expectStatus(path, null, 401);
  await expectStatus(path, sparePhone.idToken, 401);
  await expectStatus(session + '/deviceMembers', danPhone.idToken, 401);
  await expectStatus(session + '/deviceMembers/ARES-01', adrianPhone.idToken, 401);
  await expectStatus(session + '/deviceMembers/ARES-02', danPhone.idToken, 401);
  assert.equal(
    await expectStatus(session + '/deviceMembers/ARES-01', danPhone.idToken, 200),
    danPhone.localId,
  );
  assert.equal(
    await expectStatus(session + '/deviceMembers/ARES-02', adrianPhone.idToken, 200),
    adrianPhone.localId,
  );
  await expectStatus(session + '/members/ARES-01', dan.idToken, 200);
  assert.equal(await expectStatus(path, danPhone.idToken, 200), null);
  await expectStatus(path + '/ARES-02', danPhone.idToken, 401, write(pose));
  await expectStatus(path + '/ARES-01', adrianPhone.idToken, 401, write(pose));
  await expectStatus(
    path + '/ARES-01',
    danPhone.idToken,
    401,
    write({...pose, earthLatitude: 0}),
  );
  await expectStatus(path + '/ARES-02', adrianPhone.idToken, 200, write(pose));

  const opening = new AbortController();
  const timeout = setTimeout(() => opening.abort(), 5000);
  try {
    const response = await fetch(uri(path, adrianPhone.idToken), {
      headers: {accept: 'text/event-stream'}, signal: opening.signal,
    });
    assert.equal(response.status, 200);
    const reader = response.body.pipeThrough(new TextDecoderStream()).getReader();
    assert.match((await reader.read()).value, /"ARES-02"/);
    const longitude = 60 + index;
    await expectStatus(
      path + '/ARES-01',
      danPhone.idToken,
      200,
      write({...pose, marsLon: longitude}),
    );
    let event = '';
    while (!event.includes('"marsLon":' + longitude)) {
      const {value, done} = await reader.read();
      assert.equal(done, false);
      event += value;
    }
    assert.equal((await expectStatus(path, danPhone.idToken, 200))['ARES-01'].marsLon, longitude);
    const otherMission = missionIds[(index + 1) % missionIds.length];
    const neighbor = await expectStatus(sessionAt(otherMission) + '/presence', danPhone.idToken, 200);
    assert.notEqual(neighbor?.['ARES-01']?.marsLon, longitude);
  } finally {
    clearTimeout(timeout);
    opening.abort();
  }
}

const refresh = await fetch(
  'http://127.0.0.1:9099/securetoken.googleapis.com/v1/token?key=demo',
  {
    method: 'POST',
    body: new URLSearchParams({
      grant_type: 'refresh_token', refresh_token: danPhone.refreshToken,
    }),
  },
);
assert.equal(refresh.status, 200, await refresh.clone().text());
const renewed = await refresh.json();
assert.equal(renewed.user_id, danPhone.localId);
await expectStatus(sessionAt('endeavour') + '/deviceMembers/ARES-01', renewed.id_token, 200);

// A password credential with a matching UID still cannot access the
// anonymous-device member record. It only retains its original legacy slot.
const gale = sessionAt('gale');
await expectStatus(gale + '/deviceMembers/ARES-02', 'owner', 200, write(dan.localId));
await expectStatus(gale + '/deviceMembers/ARES-02', dan.idToken, 401);
await expectStatus(gale + '/presence/ARES-02', dan.idToken, 401, write(pose));

// Revoking or replacing a device is mission-local. That UID can still read
// the other approved sessions while the replaced slot fails closed.
await expectStatus(gale + '/deviceMembers/ARES-01', 'owner', 200, write(sparePhone.localId));
await expectStatus(gale + '/presence', danPhone.idToken, 401);
await expectStatus(gale + '/presence/ARES-01', danPhone.idToken, 401, write(pose));
await expectStatus(gale + '/presence/ARES-01', sparePhone.idToken, 200, write(pose));
await expectStatus(sessionAt('endeavour') + '/presence', sparePhone.idToken, 401);
await expectStatus(sessionAt('endeavour') + '/presence', danPhone.idToken, 200);

const jezero = sessionAt('jezero');
await expectStatus(jezero + '/metadata/state', 'owner', 200, write('ended'));
await expectStatus(jezero + '/deviceMembers/ARES-01', danPhone.idToken, 401);
await expectStatus(jezero + '/presence', adrianPhone.idToken, 401);
await expectStatus(jezero + '/presence/ARES-01', danPhone.idToken, 401, write(pose));

console.log('Firebase emulator passed anonymous enrollment, both own-slot writes, streamed isolation across all five field-test-01 sessions, and device replacement.');
