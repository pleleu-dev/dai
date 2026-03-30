# Dai Library Extraction — Design Spec

> Extract Dai from a standalone Phoenix app into a reusable library that host apps pull in as a git dependency. Host apps configure their Repo and schema contexts; Dai introspects their schemas at boot and serves the dashboard at a mounted route.

---

## Scope

**In scope:**

- Restructure Dai as a library dependency (git dep via mix.exs)
- Host app configures Repo, schema contexts, and AI key via `:dai` config
- Router macro `dai_dashboard/2` for mounting the LiveView
- Boot-time schema introspection (no Mix task required)
- Replace Chart.js with `live_charts` (ApexCharts) — eliminates JS distribution problem
- Move sample schemas to `Dai.Demo` namespace (conditional compilation)
- Rename `DaiWeb.*` to `Dai.*` namespace

**Out of scope:**

- Publishing to Hex (git dependency for now)
- Multi-tenancy / row-level scoping
- Any new features — this is a packaging refactor

---

## Host App Integration

### Step 1 — Dependencies

```elixir
# Host app's mix.exs
defp deps do
  [
    {:dai, git: "https://github.com/pleleu-dev/dai.git"},
    {:live_charts, "~> 0.4.0"}
  ]
end
```

### Step 2 — Configuration

```elixir
# Host app's config/config.exs
config :dai,
  repo: MyApp.Repo,
  schema_contexts: [MyApp.Orders, MyApp.Products],
  extra_schemas: []  # optional, for one-off schemas outside the contexts

# Host app's config/runtime.exs
config :dai, :ai,
  api_key: System.get_env("ANTHROPIC_API_KEY"),
  model: System.get_env("AI_MODEL") || "claude-sonnet-4-6",
  max_tokens: 1024
```

### Step 3 — Router

```elixir
# Host app's router.ex
import Dai.Router

scope "/" do
  pipe_through :browser
  dai_dashboard "/dashboard"
end
```

### Step 4 — JS hooks (live_charts)

```javascript
// Host app's app.js
import { Hooks as LiveChartsHooks } from "live_charts"

const liveSocket = new LiveSocket("/live", Socket, {
  hooks: {...colocatedHooks, ...LiveChartsHooks}
})
```

This is already documented by live_charts — Dai just mentions it in the README.

---

## Configuration Module: `Dai.Config`

Single module that reads and validates all `:dai` config at runtime.

```elixir
defmodule Dai.Config do
  def repo, do: Application.fetch_env!(:dai, :repo)
  def schema_contexts, do: Application.get_env(:dai, :schema_contexts, [])
  def extra_schemas, do: Application.get_env(:dai, :extra_schemas, [])
  def ai_config, do: Application.get_env(:dai, :ai, [])
  def api_key, do: Keyword.get(ai_config(), :api_key)
  def model, do: Keyword.get(ai_config(), :model, "claude-sonnet-4-6")
  def max_tokens, do: Keyword.get(ai_config(), :max_tokens, 1024)
end
```

All other modules read config through `Dai.Config` — never `Application.get_env` directly.

---

## Schema Discovery: Boot-Time Introspection

`Dai.SchemaContext` introspects at boot instead of requiring a Mix task.

### Discovery logic

A module is included if:
1. It exports `__schema__/1` (is an Ecto schema)
2. Its module name starts with one of the configured `schema_contexts` (e.g. `MyApp.Orders.Order` matches `MyApp.Orders`)
3. OR it's explicitly listed in `extra_schemas`

When no `schema_contexts` configured (standalone mode), falls back to scanning all schemas in the app.

### Implementation

```elixir
defmodule Dai.SchemaContext do
  @key :dai_schema_context

  def child_spec(opts) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, [opts]}, type: :worker}
  end

  def start_link(_opts) do
    :persistent_term.put(@key, build_context())
    :ignore
  end

  def get, do: :persistent_term.get(@key)
  def reload, do: :persistent_term.put(@key, build_context())

  defp build_context do
    discover_schemas()
    |> Enum.map(&extract_schema_info/1)
    |> format_context()
  end

  defp discover_schemas do
    contexts = Dai.Config.schema_contexts()
    extras = Dai.Config.extra_schemas()

    all_modules()
    |> Enum.filter(fn mod ->
      Code.ensure_loaded?(mod) and function_exported?(mod, :__schema__, 1) and
        (matches_context?(mod, contexts) or mod in extras)
    end)
  end

  defp matches_context?(_mod, []), do: true  # no filter = all schemas
  defp matches_context?(mod, contexts) do
    mod_string = Atom.to_string(mod)
    Enum.any?(contexts, fn ctx -> String.starts_with?(mod_string, Atom.to_string(ctx)) end)
  end

  defp all_modules do
    :code.all_loaded()
    |> Enum.map(&elem(&1, 0))
  end
end
```

The Mix task `mix gen_schema_context` stays as an optional debugging tool but is not required.

---

## Router Macro: `Dai.Router`

```elixir
defmodule Dai.Router do
  defmacro dai_dashboard(path, opts \\ []) do
    quote do
      live unquote(path), Dai.DashboardLive, :index, unquote(opts)
    end
  end
end
```

The macro mounts `Dai.DashboardLive` at the given path. The host app controls the surrounding `scope`, `pipe_through`, and `live_session`.

### SchemaContext startup

The host app adds `Dai.SchemaContext` to their supervision tree (required step, documented in README):

```elixir
# Host app's application.ex
children = [
  MyApp.Repo,
  Dai.SchemaContext,
  MyAppWeb.Endpoint
]
```

---

## Chart Migration: Chart.js to live_charts

### Dependency change

```elixir
# Dai's mix.exs
{:live_charts, "~> 0.4.0"}
```

### Files deleted

- `assets/js/hooks/chart_hook.js`
- `assets/package.json`
- `assets/package-lock.json`

### Component changes

The `chart/1` component in `Dai.DashboardComponents` changes from custom Chart.js hook to `LiveCharts.chart`:

```elixir
defp chart(assigns) do
  chart = build_live_chart(assigns.result)
  assigns = assign(assigns, :chart, chart)

  ~H"""
  <div id={"chart-#{@result.id}"} class="h-64">
    <LiveCharts.chart chart={@chart} />
  </div>
  """
end

defp build_live_chart(%{type: :bar_chart, data: data, config: config}) do
  x_axis = config["x_axis"] || Enum.at(data.columns, 0)
  y_axis = config["y_axis"] || Enum.at(data.columns, 1)

  LiveCharts.build(%{
    type: :bar,
    series: [%{name: y_axis, data: Enum.map(data.rows, &(&1[y_axis]))}],
    options: %{
      xaxis: %{categories: Enum.map(data.rows, &to_string(&1[x_axis]))},
      chart: %{height: "100%"},
      theme: %{mode: "dark"}
    }
  })
end

defp build_live_chart(%{type: :line_chart, data: data, config: config}) do
  x_axis = config["x_axis"] || Enum.at(data.columns, 0)
  y_axis = config["y_axis"] || Enum.at(data.columns, 1)

  LiveCharts.build(%{
    type: :line,
    series: [%{name: y_axis, data: Enum.map(data.rows, &(&1[y_axis]))}],
    options: %{
      xaxis: %{categories: Enum.map(data.rows, &to_string(&1[x_axis]))},
      chart: %{height: "100%"},
      stroke: %{curve: "smooth"}
    }
  })
end

defp build_live_chart(%{type: :pie_chart, data: data, config: config}) do
  label_field = config["label_field"] || Enum.at(data.columns, 0)
  value_field = config["value_field"] || Enum.at(data.columns, 1)

  LiveCharts.build(%{
    type: if(length(data.rows) > 4, do: :donut, else: :pie),
    series: Enum.map(data.rows, &(&1[value_field])),
    options: %{
      labels: Enum.map(data.rows, &to_string(&1[label_field])),
      chart: %{height: "100%"}
    }
  })
end
```

### Theme handling

ApexCharts accepts CSS `var()` values in color options. DaisyUI CSS variables change when `data-theme` switches. For chart re-rendering on theme change, live_charts handles this through its hook — no custom MutationObserver needed.

---

## Namespace Changes

| Current | After | Reason |
|---|---|---|
| `DaiWeb.DashboardLive` | `Dai.DashboardLive` | Library doesn't own a `*Web` namespace |
| `DaiWeb.DashboardComponents` | `Dai.DashboardComponents` | Same |
| `DaiWeb.CoreComponents` | Not shipped | Host app has their own |
| `DaiWeb.Layouts` | `Dai.Layouts` | Minimal layout for the dashboard |
| `Dai.Analytics.*` | `Dai.Demo.Analytics.*` | Sample schemas isolated |

### Layout handling

Dai needs its own minimal layout since it can't use the host app's layout directly. Two options:

1. **Dai ships a minimal layout** that wraps the dashboard content. The host app's root layout still applies (set by the router's `put_root_layout`).
2. **Dai renders without a layout** and the host app wraps it.

Option 1 is better — Dai's app layout just provides the nav bar (Dai logo + theme toggle) inside whatever root layout the host app provides.

---

## Demo Mode (Standalone)

When Dai is the main application (not a dependency), it should still work standalone with the sample dataset for development and testing.

### Conditional compilation

```elixir
# lib/dai/demo/analytics/*.ex — only compiled when :dai is the main app
# mix.exs
defp elixirc_paths(:test), do: ["lib", "test/support"]
defp elixirc_paths(_) do
  if Mix.Project.config()[:app] == :dai do
    ["lib"]  # compile everything including demo
  else
    ["lib"]  # as a dep, all files compile but demo schemas won't match any schema_context
  end
end
```

Actually simpler: the demo schemas always compile but are never discovered by SchemaContext in a host app because they're under `Dai.Demo.Analytics`, which won't be in the host's `schema_contexts` config. No conditional compilation needed.

### Standalone config

```elixir
# Dai's own config/config.exs (used when running standalone)
config :dai,
  repo: Dai.Repo,
  schema_contexts: [Dai.Demo.Analytics],
  ai: [model: "claude-sonnet-4-6", max_tokens: 1024]
```

---

## File Structure (After)

```
lib/dai/
  config.ex                    # Reads/validates :dai config
  schema_context.ex            # Boot-time introspection via :persistent_term
  router.ex                    # dai_dashboard/2 macro
  dashboard_live.ex            # Main LiveView
  dashboard_live.html.heex     # Template
  dashboard_components.ex      # Card components (using live_charts)
  layouts.ex                   # Minimal app layout for dashboard
  ai/
    client.ex                  # Claude API via Req
    component.ex               # Component type registry
    plan_validator.ex           # SQL validation
    sql_executor.ex             # Raw query execution (uses Config.repo())
    result_assembler.ex         # Builds Result structs
    query_pipeline.ex           # Pipeline orchestrator
    system_prompt.ex            # Prompt builder
    result.ex                   # Result struct
  demo/
    analytics/                 # Sample schemas (Plan, User, etc.)
      plan.ex
      user.ex
      subscription.ex
      invoice.ex
      event.ex
      feature.ex

lib/mix/tasks/
  gen_schema_context.ex        # Optional debugging tool

priv/repo/
  migrations/                  # Demo migrations
  seeds.exs                    # Demo seeds

config/
  config.exs                   # Standalone defaults
  dev.exs
  test.exs
  runtime.exs
```

---

## Migration Path

Summary of changes from current state to library:

1. Add `live_charts` dependency, remove Chart.js npm package
2. Create `Dai.Config` module
3. Rename `DaiWeb.*` -> `Dai.*` (DashboardLive, DashboardComponents, Layouts)
4. Create `Dai.Router` with `dai_dashboard/2` macro
5. Update `SchemaContext` to introspect at boot with context filtering
6. Update `SqlExecutor` to use `Dai.Config.repo()`
7. Update `Client` to use `Dai.Config` for AI settings
8. Rewrite chart components to use `LiveCharts.build/1`
9. Move sample schemas to `Dai.Demo.Analytics.*`
10. Delete `assets/js/hooks/chart_hook.js`, `assets/package.json`
11. Update standalone config to use `Dai.Demo.Analytics` context
12. Update README with host app integration instructions
