# Dai

A natural-language data dashboard built on Phoenix LiveView and Claude. Ask questions in plain English, get instant charts, metrics, and tables.

![Phoenix](https://img.shields.io/badge/Phoenix-1.8-orange) ![Elixir](https://img.shields.io/badge/Elixir-1.15+-purple) ![License](https://img.shields.io/badge/License-MIT-blue)

## How it works

```
"revenue by plan this month"
        |
   Schema Context  ──>  Claude API  ──>  SQL Validation  ──>  Postgres  ──>  LiveView Card
   (auto-generated)     (NL -> SQL)     (blocklist+LIMIT)    (raw query)    (chart/table/KPI)
```

Type a question. Dai sends it to Claude along with your database schema, gets back a SQL query and a visualization type, validates and executes the query, and renders the result as a card in a dashboard grid. No dashboards to configure, no filters to learn.

## Features

- **5 visualization types** -- KPI metrics, bar charts, line charts, pie charts, data tables
- **Schema-aware AI** -- auto-introspects your Ecto schemas so Claude knows your data model
- **Safe SQL execution** -- keyword blocklist (no INSERT/DELETE/DROP), enforced LIMIT clauses
- **Clarification flow** -- Claude asks follow-up questions when your query is ambiguous
- **Theme-aware charts** -- Chart.js reads DaisyUI CSS variables, re-renders on theme switch
- **Light/dark/system toggle** -- inherits host app theme, works standalone too

## Quick start

### Prerequisites

- Elixir 1.15+
- PostgreSQL
- [Anthropic API key](https://console.anthropic.com/)

### Setup

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
  analytics/         # Ecto schemas (Plan, User, Subscription, Invoice, Event, Feature)
  ai/
    client.ex        # Claude Messages API via Req
    plan_validator.ex # SQL blocklist + LIMIT enforcement
    sql_executor.ex   # Raw query via Ecto.Adapters.SQL
    result_assembler.ex
    query_pipeline.ex # Chains the above 4 steps
    system_prompt.ex  # Builds the Claude prompt with schema + rules + examples
    component.ex      # Component type registry (single source of truth)
    result.ex         # %Result{} struct flowing through the pipeline
  schema_context.ex   # :persistent_term cache of schema description

lib/dai_web/
  live/
    dashboard_live.ex      # Main LiveView -- form, async task, stream
    dashboard_live.html.heex
  components/
    dashboard_components.ex # Card components for each result type

assets/js/hooks/
  chart_hook.js       # Chart.js + MutationObserver for theme sync
```

The pipeline is a pure function chain (`QueryPipeline.run/2`) called via `Task.async` from the LiveView. Results stream into a CSS grid as cards. No client-side state management.

## Commands

| Task | Command |
|---|---|
| Setup (deps + DB + assets) | `mix setup` |
| Dev server (loads .env) | `mix dev` |
| Run all tests | `mix test` |
| Precommit checks | `mix precommit` |
| Regenerate schema context | `mix gen_schema_context` |
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
| Charts | Chart.js |

## Configuration

| Variable | Required | Default | Purpose |
|---|---|---|---|
| `ANTHROPIC_API_KEY` | Yes | -- | Claude API authentication |
| `AI_MODEL` | No | `claude-sonnet-4-6` | Claude model ID |
| `PORT` | No | `4000` | HTTP port |
