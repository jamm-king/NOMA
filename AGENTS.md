# Agent Guidelines

These instructions apply to the entire repository. Follow the user's current task instructions when they override a repository workflow rule.

Read [REQUIREMENTS.md](REQUIREMENTS.md), [v1 Implementation Decisions](docs/V1-DECISIONS.md), and [CONTRIBUTING.md](CONTRIBUTING.md) before changing the relevant product behavior or workflow. The repository currently contains design documentation and initial DDL, not a runnable application.

## 1. Hexagonal Architecture

- Implement business behavior using hexagonal architecture: domain logic, application use cases, ports, and adapters.
- Keep domain logic independent of frameworks, UI, HTTP, databases, storage SDKs, and browser APIs. Application use cases depend on domain types and ports, not concrete adapters.
- Define ports for external capabilities needed by use cases. Implement database, object storage, cryptography, browser storage, and transport integration in adapters where applicable.
- Treat Next.js Route Handlers and UI event handlers as inbound adapters. Validate transport input, invoke use cases, and map results without embedding business rules in handlers or components.
- Wire concrete adapters at composition roots. Do not instantiate infrastructure dependencies inside domain classes or application use cases.
- Preserve the issuer/wallet origin and information boundaries defined in the decisions. Hexagonal architecture does not imply a shared issuer/wallet runtime or access to wallet private keys.
- Organize around product capabilities and responsibilities. Do not require a particular directory tree or create unused ports and abstractions merely to match a template.

## 2. Language and Conventions

- Write documentation, branch names, and commit messages in English. English is also the default and only shipped v1 UI language.
- Use Conventional Commits: `<type>(<optional scope>): <description>`. Examples: `docs(repo): add agent guidelines`, `feat(wallet): add credential receipt`, `fix(auth): reject expired challenges`.
- Use branch names `<type>/<short-kebab-case-description>`, such as `docs/repository-guide`, `feat/issuance-flow`, or `fix/receipt-token-expiry`. Use the types documented in CONTRIBUTING.md.
- Write documents with descriptive titles, consistent terminology, clear Markdown, and the existing filename conventions. Conventional Commits syntax applies to commit messages; it is not a required prefix for every document title or paragraph. Preserve standard filenames such as `README.md` and `AGENTS.md`.
- Keep requirements, implementation decisions, schema, and repository guides consistent when their contracts change. Distinguish planned behavior from implemented and verified behavior.

## 3. Class-Level Unit Tests

- Add or update unit tests for every production class introduced or behaviorally changed. Give each class an identifiable test suite covering its public behavior.
- Test successful behavior, relevant boundary conditions, and meaningful failure paths. Assert observable results and invariants rather than private implementation details.
- Keep domain and application unit tests independent of real network connections, databases, object stores, and browser storage. Supply fakes or mocks through ports; control time and randomness where needed.
- Test production functions and modules with equivalent behavior-focused unit tests when they do not use classes. Do not turn React components or pure functions into classes solely for testing.
- Class-level unit tests do not replace integration tests for SQL constraints, transactions, concurrency, cryptographic interoperability, or browser behavior. Follow the verification criteria in the decisions for those boundaries.
- Run checks appropriate to the change and report their actual results. If a required tool or runnable implementation is unavailable, state what was not verified. Documentation-only changes require document validation, not artificial class tests.

## 4. Branch Selection

- Inspect the current branch, working tree, and relevant local/remote history before changing branches.
- Never perform implementation or documentation work directly on `main`. Checkout of `main` solely to update it before creating a task branch is allowed.
- When continuing work belonging to an existing task branch, use that branch even if the working tree is clean. Do not update `main` or create another branch merely because all prior changes were committed.
- For a genuinely new, unrelated task with a clean working tree, update `main` from `origin/main` using fast-forward-only synchronization, then create a branch using the naming convention above.
- If the relevant existing task branch is not checked out, switch to it only when doing so preserves current changes. If branches diverge or selecting a branch would risk unrelated work, inspect the situation and ask the user before resolving it destructively.
- If uncommitted changes exist, preserve them and determine whether they belong to the current task. Do not automatically stash, discard, commit unrelated changes, or move them to another branch to obtain a clean tree.
- Never force-reset `main` or erase local commits to make synchronization succeed.

## 5. Commits and Push Approval

- Commits for completed, verified work within the user's requested scope do not require prior approval.
- Review the diff and stage only files belonging to the task. Use focused Conventional Commits and leave unrelated user changes untouched.
- Every push requires explicit user approval before execution. State the target remote, branch, and commits or changes to be pushed so the approval is concrete.
- Approval to commit is not approval to push. Never infer push approval from a request to implement, edit documentation, create a branch, or finish a task. Do not use another tool to publish commits without the same approval.
- Do not merge into `main`, rewrite published history, or force-push without explicit authorization for that action.
- Report the branch, commit identifier, checks performed, and whether a push occurred. Do not claim a successful commit, push, or check without confirming the result.

## 6. Product and Security Boundaries

- Follow the existing fixed data schema, Unicode handling, English UI policy, and UTC protocol timestamps. Do not add arbitrary profile fields or real-world identity requirements.
- Keep management passkeys separate from holder keys. Never place private keys, recovery codes, authentication tokens, or external presentation histories in source control or logs.
- Preserve publication gates, atomic recovery and token consumption, and invalidation replay requirements. Document schema/API changes and the migration or verification they require.
- Do not describe documentation review or static DDL inspection as proof of working authentication, deployment, or standards interoperability.
