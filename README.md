# Dai

A natural-language data dashboard that plugs into any Phoenix app. Ask questions in plain English, get instant charts, metrics, and tables — powered by Claude.

![Phoenix](https://img.shields.io/badge/Phoenix-1.8-orange) ![Elixir](https://img.shields.io/badge/Elixir-1.15+-purple) ![License](https://img.shields.io/badge/License-MIT-blue)

## How it works

```
"revenue by plan this month"
        |
   Schema Context  -->  Claude API  -->  SQL Validation  -->  Postgres  -->  LiveView Card
   (boot-time)         (NL -> SQL)     (blocklist+LIMIT)    (raw query)    (chart/table/KPI)
```

Dai introspects your Ecto schemas at boot, sends the user's question + schema context to Claude, validates and executes the returned SQL, and renders the result as a card in a dashboard grid. No dashboards to configure, no filters to learn.

## Features

- **5 visualization types** — KPI metrics, bar charts, line charts, pie charts, data tables
- **Schema-aware AI** — auto-discovers your Ecto schemas by namespace at boot
- **Safe SQL execution** — keyword blocklist (no INSERT/DELETE/DROP), enforced LIMIT clauses
- **Clarification flow** — Claude asks follow-up questions when your query is ambiguous
- **Theme-aware charts** — ApexCharts via live_charts, inherits DaisyUI CSS variables
- **Library-first** — designed as a dependency for existing Phoenix apps

## Use as a library

Add Dai to an existing Phoenix app in 5 steps:

### 1. Dependencies

```elixir
# mix.exs
{:dai, git: "https://github.com/pleleu-dev/dai.git"},
{:live_charts, "~> 0.4.0"}
```

### 2. Configuration

```elixir
# config/config.exs
config :dai,
  repo: MyApp.Repo,
  schema_contexts: [MyApp.Orders, MyApp.Products]

# config/runtime.exs
config :dai, :ai,
  api_key: System.get_env("ANTHROPIC_API_KEY"),
  model: System.get_env("AI_MODEL") || "claude-sonnet-4-6",
  max_tokens: 1024
```

`schema_contexts` controls which Ecto schemas Dai can see. Any schema whose module name starts with a listed context is included (e.g. `MyApp.Orders.Order` matches `MyApp.Orders`). Use `extra_schemas: [MyApp.Legacy.SomeTable]` for one-offs outside those namespaces.

### 3. Supervision tree

```elixir
# application.ex
children = [
  MyApp.Repo,
  Dai.SchemaContext,  # add before Endpoint
  MyAppWeb.Endpoint
]
```

### 4. Router

```elixir
# router.ex
import Dai.Router

scope "/" do
  pipe_through :browser
  dai_dashboard "/dashboard"
end
```

### 5. JS hooks (live_charts)

```javascript
// app.js
import { Hooks as LiveChartsHooks } from "live_charts"

const liveSocket = new LiveSocket("/live", Socket, {
  hooks: {...colocatedHooks, ...LiveChartsHooks}
})
```

Visit `/dashboard` and start asking questions about your data.

## Run standalone (development)

Dai ships with a SaaS analytics demo dataset for standalone development and testing.

```bash
git clone https://github.com/pleleu-dev/dai.git
cd dai

# Create .env with your API key
echo 'ANTHROPIC_API_KEY=sk-ant-your-key-here' > .env

# Install deps, create DB, run migrations, seed data
mix setup

# Start the server (loads .env automatically)
mix dev
```

Visit [localhost:4000](http://localhost:4000).

### Example queries

| Query | Result |
|---|---|
| how many active subscribers? | KPI card |
| revenue by plan this month | Bar chart |
| signups over the last 6 months | Line chart |
| subscription distribution by plan | Pie chart |
| show recent failed invoices | Data table |

## Architecture

```
lib/dai/
  config.ex              # Centralized config reader (:dai app env)
  schema_context.ex      # Boot-time Ecto schema introspection via :persistent_term
  router.ex              # dai_dashboard/2 macro for host app routers
  icons.ex               # Self-contained SVG icon components
  layouts.ex             # Dashboard layout (nav bar)
  dashboard_live.ex      # Main LiveView — form, async task, stream
  dashboard_components.ex # Card components for each result type
  ai/
    query_pipeline.ex    # Chains: Client -> Validator -> Executor -> Assembler
    client.ex            # Claude Messages API via Req
    system_prompt.ex     # Builds prompt with schema + rules + examples
    plan_validator.ex    # SQL keyword blocklist + LIMIT enforcement
    sql_executor.ex      # Raw query via Ecto.Adapters.SQL + type normalization
    result_assembler.ex  # Builds %Result{} structs
    result.ex            # Result struct definition
    component.ex         # Component type registry (single source of truth)
  demo/
    analytics/           # Sample schemas (standalone mode only)
```

The pipeline is a pure function chain (`QueryPipeline.run/2`) called via `Task.async` from the LiveView. Results stream into a CSS grid as cards. Charts rendered by live_charts (ApexCharts). No client-side state management.

## Commands

| Task | Command |
|---|---|
| Setup (deps + DB + assets) | `mix setup` |
| Dev server (loads .env) | `mix dev` |
| Run all tests | `mix test` |
| Precommit checks | `mix precommit` |
| Show schema context | `mix gen_schema_context` |
| Reset database | `mix ecto.reset` |

## Tech stack

| Layer | Technology |
|---|---|
| Web framework | Phoenix 1.8 |
| Real-time UI | LiveView 1.1 |
| CSS | Tailwind v4 + DaisyUI 5 |
| Database | PostgreSQL + Ecto |
| AI | Claude Sonnet 4.6 (Anthropic) |
| HTTP client | Req |
| Charts | live_charts (ApexCharts) |

## Configuration

| Variable | Required | Default | Purpose |
|---|---|---|---|
| `ANTHROPIC_API_KEY` | Yes | -- | Claude API authentication |
| `AI_MODEL` | No | `claude-sonnet-4-6` | Claude model ID |
| `PORT` | No | `4000` | HTTP port |
