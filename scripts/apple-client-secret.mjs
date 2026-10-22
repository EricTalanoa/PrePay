#!/usr/bin/env node
// Turns Apple's Sign in with Apple key (the AuthKey_XXXXXXXXXX.p8 file) into
// the client secret Supabase asks for: a JWT signed with that key. Apple caps
// it at 6 months, so run this again before it expires and paste the new one
// into Supabase → Authentication → Providers → Apple → Secret Key.
//
//   node scripts/apple-client-secret.mjs <path/to/AuthKey_XXXXXXXXXX.p8> <TEAM_ID> <SERVICES_ID>
//
// Runs entirely on your machine; the key is read from disk and goes nowhere.

import { createPrivateKey, sign } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { basename } from 'node:path';

const [keyPath, teamId, servicesId] = process.argv.slice(2);
if (!keyPath || !teamId || !servicesId) {
  console.error('usage: node scripts/apple-client-secret.mjs <AuthKey_XXXXXXXXXX.p8> <TEAM_ID> <SERVICES_ID>');
  process.exit(1);
}

// Apple names the file after the key: AuthKey_<KEY_ID>.p8
const keyId = basename(keyPath).match(/^AuthKey_([A-Z0-9]{10})\.p8$/i)?.[1] ?? process.env.APPLE_KEY_ID;
if (!keyId) {
  console.error('could not read the Key ID from the file name; set APPLE_KEY_ID=XXXXXXXXXX');
  process.exit(1);
}

const now = Math.floor(Date.now() / 1000);
const SIX_MONTHS = 180 * 24 * 60 * 60; // just under Apple's 6-month limit
const b64 = obj => Buffer.from(JSON.stringify(obj)).toString('base64url');
const header = b64({ alg: 'ES256', kid: keyId, typ: 'JWT' });
const claims = b64({ iss: teamId, iat: now, exp: now + SIX_MONTHS, aud: 'https://appleid.apple.com', sub: servicesId });

const key = createPrivateKey(readFileSync(keyPath));
// JWTs use the raw r||s signature form, not the DER form Node gives by default.
const signature = sign('sha256', Buffer.from(`${header}.${claims}`), { key, dsaEncoding: 'ieee-p1363' }).toString('base64url');

console.log(`${header}.${claims}.${signature}`);
console.error(`\nExpires ${new Date((now + SIX_MONTHS) * 1000).toDateString()}. Set a reminder to run this again before then.`);
