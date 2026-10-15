# Contributing and Repository Workflow

NOMA is currently at the requirements and implementation design stage. Documentation changes must not imply that implementation, execution, or verification is complete.

Automated contributors also follow [AGENTS.md](AGENTS.md) for architecture, class-level tests, branch selection, and commit/push authorization.

## Branches

Continue related work on its existing task branch even when the working tree is clean. A clean working tree alone is not a reason to create a new branch. For a new, unrelated task with no uncommitted changes, update `main` using fast-forward-only synchronization and create a new task branch. Do not work directly on `main`; checking it out to update it is allowed. Preserve unrelated uncommitted changes rather than automatically stashing or discarding them. Use lowercase English words and hyphens in branch names.

| Prefix | Purpose | Example |
| --- | --- | --- |
| `docs/` | Documentation and design explanations | `docs/repository-guide` |
| `feat/` | New functionality | `feat/issuance-flow` |
| `fix/` | Bug fixes | `fix/receipt-token-expiry` |
| `chore/` | Tools, configuration, and maintenance | `chore/dev-environment` |

Example workflow for a new, unrelated documentation task with a clean working tree:

```sh
git switch main
git pull --ff-only origin main
git switch -c docs/your-topic
```

## Commits

Use Conventional Commits to describe the purpose of a change. Branch prefixes are a repository convention applied separately from the commit format.

```text
<type>(<optional scope>): <description>
```

- `docs`: Documentation and explanatory changes
- `feat`: New functionality
- `fix`: Bug fixes
- `refactor`: Structural changes that preserve behavior
- `test`: Verification code changes
- `chore`: Tools, configuration, and maintenance

Commits within the requested task scope do not require prior user approval. Review and stage only task-related changes after appropriate verification. Every push requires separate, explicit user approval for the intended remote, branch, and changes.

Examples:

```text
docs(repo): add repository overview and contribution guide
docs(auth): clarify recovery session permissions
feat(wallet): add credential receipt flow
```

For breaking changes, add `!` after the type/scope or describe the impact in a `BREAKING CHANGE:` commit body. When changing the actual DDL or API contract, document the impact and whether a migration is required. Keep unrelated changes out of documentation commits.

## Documentation Changes

- Update [REQUIREMENTS.md](REQUIREMENTS.md) for product purpose, public data, and screen scope.
- Update the [v1 Implementation Decisions](docs/V1-DECISIONS.md) for authentication, APIs, lifecycles, and operational policy.
- For storage changes, check the [Initial DDL](docs/schema.mysql.sql) and the decisions together. State conditions not enforced by DDL as service invariants.
- Update the [README](README.md) when document locations, implementation status, or getting-started instructions change.
- Write documentation and v1 product copy in English. Follow Section 10.4 of the decisions for language resources, Unicode content, and international date/time formatting; do not reintroduce a Korean-default UI assumption.
- Distinguish specification versions and draft status. Check official sources for new or changed external technical claims.
- Never put authentication secrets, recovery files, real user information, or production configuration values in documentation examples or images.

## Review and Validation

For documentation-only changes, check the following:

- Are relative links, heading anchors, and image paths valid?
- Do requirements, decisions, and DDL agree on fields, authentication conditions, and retention periods?
- Do code blocks and tables display correctly?
- Are plans distinguished from verification actually performed?
- Are unrelated files and secrets excluded from the change?

Use these commands to inspect changes:

```sh
git diff --check
git diff --stat
git diff
git status --short
```

When DDL or service behavior changes, documentation review alone does not complete verification. Record actual MySQL execution and relevant functional verification results, and identify checks that were not performed. Follow [Section 11 of the decisions](docs/V1-DECISIONS.md#11-schema-and-implementation-verification) for full completion criteria.

## Pushing and Describing Changes

Explicitly stage reviewed files and commit using Conventional Commits. Push the working branch only after explicit user approval. Committing or completing a task does not grant permission to push.

```sh
git add README.md CONTRIBUTING.md
git commit -m "docs(repo): add repository overview and contribution guide"
# Run only after explicit user approval of the push:
git push -u origin docs/your-topic
```

Pull Requests should describe the purpose, final changes, verification results, and unverified items. Merge into `main` after review.
