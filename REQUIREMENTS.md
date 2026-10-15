# NOMA Requirements and Design Guidelines

- Written: 2026-10-15 (Asia/Seoul)
- Status: Initial release requirements and implementation baseline finalized
- Project: NOMA
- Database: MySQL
- Selected design: Second concept — Dark Terminal

This document defines NOMA's product requirements. Outstanding implementation choices are finalized in the [v1 Implementation Decisions](docs/V1-DECISIONS.md), which governs technical details, authentication, lifecycles, APIs, and operations. The physical schema is defined in the [Initial MySQL DDL](docs/schema.mysql.sql). This does not mean implementation, deployment, or standards interoperability has been verified.

## 1. Project Purpose

NOMA is an independent system for creating, issuing, and managing fictional personal information without requiring a real-world identity. Users create fictional identities and receive unique registration numbers. External systems can use that information and those identifiers for their own purposes.

The fictional identity system itself is the focus of this project. It is an experimental concept exploring how users use issued information and what external developers build on top of it.

NOMA targets users and developers worldwide. English is the default product language; v1 ships English UI and documentation rather than assuming a Korean audience. Interface language does not restrict the scripts used in user profile information.

A social network is an example application, not NOMA's core product or a required component. Signing up for an external service with NOMA information is another example use case.

## 2. Core Principles

### 2.1 Independence of the Issuing System

- NOMA must function without knowing that external services exist.
- External services do not need to register with NOMA or obtain integration approval.
- Do not issue service-specific IDs. External services use the common `noma_id`.
- The issuing system does not maintain external service lists, signup records, usage destinations, or presentation and approval histories.
- Publish integration specifications and verification methods to enable external use.
- Presentations to external services take place between the user's wallet and the external service.

A wallet checking an external service's identity is distinct from the issuing system managing external services. The wallet checks the presentation request's intended recipient without sending that information to the issuer server.

### 2.2 Fictional Information and Anonymity

- Issuance must not require real-world identity information such as a legal name, real email address, or real phone number.
- The name, birth year, photo, and email are fictional information chosen by the user.
- An email address does not need to exist or receive messages.
- NOMA does not guarantee that fictional information describes real-world facts.
- A fictional birth year cannot prove a user's actual age.
- Avoiding collection of real-world identity information does not make all activity untraceable.
- Publishing the same `noma_id` in multiple places can allow external parties to correlate activity. Do not claim absolute anonymity or untraceability.

### 2.3 Structured Data

- Every fictional identity follows the same fixed data structure.
- Users cannot add arbitrary fields or extensible attributes.
- Do not provide messenger fields.
- Biographies, interests, and arbitrary URLs are also outside the current personal information structure.
- Validate structure and data types, not the real-world truth of the contents.
- Reject undefined input fields.

## 3. Public Data Structure

With the project name finalized, the temporary `persona_id` is renamed to `noma_id`. Use this name consistently in APIs, the database, and credential business data.

### 3.1 System Metadata

| Field | Type | Rules |
| --- | --- | --- |
| `noma_id` | UUID | Random unique registration number; immutable and never reused |
| `schema_version` | String | Data specification version; initially `1.0` |
| `revision` | Positive integer | Starts at 1; increments when public personal information changes |
| `status` | Enumerated string | `active`, `revoked` |
| `issued_at` | Date/time | Initial issuance time; immutable |
| `updated_at` | Date/time | Most recent public information change |

External responses express date/time values as UTC ISO 8601 strings. Authentication key and credential lifecycles are designed separately from the personal information `revision`.

### 3.2 `profile`

| Field | Type | Required | Rules |
| --- | --- | --- | --- |
| `name` | String | Yes | 1–50 characters after trimming leading and trailing whitespace |
| `birth_year` | Integer or `null` | No | 1–9999; does not prove actual age |
| `photo_id` | UUID or `null` | No | Reference to an uploaded photo asset |
| `email` | String or `null` | No | Up to 254 characters; no format, existence, or deliverability validation |

- Use `null` for unset optional fields.
- Public responses for active identities always include all four fields.
- Normalize empty strings in optional fields to `null`.
- Duplicate names and emails are allowed. Only `noma_id` is unique.
- Treat strings as plain text; do not execute HTML.
- Photos reference system asset IDs rather than arbitrary external URLs.
- Trim leading and trailing whitespace, normalize strings to NFC, and validate length by Unicode code point count.

### 3.3 Example Public Response

```json
{
  "schema_version": "1.0",
  "noma_id": "788891a4-c11a-46a0-b9cb-aab8ee3f776c",
  "revision": 1,
  "status": "active",
  "issued_at": "2026-10-15T05:00:00Z",
  "updated_at": "2026-10-15T05:00:00Z",
  "profile": {
    "name": "Haru",
    "birth_year": 2001,
    "photo_id": null,
    "email": "haru@example.invalid"
  }
}
```

Never reuse revoked registration numbers. Preserve the top-level public response structure, but return `status` as `revoked` and `profile` as `null`. Remove current personal information immediately upon revocation and clean up related assets, including photos, within 24 hours. Retain a minimal tombstone permanently; follow the v1 decisions for detailed retention rules.

## 4. MySQL Storage Structure

Use MySQL without JSON columns for arbitrary extensibility. Model business fields and authentication metadata as explicit columns and relationships. JSON in an API or credential does not imply JSON storage in the database.

The following are logical data categories. Physical tables and constraints are defined in `docs/schema.mysql.sql`. Use MySQL 8.4 LTS, InnoDB, utf8mb4, and UTC.

| Data category | Contents |
| --- | --- |
| Fictional personal information | `noma_id`, four profile fields, schema, revision, status, and timestamps |
| Photo assets | Photo IDs, storage locations, formats, sizes, and related metadata |
| Management authentication | Management credentials and recovery code verification hashes |
| Holder public keys | Public keys linked to NOMA identities, key status, and lifecycles |
| Credential issuance records | Credential identifiers, profile revisions, issuance, expiration, and revocation data |

- Store photo files separately; keep references in MySQL.
- Never store holder private keys on the issuer server or in MySQL.
- Protect issuer signing private keys on the server; never store plaintext keys in ordinary business tables.
- Do not create external service registration or service-specific ID mapping tables.
- Store signed SD-JWT serialization bytes in a credential table BLOB. Do not use extensible JSON columns for public profile information. Delete credential bytes seven days after expiration.

## 5. Purpose of Credentials

A credential establishes the following:

> NOMA issued an association between fictional personal information and a holder public key at a specific time, and the signed contents have not been altered.

| Verification target | Can the credential alone establish it? |
| --- | --- |
| Issuance by NOMA | Yes, when verified with a trusted NOMA public key |
| Integrity of signed contents | Yes |
| Real-world truth of the information | Not guaranteed |
| Email deliverability | Not guaranteed |
| Current validity and latest revision | Requires separate status and revision checks |
| Presenter's control of the bound private key | Requires separate proof of possession |

Credential files can be copied. Possession of a file alone must not establish ownership for signup or login. Proof of possession also does not identify a real-world person or prove that a person has only one NOMA identity.

Credentials describe information at a point in time and are immutable after issuance. Issue a credential for the new revision when personal information changes. A valid signature on an old credential is distinct from current validity.

Photo assets are never overwritten; replacements receive new IDs. Bind the SHA-256 digest of the stored WebP bytes through a separate fixed credential claim. Preserve the existing `profile` structure.

## 6. OpenID4VP-Based Proof of Possession

### 6.1 Selected Approach

Design credential presentations and proof of possession around OpenID for Verifiable Presentations 1.0. Follow its request, response, and verification procedures rather than inventing a custom cryptographic protocol.

OpenID4VP is a presentation protocol. It does not automatically determine the credential format, initial issuance protocol, or complete key recovery policy.

### 6.2 Roles

| Component | Responsibilities |
| --- | --- |
| NOMA issuing system | Manage profiles, sign and issue credentials, provide public keys and status information |
| User wallet | Generate and store private keys, store credentials, validate requests, obtain approval, and generate proof of possession |
| External verifier | Request information, verify issuer authenticity and proof of possession, and handle its own business logic |

The wallet communicates directly with external services. It may share NOMA branding, but its responsibilities and data flows are separate from the issuer server.

### 6.3 Presentation Flow

1. Generate a holder key pair on the user's device.
2. NOMA issues a credential binding the user's public key to the profile.
3. An external service creates a presentation request with required information and an unpredictable one-time `nonce`.
4. The wallet validates the request source and response destination, then displays the selected NOMA identity and requested fields.
5. With user approval, the wallet uses the private key to generate proof bound to that request.
6. The wallet sends the credential and proof directly to the external service.
7. The external service verifies the issuer signature, holder proof, audience, nonce, time, and session binding.
8. The verifier prevents reuse of the successful nonce and independently completes signup or other business actions.

The NOMA issuer server does not receive or store external service names, presentation requests, user approvals, or signup events. Never disclose the user's private key to an external service.

### 6.4 v1 Technical Baseline

- External verifier identification: `x509_san_dns`. The wallet verifies the request signature and certificate trust chain. NOMA preregistration is not required.
- External services must have a certificate and key suitable for request signing. Do not assume every HTTPS certificate is suitable.
- Credentials: SD-JWT RFC 9901 and SD-JWT VC draft-19; format `dc+sd-jwt`.
- Status: Token Status List draft-21. Do not describe draft specifications as final standards.
- Bind the holder public key in the fixed `cnf.jwk` field. Use ES256 for issuer and holder proof signatures.
- Place the public data object under the fixed `noma` claim. Support selective disclosure of the four `profile` fields without changing public lookup visibility.
- Use DCQL and require holder binding. Responses use `direct_post.jwt` with ECDH-ES/A256GCM encryption.
- Requests requiring ownership verification, including signup, must require cryptographic proof of possession.
- External verifiers obtain NOMA public keys through a trusted distribution path. Never blindly trust a key supplied by a credential.
- Initial issuance uses NOMA-specific `/api/v1` endpoints. v1 does not implement OpenID4VCI.
- Follow the v1 decisions for detailed certificate, request, response, key, and session validation conditions.

### 6.5 Status Checks and Key Management

- Allow external parties to verify issuer authenticity and proof of possession independently.
- Check current revision, revocation, and key replacement through separate status information.
- Distribute signed Token Status Lists in batches for verifier caching to reduce individual presentation traces.
- Distinguish signature validity, credential expiration, current revocation status, and profile freshness.
- Recovery and key replacement must also update the validity of old keys and credentials.
- Credentials are valid for 30 days. Profile changes, renewal, key replacement, recovery, and NOMA revocation revoke existing credentials. Keep only one valid credential per NOMA identity.
- Allow status information at most 120 seconds old. Reject signup and authentication when fresh status cannot be confirmed.
- Recovery uses a 256-bit single-use code to register a new management passkey and holder key. Revoke previous authentication methods, holder keys, and credentials.
- When a passkey is lost, recovery code verification replaces recent passkey reauthentication. A restricted recovery session permits only replacement setup and recovery completion, not ordinary management or credential downloads. Consume the recovery code atomically at completion.

Passkeys/WebAuthn authenticate access to NOMA management. They are distinct from using a common private key to sign presentations to arbitrary external services. Do not confuse management keys with holder keys.

## 7. Web Application Screens

The web application is a digital issuing office for creating and managing fictional identities. The following screens are in v1 scope. Use Next.js for the management application and an installable PWA on a separate origin for the wallet.

| Screen | Main features |
| --- | --- |
| Home | Service introduction, start issuance, open existing NOMA management |
| Issuance | Enter four profile fields, preview the card, explain public visibility |
| Issuance complete | Completed card, copy registration number, receive credential, open management |
| My NOMA | Edit profile, inspect revision, manage credentials, authentication, recovery, and revocation |
| Public lookup | Retrieve current public information and status by exact `noma_id` |
| Developer documentation | Data specification, lookup API, public keys, OpenID4VP verification and integration examples |
| Wallet presentation approval | Review request source, selected identity, and requested fields; approve or reject |

### 7.1 Issuance Flow

Start issuance → enter profile → review public information → configure management authentication and recovery → finalize issuance → completion screen.

- Never display a registration number as issued before issuance actually completes.
- Clearly explain before final issuance that the entered information is publicly retrievable by registration number.
- Do not treat the fictional email as a recovery address.
- Registration numbers can be shared, but private keys and recovery codes must never appear on cards or in public responses.
- Prevent duplicate or partial issuance with issuance intents, idempotency keys, DB transactions, and a status publication outbox. Never return credentials before commit and publication complete.
- Distinguish server issuance completion from wallet storage completion. The management screen sends target IDs and a five-minute single-use receipt token to the validated wallet window. The wallet signs a challenge with the bound holder key and receives the credential directly. After a lost response or storage failure, retry receipt of the same credential with a new token rather than reissuing it. Follow Section 6.1 of the v1 decisions for authentication, communication, and cleanup details.

### 7.2 Management and Lookup Screens

- Display differences between the current profile revision and the revision in a credential.
- Explain revocation consequences and obtain final confirmation.
- Public lookup accepts only an exact registration number.
- The first release does not provide name search or a list of all registered identities.
- v1 does not store wallet presentation history.
- The wallet is a PWA on a separate origin. Store private keys as non-extractable keys in browser IndexedDB. Cross-device holder key copying and synchronization are outside v1 scope.

### 7.3 Language and International Use

- English is the default and the only shipped UI language in v1 for the issuer application, wallet, public lookup, and developer documentation. Use English labels, help, validation errors, consent text, recovery guidance, and accessibility text.
- Keep UI messages separate from business logic so translations can be added later. v1 does not display a language selector for unavailable translations or automatically switch to Korean based on browser settings.
- Continue accepting Unicode profile values under the existing normalization and length rules. Do not translate user-entered names or require an English name, country, nationality, phone number, or real-world location.
- Store and exchange timestamps in UTC. Display human-facing dates in English using the browser's time zone, label the time zone, and offer the exact UTC timestamp for technical inspection. Do not default product displays to Asia/Seoul or show ambiguous numeric-only dates.
- Follow Section 10.4 of the v1 decisions for text direction, formatting, and future localization boundaries.

## 8. Selected Design Concept

The requested direction is cyber, steel, and metaverse, without stereotypical AI gradients. The second of three generated concepts was selected.

The visual reference is stored at `docs/assets/noma-dark-terminal-concept.png`. It is a visual guide and does not override data constraints or behavioral specifications.

The original concept contains Korean text. Preserve it as a design reference, but implement all product copy in English according to the language policy and the v1 decisions.

| Element | Guideline |
| --- | --- |
| Overall impression | A fictional identity system precisely engraved into black steel |
| Background | Near-black charcoal with subtle metallic texture |
| Text | Bright silver with gray supporting text |
| Accent | Lime, limited to primary buttons and selected states |
| Structure | Aligned grid, numbered inputs, thin dividers |
| Shape | Angular corners and restrained borders |
| Typography | Readable sans-serif; monospace for IDs and technical information |
| Card | Vertical metal identity card emphasizing the photo and registration number |

- Exclude gradients and neon glow effects.
- Metallic texture must not reduce text or input readability.
- Express the metaverse theme through avatars and fictional identity cards.
- The reference avatar is illustrative; do not require a particular photo style or avatar.
- Replace the reference's email description with wording explaining that the information is fictional and deliverability is not checked.
- Copy, file restrictions, and decorative details in the concept image are not finalized requirements.
- Follow the design tokens in Section 10 of the v1 decisions for colors, fonts, spacing, responsive layout, and accessibility targets.

## 9. Privacy and Operational Design

- Do not collect real-world personal information unnecessary for issuance.
- Accept JPEG, PNG, and static WebP images up to 5 MiB. Re-encode them as square WebP images and remove metadata such as location data.
- Never log authentication secrets, recovery codes, or unnecessary profile contents.
- Do not send wallet presentation flows or usage destinations to issuer analytics or logs.
- Public lookup, key distribution, and status distribution can generate access records. Do not make the excessive technical claim that all external usage is unknowable.
- Default retention: error logs seven days, minimal management audit 30 days, encrypted backups seven days. Do not persist raw IP addresses, User-Agent, Referer, personal information, authentication secrets, or usage destinations in logs.
- Retain security invalidation records separately from ordinary audits in encrypted storage independent of the operational DB and backups. Confirm external recording before success responses and related status publication. Retain NOMA tombstones and issuer key distrust records permanently; retain other minimal invalidation identifiers for the periods in Section 9.1 of the v1 decisions. Do not record profile contents, authentication secrets, or usage destinations.
- The ordinary data recovery point objective is at most 24 hours; the target data loss for successfully acknowledged security invalidations is zero. Simultaneous loss of the independent store is outside that guarantee. During restoration, replay invalidations, invalidate all sessions, temporary tokens, and existing credentials, and publish new status lists. Do not reopen service without confirming record completeness. Lock identities whose new authentication methods were lost after the backup rather than restoring old authority.
- Apply the v1 issuance and lookup limits, file decoding checks, deletion rules, and status distribution policy.

## 10. Implementation Decisions and Completion Criteria

The previous 11 unresolved items are addressed in `docs/V1-DECISIONS.md`: frameworks, deployment, DB version, UUIDs, authentication, recovery, multiple identities, wallet, credential specifications and lifecycle, issuance APIs, photos, physical DDL, screens, accessibility, and operations.

- Physical DDL: `docs/schema.mysql.sql`.
- Inject production domains, provider accounts, deployment secrets, and security patch versions as deployment configuration.
- Implementation completion requires MySQL 8.4 DDL execution, issuance and recovery transactions, key storage, standard requests and responses, and an external verification demo.
- Verify wallet receipt expiration, replay and target mismatch rejection, retry after storage failure, restricted recovery permissions and concurrent consumption, external invalidation recording failures, backup restoration, and reopening prevention when records are missing. Recovery drills must check RPO compliance and measure actual recovery time.
- Verify English copy across all screens and error/approval flows, Unicode and mixed-direction profile display, and correctly labeled date/time formatting across time zones without changing UTC API values.
- Do not describe the current documentation and DDL as an implemented, deployed, or verified service.

## 11. Reference Specifications

- [OpenID for Verifiable Presentations 1.0 — Final](https://openid.net/specs/openid-4-verifiable-presentations-1_0-final.html)
- [OpenID4VP Verifier Identification](https://openid.net/specs/openid-4-verifiable-presentations-1_0-final.html#section-5.9.3)
- [OpenID4VP SD-JWT VC Processing](https://openid.net/specs/openid-4-verifiable-presentations-1_0-final.html#appendix-B.3)
- [JWS — RFC 7515](https://www.rfc-editor.org/rfc/rfc7515)
- [EdDSA — RFC 8032](https://www.rfc-editor.org/rfc/rfc8032) — Reference for a discussed signature method, not confirmation of algorithm adoption.
- [WebAuthn Level 2](https://www.w3.org/TR/webauthn-2/) — Reference for distinguishing management authentication from external proof of possession.
