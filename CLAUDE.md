# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

Dai is a Phoenix 1.8 LiveView application — an AI-powered natural-language data dashboard. Users ask questions in plain English; the system generates SQL, picks a visualization component, and renders the result via LiveView. See `ai_dashboard_project.md` for the full architecture spec and roadmap.

The codebase is currently a fresh Phoenix 1.8 scaffold. The AI pipeline, LiveViews, Chart.js hooks, and schema context system described in the project spec are **not yet implemented**.

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

`mix precommit` runs in the `:test` env (configured in `cli/preferred_envs`). Always run it before finalizing changes.

## Architecture

### Current state

Standard Phoenix 1.8 scaffold with Ecto/Postgres. No LiveViews, no AI pipeline modules yet. The only route is `GET /` via `PageController`.

### Key modules

- `Dai.Repo` — Ecto repo (Postgres)
- `DaiWeb.Router` — routes; the `/` scope is aliased to `DaiWeb` (don't duplicate the prefix in route module names)
- `DaiWeb.Layouts` — wraps all LiveView content; templates must start with `<Layouts.app flash={@flash} ...>`
- `DaiWeb.CoreComponents` — provides `<.input>`, `<.icon>`, `<.form>` and other function components (already imported in all views)
- `lib/dai_web.ex` — `html_helpers/0` imports `CoreComponents`, aliases `Layouts` and `JS` for all views

### Target pipeline (from spec, not yet built)

User query flows through: schema context injection → Claude API (NL→SQL+component JSON) → SQL validation (keyword blocklist + LIMIT) → raw query execution (`Ecto.Adapters.SQL.query/3`) → LiveView component render (`kpi_metric`, `bar_chart`, `line_chart`, `pie_chart`, `data_table`).

### Assets

- **Tailwind v4 + DaisyUI 5** — no `tailwind.config.js`; uses `@import "tailwindcss"` syntax in `assets/css/app.css`
- **DaisyUI themes** — two themes configured via `@plugin "../vendor/daisyui-theme"` in `app.css`: `light` (default) and `dark` (prefers-dark). Dark mode variant uses `data-theme` attribute, not media query
- **Colocated hooks** — `app.js` imports hooks from `phoenix-colocated/dai` and passes them to `LiveSocket`. New hooks should use Phoenix's colocated hook pattern
- **No external script/link tags in templates** — vendor deps must be imported through `assets/js/app.js` and `assets/css/app.css`
- **No inline `<script>` tags** — all JS goes in `assets/js/` and integrates via `app.js`

### Environment

- `.env` file loaded by `scripts/load_env.sh` (used by `mix dev`). **Note:** `.env` is not in `.gitignore` — add it before committing secrets
- Postgres: `dai_dev` database, `postgres`/`postgres` credentials in dev
- Port defaults to 4000 (overridable via `PORT` env var)

## Code conventions

Detailed Elixir, Phoenix, Ecto, HEEx, and LiveView conventions are in `AGENTS.md` — that file is authoritative. Key points summarized here:

- Use `Req` for HTTP requests — never `:httpoison`, `:tesla`, or `:httpc`
- LiveView streams for all collections (never regular list assigns)
- Avoid LiveComponents unless there's a strong specific need
- LiveView modules: `DaiWeb.FooLive` suffix; router scope already aliases `DaiWeb`
- `{...}` for HEEx attribute interpolation; `<%= ... %>` only for block constructs in tag bodies
- Class lists must use `[...]` syntax: `class={["px-2", @flag && "py-5"]}`
- Tailwind v4 `@import` syntax — never use `@apply`
- No daisyUI component library shortcuts — write tailwind-based components manually
- When using `phx-hook`, also set `phx-update="ignore"` if the hook manages its own DOM
- Use `Phoenix.LiveViewTest` + `LazyHTML` for assertions; test against element IDs/selectors, not raw HTML
