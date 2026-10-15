# NOMA

An independent system for creating, issuing, and managing fictional personal information without requiring a real-world identity. Users create fictional identities with unique registration numbers (`noma_id`). External services can use the public specifications to look up information or verify credentials and proof of possession.

NOMA targets a global audience. English is the default and the only shipped UI language in v1 across the issuer application, wallet, and developer documentation. Profile names continue to support Unicode; an English interface does not restrict users to English names.

## Current Status

**The v1 requirements and implementation design are documented.** This repository currently contains documentation, an initial MySQL DDL, and a design reference image. Application code, installation scripts, and a runnable development environment are not yet available. DDL execution, deployment, and standards interoperability have not been verified.

## Documentation

| Document | Contents |
| --- | --- |
| [Requirements and Design Guidelines](REQUIREMENTS.md) | Product purpose, public data structure, issuance and management flows, design, and scope |
| [v1 Implementation Decisions](docs/V1-DECISIONS.md) | Technology choices, authentication and recovery, credentials and presentations, APIs, operations and restoration, completion criteria |
| [Initial MySQL DDL](docs/schema.mysql.sql) | Tables, relationships, constraints, and invariants enforced by service logic |
| [Dark Terminal Design Concept](docs/assets/noma-dark-terminal-concept.png) | Visual reference for the selected design |
| [Contributing and Repository Workflow](CONTRIBUTING.md) | Branch and commit conventions, documentation changes, and validation |
| [Agent Guidelines](AGENTS.md) | Hexagonal architecture, class-level tests, branch reuse, and commit/push authorization |

Start with the requirements, then read the decisions and DDL together for implementation details. Product behavior follows the documentation; example copy and decoration in the concept image do not replace requirements. Resolve inconsistencies between documents as part of any change.

## Core Principles

- Public profiles have a fixed structure: name, birth year, photo, and email. Name is required; the other fields are optional. Their real-world truth is not guaranteed.
- Anyone can retrieve issued information using an exact `noma_id`. Selective disclosure credentials do not make public lookup private.
- Management passkeys and holder keys for external presentations are separate. Possessing a credential file alone does not establish ownership.
- Wallets communicate directly with external verifiers. The issuing system does not maintain external service registrations, usage destinations, or presentation histories.
- Reusing an ID across services can allow activity correlation. NOMA does not guarantee absolute anonymity, proof of actual age, or one identity per person.
- Social networks, name search, complete identity listings, and arbitrary profile fields are outside v1 scope.

## Planned Architecture

| Component | Responsibilities | v1 technology choice |
| --- | --- | --- |
| Issuance and management application | Profile management, passkey authentication, issuance APIs, public lookup | Next.js 16, TypeScript, Node.js 24 LTS |
| User wallet | Holder key generation and storage, credential storage, presentation approval | React + Vite PWA on a separate origin |
| Database | Fixed schema and authentication/credential metadata | MySQL 8.4 LTS, mysql2 |
| Photo storage | Re-encoded photo assets | S3-compatible storage; MinIO for development |
| Deployment | HTTPS and container execution | Linux, Docker Compose, Caddy |

Pinned credential and presentation specifications and verification conditions follow [Section 5 of the decisions](docs/V1-DECISIONS.md#5-credentials-and-openid4vp-profile). This table describes implementation plans, not installed or running components.

## Repository Structure

```text
.
├── README.md
├── CONTRIBUTING.md
├── AGENTS.md
├── REQUIREMENTS.md
└── docs/
    ├── V1-DECISIONS.md
    ├── schema.mysql.sql
    └── assets/
        └── noma-dark-terminal-concept.png
```

## Starting Implementation

1. Set up the issuer application, separate wallet, and development infrastructure from the decisions, and pin dependency versions.
2. Validate the initial DDL as a migration against an empty development database. Do not apply it unchanged to an existing database.
3. Implement issuance, wallet receipt, management, recovery, and status publication; verify failures, concurrent requests, and retries.
4. Meet the [implementation completion criteria](docs/V1-DECISIONS.md#11-schema-and-implementation-verification), including an external verification demo and backup recovery drills.

Add run commands and environment variable documentation once the development environment exists. Never commit private keys, recovery codes, production tokens, or other secrets.
