# Project conf template

Written to `.gravity/project.conf` by `/gravity:setup`, which proves it before use. The file is committed.

Each command takes a tag after `|`: `external` (a compiler, a real service), `project` (the repo's lint, types and build) or `suite`
(tests the agent can edit). With no real surface, write `run = none | <reason>`. A section with nothing to say stays, empty.

```ini
[commands]
install = <pnpm install --frozen-lockfile>
test    = <pnpm test> | suite
lint    = <pnpm lint> | project
types   = <pnpm typecheck> | external
build   = <pnpm build> | external
run     = .gravity/verify.sh | external

[paths]
specs = docs/specs
plans = docs/plans

[risk]
paths = <src/auth/** src/payments/** migrations/**>
deny  = <npm publish, supabase db push>

[bar]
paths = <.github/workflows/** jest.config.* eslint.config.* tsconfig.json>

[guidelines]
<backend> = <docs/guidelines/backend.md> | <when touching controllers, services or data access>

[baseline]
known_failing = .gravity/known-failing.txt
```
