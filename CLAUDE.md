# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

Dai is a reusable Phoenix library — an AI-powered natural-language data dashboard. Host apps pull it in as a git dependency, configure their Repo and schema contexts, mount the dashboard at a route, and users can ask questions in plain English to get charts, metrics, and tables.

The library also runs standalone with a SaaS analytics demo dataset for development and testing.

## Commands

| Task | Command |
|---|---|
| Setup (deps + DB + assets) | `mix setup` |
| Dev server (kills stale port, loads .env) | `mix dev` |
| Dev server (standard) | `mix phx.server` or `iex -S mix phx.server` |
| Run all tests | `mix test` |
| Run single test file | `mix test test/path/file_test.exs` |
| Run previously failed tests | `mix test --failed` |
| Format code | `mix format` |
| Precommit checks (compile warnings + unused deps + format + test) | `mix precommit` |
| Reset database | `mix ecto.reset` |
| Show schema context (debug) | `mix gen_schema_context` |

`mix precommit` runs in the `:test` env (configured in `cli/preferred_envs`). Always run it before finalizing changes.

## Architecture

### Library core (`lib/dai/`)

All library modules live under the `Dai.*` namespace (not `DaiWeb.*`). The library is self-contained — it ships its own layouts, icons, and components without depending on the host app's CoreComponents.

### Key modules

- `Dai.Config` — centralized config reader; all modules read `:dai` app env through this
- `Dai.SchemaContext` — discovers Ecto schemas at boot via `:persistent_term`; filters by `schema_contexts` config
- `Dai.AI.QueryPipeline` — orchestrates: Client -> PlanValidator -> SqlExecutor -> ResultAssembler
- `Dai.AI.Client` — sends prompts to Claude Messages API via Req
- `Dai.AI.PlanValidator` — SQL keyword blocklist + LIMIT enforcement
- `Dai.AI.SqlExecutor` — raw query via `Ecto.Adapters.SQL.query/3`, normalizes Postgrex types
- `Dai.AI.ResultAssembler` — builds `%Dai.AI.Result{}` structs
- `Dai.AI.Component` — single source of truth for component types and their limits
- `Dai.AI.SystemPrompt` — builds the Claude prompt with schema context + rules + examples
- `Dai.DashboardLive` — main LiveView with async query execution and streaming result grid
- `Dai.DashboardComponents` — function components for each card type (KPI, chart, table, error, clarification)
- `Dai.Icons` — self-contained SVG icon components (no dependency on host's heroicons)
- `Dai.Layouts` — minimal dashboard layout (nav bar wrapper)
- `Dai.Router` — `dai_dashboard/2` macro for host app routers

### Standalone scaffold (`lib/dai_web/`)

When running standalone (not as a dependency), the DaiWeb scaffold provides the Phoenix endpoint, router, and standard controllers. The router uses `dai_dashboard "/"` to mount the dashboard.

### Demo data (`lib/dai/demo/`)

Sample Ecto schemas under `Dai.Demo.Analytics` (Plan, User, Subscription, Invoice, Event, Feature) with seed data. These are only visible in standalone mode because the standalone config sets `schema_contexts: [Dai.Demo.Analytics]`. Host apps configure their own namespaces.

### Pipeline flow

```
User prompt + SchemaContext.get()
  |> Dai.AI.Client.generate_plan/2        (Claude API -> JSON plan)
  |> Dai.AI.PlanValidator.validate/1       (blocklist + LIMIT)
  |> Dai.AI.SqlExecutor.execute/1          (raw SQL -> normalized rows)
  |> Dai.AI.ResultAssembler.assemble/3     (plan + rows -> %Result{})
```

Clarification plans (`needs_clarification: true`) are handled once at the pipeline level, not in individual steps.

### Assets

- **Tailwind v4 + DaisyUI 5** — no `tailwind.config.js`; uses `@import "tailwindcss"` syntax in `assets/css/app.css`
- **DaisyUI themes** — two themes configured in `app.css`: `light` (default) and `dark` (prefers-dark)
- **Charts** — rendered by `live_charts` hex package (ApexCharts); no custom JS hooks needed
- **No npm dependencies** — Chart.js was replaced by live_charts which ships pre-built JS via hex
- **Colocated hooks** — `app.js` imports hooks from `phoenix-colocated/dai` and passes them to `LiveSocket`
- **No external script/link tags in templates** — vendor deps must be imported through `assets/js/app.js`

### Environment

- `.env` file loaded by `scripts/load_env.sh` (used by `mix dev`); `.env` is in `.gitignore`
- Postgres: `dai_dev` database, `postgres`/`postgres` credentials in dev
- Port defaults to 4000 (overridable via `PORT` env var)
- `ANTHROPIC_API_KEY` required for AI queries

### Configuration (`Dai.Config`)

All Dai modules read config through `Dai.Config`, never `Application.get_env` directly:

| Config key | Type | Description |
|---|---|---|
| `:repo` | module | Ecto repo to query against (required) |
| `:schema_contexts` | `[module]` | Namespace prefixes for schema discovery |
| `:extra_schemas` | `[module]` | Individual schemas outside the contexts |
| `:ai` | keyword | `api_key`, `model`, `max_tokens` |

## Code conventions

Detailed Elixir, Phoenix, Ecto, HEEx, and LiveView conventions are in `AGENTS.md` — that file is authoritative. Key points summarized here:

### Commit messages

Use `type(scope): title` format:
- `feat(pipeline): add SQL plan validator`
- `fix(executor): normalize Decimal values`
- `refactor(namespace): move dashboard to Dai.*`
- `chore(deps): replace Chart.js with live_charts`
- `docs(readme): add library integration instructions`
- `test(liveview): add dashboard mount tests`

### Library conventions

- All library modules use `Dai.*` namespace (not `DaiWeb.*`)
- Library components use `Dai.Icons` for SVGs — never depend on host app's CoreComponents
- `Dai.DashboardLive` inlines its template in `render/1` (no separate .heex file)
- `Dai.AI.Component` is the single source of truth for component types — don't duplicate the list
- Schema discovery uses both `:application.get_key(:dai, :modules)` and `:code.all_loaded()` to find schemas in both standalone and library mode

### Elixir/Phoenix conventions

- Use `Req` for HTTP requests — never `:httpoison`, `:tesla`, or `:httpc`
- LiveView streams for all collections (never regular list assigns)
- Avoid LiveComponents unless there's a strong specific need
- `{...}` for HEEx attribute interpolation; `<%= ... %>` only for block constructs in tag bodies
- Class lists must use `[...]` syntax: `class={["px-2", @flag && "py-5"]}`
- Tailwind v4 `@import` syntax — never use `@apply`
- No daisyUI component library shortcuts — write tailwind-based components manually
- Use `Phoenix.LiveViewTest` + `LazyHTML` for assertions; test against element IDs/selectors, not raw HTML
