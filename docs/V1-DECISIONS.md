# NOMA v1 Implementation Decisions

- Decided: 2026-10-15 (Asia/Seoul)
- Scope: First experimental release
- Status: v1 baseline finalized. Implementation, deployment, and standards interoperability require separate verification.
- This document resolves the technical and policy choices left open in the requirements.

## 1. Decision Summary

| Item | v1 decision |
| --- | --- |
| Management application | Next.js 16, TypeScript, App Router, and Node.js Route Handlers |
| Runtime | Node.js 24 LTS; pin a security-patched release in this series using lockfiles and image digests when adopted |
| Database | MySQL 8.4 LTS, InnoDB, utf8mb4, UTC |
| Data access | Parameter-bound SQL with mysql2; versioned SQL migrations |
| UI | Tailwind CSS 4, React, English by default and the only shipped UI language in v1, selected Dark Terminal design |
| Wallet | React + Vite + TypeScript PWA on a separate origin; private keys and presentations handled in the browser |
| Deployment | Linux containers, Docker Compose, Caddy HTTPS proxy; independent of a specific cloud |
| Photo storage | S3-compatible object storage; MinIO for development |
| Registration number | UUID v4; lowercase hyphenated UUID externally, BINARY(16) in the DB |
| Management authentication | Passkeys per NOMA identity; no legal name, phone number, real email, or conventional password account |
| Recovery | Random 256-bit single-use recovery code per NOMA identity; register new passkey and holder key during recovery |
| Credentials | SD-JWT VC, mandatory holder key binding, fixed profile schema |
| Presentation | OpenID4VP 1.0 Final, x509_san_dns, DCQL, direct_post.jwt |
| Signatures | Issuer and holder keys: ES256 / P-256 / SHA-256 |
| Credential lifetime | 30 days from issuance; user-requested renewal |
| Status | Signed Token Status Lists distributed publicly in batches |
| Initial issuance | NOMA-specific versioned API; no OpenID4VCI in v1 |
| Multiple NOMA identities | Allowed; no person-level unified account or ownership list on the server |
| Out of scope | Social networks, complete user listings, name search, messengers, arbitrary fields, external service registration |

Pin patch versions and container digests at installation time. This is a dependency management rule for incorporating security patches, not an unresolved choice. Preparing this document did not install packages or create services or paid resources.

## 2. Deployment and Information Boundaries

Separate the following three logical origins. Purchase production domains during deployment.

- `ISSUER_ORIGIN`: Management application, issuance and management APIs, public profile lookup.
- `WALLET_ORIGIN`: Static wallet PWA files; no backend for handling external requests.
- `ASSET_ORIGIN`: Photos and shared static files. Configure issuer public key and status paths as paths serving shared static files.

In production, use separate HTTPS hosts under the same registered domain. Preserve origin separation and first-party communication; keep cookies on the issuer host only.

The wallet origin is the security boundary for private key storage. Changing it after launch prevents automatic access to existing browser keys and requires recovery.

For issuance and key replacement, connect the management screen and wallet using a user-opened popup and `postMessage`. Validate the exact targetOrigin, event.origin, event.source, and a single-use connection nonce. Exchange public keys, issuance challenges, and their signatures, as well as the resulting noma_id, credential_id, and single-use receipt token. The wallet fetches credential bytes directly from the issuance API (Section 6.1). Never send private keys, plaintext recovery codes, or external presentation requests through this channel. Send recovery code hashes only when needed for registration. Apply Referrer-Policy: no-referrer to wallet documents.

Put presentation request URIs delivered to the wallet in the URL fragment so they are not included in static hosting HTTP requests. After reading the fragment, the wallet removes it from the address bar and fetches the external verifier's request object directly. External verifiers allow the CORS needed by browser wallets. The wallet also sends responses directly.

The NOMA issuer server must not proxy presentation request fetching. Do not send external service names, requests, responses, signups, or approval records to the server. Do not include analytics SDKs, external advertisements, or remote error collection SDKs in the wallet. Static file loading and issuance/renewal communication still occur; do not claim that the web wallet is cryptographically independent of its issuer operator.

Develop on separate localhost ports. Inject the actual WebAuthn RP ID and production origins through deployment configuration. Never share development and production credentials.

## 3. Registration Numbers, Strings, and Time

- `noma_id`: Cryptographically random UUID v4; contains no sequence, birth year, or user attributes.
- Allow users to view and copy the full UUID. Do not add prefixes such as `noma_`.
- Do not use the byte swap option of UUID_TO_BIN/BIN_TO_UUID for server UUID conversion.
- Internal key, authentication, photo, and credential IDs also use UUID v4 or collision-resistant identifiers required by the protocol.
- `name`, `email`: Trim leading/trailing whitespace → normalize to Unicode NFC → validate length by Unicode code point count.
- Reject control characters and line breaks; render HTML as plain text. Apply consistent validation to invisible characters without restricting ordinary Unicode names to ASCII.
- Names: 1–50 characters. Emails: 1–254 characters or null. Do not require syntax such as `@`.
- `birth_year`: Integer 1–9999 or null. Do not vary the range by the current year or actual age.
- Use null for optional JSON fields. Convert empty email strings to null.
- DB: DATETIME(3). Server and DB sessions: UTC. API: `YYYY-MM-DDTHH:mm:ss.sssZ`.
- A PATCH with unchanged values does not change revision or updated_at.
- Reject unknown fields, duplicate JSON keys, and invalid data types.

## 4. Authentication, Recovery, and Multiple Identities

### 4.1 Management Authentication

Keep separate management credentials for each NOMA identity. Register passkeys as discoverable credentials and require user verification. Each server session is bound to one NOMA identity.

- Do not provide email/phone signup or recovery.
- Maximum five passkeys per NOMA identity. Reauthenticate when adding or deleting individual passkeys.
- Passkey registration/login challenges: 32 random bytes, five-minute expiry, single-use.
- Sessions: 32-byte random tokens; store only SHA-256 hashes on the server.
- Cookies: HttpOnly, Secure, SameSite=Lax, host-only. Also validate CSRF tokens and Origin.
- Expire after 30 minutes of inactivity or 12 hours absolutely. Key replacement and NOMA revocation in ordinary management sessions require passkey reauthentication within five minutes. For a lost passkey, recovery code verification in Section 4.3 replaces this requirement.
- Do not provide conventional password login. Explain that issuance and management are unsupported where passkeys are unavailable.

### 4.2 Holder Keys

Each NOMA identity has one active P-256 holder key. Store the wallet-generated, non-extractable CryptoKey in IndexedDB; register only its public key on the server. Management passkeys and holder keys are separate.

- During registration, prove control by signing the server's single-use challenge with the new private key.
- The wallet must not sign without explicit user approval.
- After browser storage deletion or device loss, replace the holder key rather than restoring the old private key.
- Non-extractability prevents key export; it is not a hardware guarantee against signing by malicious same-origin scripts.
- Reduce key misuse risks through exclusion of third-party scripts, strict CSP, safe DOM output, build integrity, and a separate origin.

### 4.3 Recovery Policy

The wallet generates a random 256-bit recovery code, displayed in grouped Base32. Store only its SHA-256 verification hash on the server at registration. Unlike a human password, this code has sufficient random entropy.

- Users download and securely retain a recovery file (`.noma-recovery.json`) containing only noma_id, format version, and recovery code.
- This file is a management secret, distinct from a profile credential. Clearly explain this in the UI.
- Never store or log plaintext recovery codes or files on the server.
- Submitting a recovery code creates a restricted five-minute recovery session to register a new passkey and holder key together.
- Restricted recovery sessions permit only new passkey/holder key challenges and registration for that NOMA identity, setting a new recovery code hash, and recovery completion. Reject profile changes, NOMA revocation, credential downloads, and other ordinary management actions. After completion, sign in with the new passkey to create an ordinary management session.
- Do not consume the code when creating a recovery session. Lock and check that it is still unused in the completion transaction, then consume it exactly once. Only one of multiple sessions created with the same code may complete.
- The recovery completion transaction revokes all previous passkeys, sessions, holder keys, and valid credentials, and replaces the recovery code.
- Recovery initiation, verification failure, or completion transaction rollback must not revoke existing authentication methods. After commit, external recording or publication delays remain pending rather than being rolled back as failures (Section 9.1).
- An existing passkey can authenticate management access to replace a holder key, even when the old holder key is unavailable. Revoke old credentials.
- If both passkeys and the recovery code are lost, do not provide operator-assisted real-world identity checks or manual account recovery.

### 4.4 Multiple Identities and Devices

A person may create multiple NOMA identities. A wallet may store multiple identities, but the server does not group them into a person-level unified account. Do not impose a per-person issuance limit.

v1 does not copy or synchronize a NOMA identity's holder key across devices. Registering a new holder key on another device revokes the old key and credentials. Simultaneous holder keys on multiple devices are outside v1 scope. Do not guarantee that issuance/management communication, IP addresses, or other signals cannot create correlations.

## 5. Credentials and OpenID4VP Profile

### 5.1 Pinned Specifications

- Presentation protocol: OpenID4VP 1.0 Final (2025-07-09).
- Base SD-JWT processing: RFC 9901.
- Credentials: draft-ietf-oauth-sd-jwt-vc-19, format `dc+sd-jwt`.
- Status: draft-ietf-oauth-status-list-21, JWT-based Token Status List.
- Do not label the two drafts as final standards. Adopt later revisions through a profile version change and interoperability testing.
- NOMA interoperability profile version: `noma-vp-1.0`.

### 5.2 Credential Structure

The credential envelope contains issuer `iss`, credential type `vct`, issuance time `iat`, expiration time `exp`, credential identifier `jti`, public key `cnf.jwk`, and status reference `status`. The JOSE header uses a fixed allowed algorithm and `kid`.

Place the existing public data object unchanged under the fixed `noma` claim. This avoids a collision between the standard's `status` object and the profile's `noma.status` string. Preserve the `noma.profile` structure.

- noma_id and schema, revision, time, and status metadata are mandatory in presentations.
- Encode each of the four `profile` fields for selective disclosure. This does not allow arbitrary fields.
- The full public lookup API continues to return all four fields. Selective disclosure does not make the public lookup data private.
- Distinguish null for unset information from absence of an undisclosed field. The wallet must not fill undisclosed fields using the public lookup API.
- Allow only `kty`, `crv`, `x`, and `y` in holder public JWKs. Reject remote key URLs and private key `d`.
- Use ES256 for issuer signatures and Key Binding JWTs. Validate KB-JWT nonce, aud, iat, and sd_hash.
- If a photo exists, put the stored file's SHA-256 in the separate fixed `photo_sha256` claim and disclose it together with photo_id. Use null when no photo exists. Do not embed photo bytes in credentials.

### 5.3 External Verifiers, Requests, and Responses

- client_id: `x509_san_dns:<verifier domain>`.
- Use signed request objects and x5c certificate chains. The wallet validates trusted public Web PKI roots, chain, validity period, DNS SAN, certificate purpose, and signature.
- Allow only ES256, RS256, and PS256 for verifier request signatures. RSA keys must be at least 2048 bits.
- Allow HTTPS response destinations only on the same host as the validated client_id. Restrict request URIs to that host as well. Localhost development exceptions are allowed only in development builds.
- Requests expire within five minutes; allow 60 seconds of clock skew. Generate nonce and state as 32 random bytes and bind them to the verifier's browser session.
- Use DCQL and require `require_cryptographic_holder_binding=true`.
- Responses: `direct_post.jwt`, JWE ECDH-ES + A256GCM. Include the response encryption key in signed request metadata.
- The wallet POSTs directly to the response destination. The verifier provides the necessary CORS for the wallet origin.
- The verifier atomically consumes the correct request session and nonce exactly once. KB-JWT maximum age: 60 seconds; future timestamp tolerance: 60 seconds.
- Wallet request fetching: HTTPS, at most 64 KiB, 10-second timeout, no cross-host redirects. Reject IP literals, local addresses, and arbitrary protocols in production.
- Do not claim automatic support for ordinary certificates before certificate chain verification and standards requirements have passed implementation checks.
- Do not require NOMA preregistration, API key issuance, or usage destination lists.

### 5.4 Credential Lifetime and Freshness

- Valid for 30 days. Start renewal reminders seven days before expiration.
- Do not issue automatically in the background. Renew using current information and the active holder key when requested by the user in the wallet.
- Renewal alone does not increment the profile revision.
- Keep one valid credential per NOMA identity. Revoke the old credential and issue a new one on renewal or reissuance.
- Increment revision and revoke existing credentials when the profile changes. Show that the wallet needs a new credential.
- Revoke all old credentials on holder key replacement, recovery, or NOMA revocation.
- Offline tools that verify issuance alone must not authorize current signups.

### 5.5 Status Distribution

- Token Status Lists: one-bit status (0=valid, 1=revoked), 131,072 slots per list, randomly assigned slots. Keep unassigned slots revoked.
- The issuer signs lists with ES256 and distributes them at static public paths.
- Publish changes within 30 seconds. Even without changes, refresh issuance time every 60 seconds.
- HTTP cache max-age: 30 seconds. Verifiers accept lists issued within the last 120 seconds for signup/authentication. Status token exp: five minutes after issuance.
- Reject signup and holder authentication if a fresh list is unavailable. Do not treat stale caches as evidence of validity.
- Revocation therefore has an allowed propagation window of up to 120 seconds. Do not promise immediate worldwide updates.
- Never include noma_id or verifier service names in status URLs. Aggregate statistics only at list level.
- This is not an anonymous proof protocol that eliminates correlation through timestamps, indexes, or key information.

### 5.6 Issuer Keys

Inject issuer signing keys into v1 containers as read-only secret files. Do not store them in MySQL, Git, or environment logs. Encrypt and back up source secrets offline. Rotate every 90 days and publish new keys 24 hours before use. Retain old public keys through the last credential expiration and status list verification period.

On compromise, publicly mark the old kid as distrusted and revoke/reissue valid credentials signed by that key. The verification SDK also checks current trust status from trusted issuer key metadata and rejects expired metadata. Previously exported signatures cannot be erased historically.

Key metadata and JWKS cache TTL: 30 seconds. Maximum age for signup/authentication: 120 seconds. Remove compromised keys from the currently trusted set and distribute status lists signed with the new key. The wallet validates verifier certificates using bundled trusted roots; do not assume browsers automatically validate arbitrary x5c chains.

## 6. Initial Issuance and Management Transactions

Use NOMA-specific `/api/v1` APIs for initial issuance. v1 does not implement OpenID4VCI. Adoption of a presentation standard is separate from adoption of an initial issuance standard.

- An issuance preparation request creates a 15-minute issuance intent and management registration/holder key challenges.
- The final request binds normalized profile data, verified passkey registration results, holder key proof, and the recovery code hash.
- After validation, sign a candidate credential and record the NOMA identity, authentication, holder key, recovery data, credential, status slot, and publication outbox in one MySQL transaction.
- Never return the signed candidate before commit. Failure must not leave a public registration or valid credential.
- Bind the client idempotency key to the intent. Repeating the same completion request returns the existing result without duplicate issuance.
- Return credentials only after the corresponding status list is published. On delay, return 202 and the same issuance operation identifier for polling.
- Use If-Match/revision optimistic locking for profile changes; return 409/412 on conflict.
- Signing, publication, and file storage are not DB transactions. Maintain consistency through outboxes and retries.
- Delete management challenges one hour after expiry, completed intents and idempotency results 24 hours after completion, and incomplete intents 24 hours after expiry.

### 6.1 Wallet Credential Receipt

- Distinguish server issuance completion from wallet storage completion. Display noma_id and credential_id in management after status publication completes; show “Save to wallet required” until wallet storage is confirmed.
- Request a receipt grant using the initial issuance result token or an ordinary management session for that NOMA identity. Issue a random 32-byte receipt token only for the current credential. The token expires in five minutes and is bound to credential_id, noma_id, and the active holder_key_id. Store only its SHA-256 hash and invalidate previous unconsumed tokens for the same credential.
- The management screen sends result identifiers and the receipt token with the connection nonce to the validated wallet window. The wallet checks that its public key matches the target holder key, then requests a receipt challenge: 32 random bytes, one-minute expiry, single-use.
- The challenge response includes the target holder_key_id and public JWK thumbprint for comparison with the local key. After user approval, the wallet signs the UTF-8 bytes of the fixed-field JSON array `["noma-credential-receive-v1", ISSUER_ORIGIN, noma_id, credential_id, SHA256(receipt token), challenge]` using ES256. Use JSON serialization without whitespace, the configured origin string, and lowercase UUIDs. Encode the hash and challenge as unpadded base64url; encode the 64-byte R||S signature as base64url. The server verifies with the stored target holder key and does not accept arbitrary public keys.
- The receipt API checks the token, challenge, signature, currently active NOMA identity/holder key/credential, and completed status publication, then consumes the token and challenge transactionally. Reject expiry, different keys, different issuance targets, and duplicate receipt. Do not return credentials while security changes are pending.
- After HTTP response loss or IndexedDB storage failure, never reuse a consumed token. Request a new receipt token for the same credential from management and retry with a new challenge. Receipt retries do not issue a new credential or increment revision. After the initial result token expires, use passkey login.
- The wallet verifies the issuer signature, target IDs, cnf public key, expiration, and status, stores the credential in IndexedDB, and sends a storage completion response containing the connection nonce and credential_id to the management window. If a window closes, establish a new connection and retry. If the private key is lost, guide the user to key replacement or recovery instead.
- Key replacement and recovery do not automatically issue new credentials. The user requests issuance after registering the new key; subsequent receipt follows the same procedure. Direct wallet renewal responses follow the publication completion conditions in Section 6 after management authentication and holder proof have been verified.
- Never put tokens, challenges, signatures, or credentials in URLs, query strings, or persistent logs. Receipt APIs allow only WALLET_ORIGIN through CORS, authenticate using the token and holder proof without cookies, and apply no-store. Grant creation requires existing management authentication or the initial result token plus Origin validation.
- Delete receipt tokens one hour after expiry. Invalidate applicable unconsumed tokens on revocation, key replacement, recovery, or credential replacement. Limit grant creation, challenge requests, and receipt to 10 requests per minute per NOMA identity each.
- Transmit receipt tokens and challenges as unpadded base64url. SHA-256 operates on the decoded original random bytes. Maintain one challenge per receipt token; requesting another invalidates the previous challenge.

## 7. Photo Policy

- Input: JPEG, PNG, static WebP. GIF, SVG, video, and animation are unsupported.
- Maximum upload: 5 MiB; maximum width/height: 4096 px; maximum total: 16 megapixels.
- Validate headers and actual decoding results; never trust file extensions alone.
- Users select a square crop; the server re-encodes it as static WebP at up to 1024×1024. Do not upscale.
- Remove EXIF and other metadata during re-encoding and compute the stored file's SHA-256.
- Do not retain originals. Distinguish processing failures from issuance failures so users can re-upload.
- Use UUID-based filenames. Never use original filenames or user-provided URLs as storage paths.
- Files are immutable objects. Replacements create a new photo_id and file.
- Public cache TTL: 60 seconds. Immediately exclude old assets from lookup after revocation/replacement; delete them from server/object storage within 24 hours.
- Delete files not linked to any NOMA identity within 24 hours of upload.
- Credential photo hashes cover the stored WebP bytes. Do not guarantee deletion of external copies.

## 8. API Contract

All APIs use JSON. Public CORS allows `*` without credentials; management APIs allow only the configured issuer/wallet origins. Apply authentication and CSRF validation to management APIs.

| Method and path | Purpose |
| --- | --- |
| GET `/api/v1/nomas/{noma_id}` | Defined public response; profile=null when revoked |
| GET `/api/v1/photos/{photo_id}` | Public photo file; 410 after deletion or 404 according to public existence disclosure |
| POST `/api/v1/issuance-intents` | Issuance preparation challenge |
| POST `/api/v1/issuance-intents/{id}/complete` | Final issuance request |
| GET `/api/v1/issuance-intents/{id}/result` | Result lookup with secret operation token |
| POST `/api/v1/auth/options` | Passkey login options |
| POST `/api/v1/auth/verify` | Passkey verification and session creation |
| POST `/api/v1/auth/logout` | Session revocation |
| PATCH `/api/v1/nomas/{noma_id}` | Edit own profile |
| POST `/api/v1/nomas/{noma_id}/revoke` | Permanent revocation |
| POST `/api/v1/photos` | Authenticated upload; initial issuance restricted by intent token |
| POST `/api/v1/nomas/{noma_id}/credentials/challenge` | Holder key challenge for credential issuance/renewal |
| POST `/api/v1/nomas/{noma_id}/credentials` | Issue/renew after holder key verification |
| GET `/api/v1/nomas/{noma_id}/credentials/current` | Download current credential after management authentication |
| POST `/api/v1/nomas/{noma_id}/credentials/{credential_id}/receipt-grants` | Create single-use receipt grant with ordinary management authentication or initial result token |
| POST `/api/v1/nomas/{noma_id}/credentials/{credential_id}/receipt-challenge` | Request holder key challenge with receipt token |
| POST `/api/v1/nomas/{noma_id}/credentials/{credential_id}/receive` | Verify receipt token/challenge signature, consume atomically, and return to wallet |
| POST `/api/v1/nomas/{noma_id}/holder-keys/challenge` | New holder key registration challenge |
| POST `/api/v1/nomas/{noma_id}/holder-keys` | Replace key after reauthentication and proof of new key control |
| POST `/api/v1/recovery/start` | Verify recovery code and create restricted recovery session |
| POST `/api/v1/recovery/complete` | Complete recovery with new authentication, holder key, and recovery code |
| GET `/api/v1/security-operations/{event_id}` | Check only invalidation recording/publication completion using a separate operation token |
| POST `/api/v1/nomas/{noma_id}/passkeys/options` | Additional passkey registration challenge |
| POST `/api/v1/nomas/{noma_id}/passkeys` | Verify additional passkey registration |
| DELETE `/api/v1/nomas/{noma_id}/passkeys/{id}` | Revoke a management authentication method |
| GET `/.well-known/jwt-vc-issuer` | Standard issuer metadata |
| GET `/.well-known/jwks.json` | Issuer public keys |
| GET `/credentials/noma-v1` | NOMA credential type metadata and fixed schema |
| GET `/status/{list_id}.jwt` | Signed status list |

404 means an unknown identifier; 410 an explicitly revoked management operation; 422 input constraints; 401/403 authentication/authorization; 409/412 conflicts; 429 rate limits. Public lookup of a revoked NOMA identity returns 200 with a tombstone. Error bodies contain only a fixed error code and user-facing message, never internal stacks.

Public lookup cache TTL: 30 seconds. Management, recovery, credential downloads, and receipt use no-store. Restricted recovery sessions do not count as ordinary management authentication. Grant creation returns 202 when status is unpublished; receipt challenge/receive return 409 without consuming the token. There are no external service registration, OAuth client registration, or usage reporting APIs.

## 9. Operations, Retention, and Limits

- Public lookup: 60 requests/minute/IP. Photos: 120/minute/IP. Issuance preparation: five/hour/IP. Final issuance: three/hour/IP.
- Apply passkey/recovery failure limits to both IP and target identity. Ten failures in 15 minutes block that combination for 15 minutes; 30 failures in 15 minutes against an identity block the identity for 15 minutes.
- Credential renewal: 10/day/NOMA identity. Photo uploads: 10/hour/NOMA identity.
- Pseudonymize IPs using in-memory HMAC keys rotated by time window, use only for rate limiting, and delete within one hour. Never persist raw IPs, User-Agent, Referer, or external service addresses in logs.
- The small-scale v1 uses a single issuer replica for consistent limits. Record loss of rate-limit state on restart as an operational limitation.
- Disable ordinary access logs. Record only route templates, response codes, latency, and random request IDs. Do not log profile contents, recovery codes, signed tokens, query strings, or authentication headers.
- Retain internal error logs for seven days and per-identity management change audits for 30 days. Audit records contain only action type, time, and revision, not previous profile values or usage destinations.
- v1 does not store wallet presentation history at all. Wallet private keys and credentials reside only in IndexedDB.
- On NOMA revocation, remove the current profile immediately and clean up photos, management passkeys, recovery data, and sessions within 24 hours. Retain a minimal tombstone (noma_id, revision, status, issuance and revocation times) permanently.
- Retain revoked credential status until seven days after original expiration. Delete credential bytes and issuance records after that deadline. Retain old holder public keys until the last referencing credential is cleaned up, then remove them; this does not retain authentication secrets. Follow reference order during cleanup, removing sessions, challenges, and credentials first. Do not store separate historical profiles for active identities.
- Encrypt MySQL/object storage backups, create them daily, and retain them seven days. Ordinary profile/photo/new issuance recovery point objective (RPO): at most 24 hours; alert if the latest healthy backup is older. Target RPO 0 for successfully acknowledged security invalidations, requiring the separate records in Section 9.1. Replay those records before reopening after disaster recovery. Disclose that deletion from backups can be delayed until backup expiration.
- Do not claim to prevent all bulk collection from a public system. The initial release excludes CAPTCHA, real-world identity verification, and external tracking SDKs.

### 9.1 Security Invalidation Records and Disaster Recovery

Keep minimal records separate from the ordinary 30-day management audit to prevent backup restoration from reviving revoked authority. Write immutable objects to encrypted S3-compatible storage with a failure domain and write credentials separate from the operational DB and daily backups. Operational write credentials cannot overwrite or delete; retention policy changes require separate operational authority. A single development MinIO instance does not satisfy production independent retention requirements.

- Records contain only event_id, a monotonically increasing sequence, operation type, time, target IDs, and necessary invalidation data. Do not include profile contents, photos, IPs, usage destinations, private keys, session tokens, recovery codes, or recovery code hashes.
- Record minimal tombstone fields for NOMA revocation; credential_id, noma_id, list_id, slot_index, and original expiration for credential revocation; relevant IDs for holder key/passkey revocation; recovery_id for recovery code consumption; and kid for issuer key distrust. Record all previous authentication target IDs as one recovery batch. Do not record new authentication secrets.
- Retain NOMA tombstones and issuer key distrust permanently. Retain credential revocation through original expiration plus 14 days. Retain holder key, passkey, and recovery code invalidations for the longer of at least 45 days or the last referencing credential's expiration plus 14 days. These periods cover restoration from backups up to seven days old and credential cleanup. Disclose retention separately from ordinary audits/backups.
- External records consist of per-target payload objects and an event manifest binding their digests. Separate permanent and finite-retention targets so a tombstone does not cause all authentication identifiers in the same operation to be retained forever. Expired payload cleanup requires separate retention-management authority and leaves immutable cleanup attestations containing the target digest and expiry justification, plus interval checkpoints. Restoration distinguishes legitimately expired payloads from lost payloads, checking manifest sequence continuity and retained payload digests. Do not add target IDs or secrets to checkpoints or cleanup attestations.
- Profile changes, credential replacement, key replacement, passkey deletion, recovery, NOMA revocation, and issuer key distrust that invalidate authority commit business changes and `security_invalidation_outbox` in the same DB transaction. A single recording worker writes and verifies external objects in sequence order before marking recording complete. Retry by event_id; halt with an operational error if the same sequence has different contents.
- After confirming external object durability, write the latest checkpoint including the previous sequence and digest to independent storage. Success responses, new credential delivery, and publication of the change's status lists/key metadata require checkpoint confirmation. If the worker stops before updating the DB, confirm the same object/checkpoint on retry. Publication workers must not deploy DB snapshots containing unconfirmed changes.
- If external storage fails, do not roll back committed DB changes; return an operation identifier and 202. Immediately reject old authority in the operational DB, and block new authority/credential receipt until recording completes. Idempotent retries retrieve the existing operation. During recording delays, stop reissuing affected status lists/key metadata so external verifiers reject them under the 120-second freshness rule. Alert that the 30-second publication target is unmet during this failure.
- Bind retry idempotency keys to the target NOMA identity, operation type, and normalized request hash; reject different contents under the same key with 409. Authenticate polling with a random 32-byte token and store only its hash. The client generates the token before the initial request and sends it in a header so polling remains possible after response loss. Polling returns status only and grants no new authentication authority. Invalidate polling tokens 24 hours after completion and clean up completed outbox records after seven days. Never automatically delete incomplete operations.
- RPO 0 is not guaranteed if both the DB and independent store are lost. Unacknowledged operations may be missing after restoration; users must not treat pending operations as complete. Replay externally recorded operations regardless of response loss.

Restore with external access and status/key reissuance stopped: restore a healthy backup → confirm the independent store's latest checkpoint and sequence/digest continuity → replay retained invalidations → clean up and publish new status/key metadata → reopen service.

- Create tombstones from records for revoked NOMA identities missing from the backup. Apply revoked status slots even for missing credentials. Invalidate recorded keys, passkeys, and recovery codes present in the backup and prohibit reuse even if absent. Never reassign slots with retained revocations.
- If a recovery or key replacement event_id is absent from the restored DB, treat the new authentication commit as unconfirmed. Set the identity's internal `restore_locked_at` to block ordinary management, recovery, credential issuance, and receipt; guide the user to create a new identity. Public status retains the active/revoked structure. Ordinary APIs cannot clear this lock. Operators must not regenerate lost secrets or perform manual identity-based recovery. Compare recorded event_ids with external checkpoints to restore outbox recording status without duplicate recording.
- Invalidate all management/recovery sessions, challenges, issuance intent/result tokens, and receipt tokens during restoration. Do not resume old issuance operations without authentication.
- Publish revoked values for every slot in all identifiable old status lists and revoke remaining active credentials. Reject requests for list_ids absent from backups/records with 404/410; never create those lists automatically. New issuance uses new list_ids only. This prevents unknown post-backup credentials and slot allocations from becoming valid. Tell wallets that credentials need reissuance.
- Do not resume management, issuance, authentication, or status/key reissuance if the latest checkpoint is unavailable, records are missing/tampered with, or retention rules were violated. Operational records contain only restoration verification completion time, checkpoint, and result. No fixed recovery time objective (RTO) is promised yet; measure it in pre-launch recovery drills.

## 10. Screens, Accessibility, and Design Tokens

### 10.1 Screen Flow

- Home → input and preview → public information review → passkey/holder key/recovery setup → issuance processing → completion.
- Desktop issuance follows the selected concept: navigation on the left, inputs in the center, vertical card on the right.
- Mobile uses simple top navigation, a collapsible card preview, and inputs in a single column.
- My NOMA has profile, credential, and authentication/recovery sections.
- Public lookup accepts an exact noma_id only. No listings or name search.
- Wallet approval displays the service's validated domain, requested fields, selected identity, and approve/reject actions.
- Label management authentication and holder authentication as “NOMA management” and “External presentation approval” respectively.

### 10.2 States and Copy

The following English text is the baseline product copy for v1. Use English throughout the issuer application and wallet, including validation, consent, recovery, and accessibility text. NOMA targets a global audience; the original concept's Korean text does not determine the implementation language.

- Input: name required; birth year, photo, and email optional.
- Email help: “Fictional information; actual email deliverability is not checked.”
- Public review: “Anyone can look up your issued name, birth year, photo, and email using your NOMA ID.”
- Recovery notice: “Your recovery code is a secret that grants NOMA management access. Do not share it with your credential.”
- Unissued card ID: “Generated after issuance”.
- Presentation: “Submit your NOMA information to this service?”
- Credential states: valid / renewal required / expired / revoked.
- Implement separate states for input errors, processing, network failures/retries, authentication cancellation, conflicts, missing photos, recovery failures, and unavailable status checks.
- Block external presentation without a valid credential and guide users to issuance/renewal when they request it.

### 10.3 Tokens

| Token | Value |
| --- | --- |
| background | #101112 |
| surface | #191B1D |
| surface-raised | #24272A |
| divider | #4B5055 — decorative dividers |
| control-border | #727980 — meaningful UI boundaries such as inputs |
| text-primary | #F1F3F4 |
| text-secondary | #B4BAC0 |
| accent | #C8FF32 |
| accent-text | #101112 |
| danger | #FF8A8A |
| Body text | Pretendard Variable, 16px, line-height 1.5 |
| Technical text | IBM Plex Mono, 14px |
| Corners | Default 0px; inputs/buttons at most 2px |
| Spacing | 4/8/12/16/24/32/48/64px |
| Maximum content width | 1440px |
| breakpoint | Mobile <768px, tablet 768–1199px, desktop >=1200px |

Self-host fonts with their licenses. Metallic texture behind body text has at most 3% opacity. Gradients and neon glow are prohibited. Use accent colors for primary actions and selected states.

Use system sans-serif fallbacks for scripts not covered by the bundled body font. Keep technical identifiers in monospace; do not force arbitrary user names into a font that cannot display their script.

Target WCAG 2.2 AA. Check 4.5:1 contrast for normal text and 3:1 for large text and meaningful UI boundaries. Support keyboard operation, explicit labels, non-color state indicators, a 2px focus ring, recommended 44×44px touch targets, and reduced-motion. Guide focus to errors that need correction and associate server validation errors with their fields.

### 10.4 Language and International Formatting

- v1 ships English only, with document language `en` and left-to-right interface layout. Apply the same language to the issuer application, wallet, public lookup, developer documentation, page metadata, accessible names, and status/error messages. Do not show a language selector until additional translations are available.
- Keep interface strings in shared message catalogs or equivalent locale resources rather than embedding them in business logic. English is the fallback for future locales. Browser language does not automatically switch v1 copy to another language.
- Preserve Unicode names and emails under Section 3 rules. Do not transliterate, translate, or require ASCII-only profile values. Isolate user-supplied text from surrounding layout with automatic text direction so mixed-direction names do not reorder adjacent labels or IDs. This does not relax control-character validation.
- Format human-facing dates and numbers with an English locale. Use the browser's resolved time zone for displayed timestamps and show the time zone, including its UTC offset at that instant. Fall back to UTC if the zone is unavailable. Use month names rather than ambiguous numeric-only dates, and make the exact UTC ISO 8601 value available in details or a copy action.
- Keep API/credential timestamps, signature inputs, UUIDs, protocol numbers, and birth_year values independent of locale. A birth year is an integer, not a date subject to time-zone conversion. Use UTC for all expiry and freshness checks.
- Do not request country, nationality, or real-world location to choose a display language or time zone. Resolve display settings locally in the browser; do not add server profile fields or infer a user's identity from them.
- Later translations must cover complete flows, including errors, recovery warnings, approval details, and accessible text, before being offered. When adding languages, verify text expansion and right-to-left layouts where applicable; v1 only needs mixed-direction user content within its English layout.

## 11. Schema and Implementation Verification

The physical schema follows `schema.mysql.sql`. It is initial DDL for a new database, not something to apply indiscriminately to existing databases. DDL alone cannot handle deletion, authentication lifecycles, normalization, or signature verification; service logic and integration verification are required.

Implementation completion includes:

- Execute initial DDL on MySQL 8.4 and verify transactions, concurrent changes, and duplicate issuance.
- Reject tampered credentials, different holder keys/audiences, expired/reused nonces, and session substitution.
- Verify x509 chains, hosts, request signatures, and response encryption.
- Reject revoked and old credentials after renewal, key replacement, and recovery.
- Confirm that profile contents, tokens, usage destinations, and recovery secrets never reach server logs.
- Verify browser key storage, storage deletion, recovery, and desktop/mobile approval flows.
- Confirm interoperability through a separate external verifier demo following the public specification.
- Reject expired receipt tokens, different holder keys/credentials, concurrent reuse, and invalid postMessage origin/source/nonce. Verify receipt of the same credential after response loss or IndexedDB storage failure.
- Verify recovery without a passkey, rejection of ordinary management/downloads in restricted recovery sessions, exactly one concurrent completion per recovery code, and invalidation of old authentication methods.
- Verify success/publication blocking and retries on external invalidation storage failure, interruption immediately after commit, and interruption immediately after checkpointing. Restore a seven-day-old backup and reject reactivation of revoked identities, keys, passkeys, recovery codes, and all old credentials.
- Verify reopening prevention for missing/tampered records or unknown latest checkpoints, locking after loss of post-backup authentication methods, status list ID replacement, credential reissuance, and RPO/RTO recovery drill results.
- Verify English labels, validation errors, consent/recovery notices, accessible names, and page metadata across issuer and wallet flows. Check Unicode and mixed-direction names, multiple browser time zones and daylight-saving transitions, UTC fallback, and unchanged API/credential timestamps and expiry checks.

This document resolves product and technical choices needed before implementation. Actual domains, hosting providers, and deployment secrets are injected configuration, not unresolved product requirements.

## 12. Official Sources Consulted

- [Next.js 16](https://nextjs.org/blog/next-16)
- [Node.js Release Schedule](https://github.com/nodejs/Release/blob/main/README.md)
- [MySQL 8.4 LTS](https://dev.mysql.com/doc/refman/8.4/en/mysql-releases.html)
- [OpenID4VP 1.0 Final](https://openid.net/specs/openid-4-verifiable-presentations-1_0-final.html)
- [SD-JWT — RFC 9901](https://www.rfc-editor.org/rfc/rfc9901.html)
- [SD-JWT VC draft-19](https://datatracker.ietf.org/doc/html/draft-ietf-oauth-sd-jwt-vc-19)
- [Token Status List draft-21](https://datatracker.ietf.org/doc/html/draft-ietf-oauth-status-list-21)
- [W3C Web Cryptography API](https://www.w3.org/TR/WebCryptoAPI/)
- [WCAG 2.2](https://www.w3.org/TR/WCAG22/)
