# Dai Library Extraction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Transform Dai from a standalone Phoenix app into a reusable library that host apps pull in as a git dependency.

**Architecture:** Host apps configure Repo, schema contexts, and AI key via `:dai` config. Dai introspects their schemas at boot via `:persistent_term`. A router macro mounts the dashboard LiveView. Chart.js is replaced by `live_charts` (hex package) to eliminate JS distribution. Sample schemas move to `Dai.Demo.Analytics`.

**Tech Stack:** Phoenix 1.8, LiveView 1.1, Ecto, live_charts (ApexCharts), Req, :persistent_term

**Spec:** `docs/superpowers/specs/2026-03-30-library-extraction-design.md`

---

## File Map

### New files

| File | Responsibility |
|---|---|
| `lib/dai/config.ex` | Centralized config reader for `:dai` app env |
| `lib/dai/router.ex` | `dai_dashboard/2` macro for host app routers |
| `lib/dai/layouts.ex` | Minimal layout for the dashboard (nav bar + theme toggle) |
| `lib/dai/dashboard_live.ex` | Moved from `lib/dai_web/live/dashboard_live.ex` |
| `lib/dai/dashboard_live.html.heex` | Moved from `lib/dai_web/live/dashboard_live.html.heex` |
| `lib/dai/dashboard_components.ex` | Moved from `lib/dai_web/components/dashboard_components.ex` |
| `lib/dai/demo/analytics/plan.ex` | Moved from `lib/dai/analytics/plan.ex` |
| `lib/dai/demo/analytics/user.ex` | Moved from `lib/dai/analytics/user.ex` |
| `lib/dai/demo/analytics/subscription.ex` | Moved from `lib/dai/analytics/subscription.ex` |
| `lib/dai/demo/analytics/invoice.ex` | Moved from `lib/dai/analytics/invoice.ex` |
| `lib/dai/demo/analytics/event.ex` | Moved from `lib/dai/analytics/event.ex` |
| `lib/dai/demo/analytics/feature.ex` | Moved from `lib/dai/analytics/feature.ex` |

### Modified files

| File | Change |
|---|---|
| `lib/dai/ai/client.ex` | Use `Dai.Config` instead of `Application.get_env` |
| `lib/dai/ai/sql_executor.ex` | Use `Dai.Config.repo()` instead of `Dai.Repo` |
| `lib/dai/schema_context.ex` | Boot-time introspection with context filtering |
| `lib/dai/application.ex` | Update for standalone mode (demo schemas) |
| `mix.exs` | Add `live_charts`, update aliases, standalone config |
| `config/config.exs` | Add `repo` and `schema_contexts` config for standalone |
| `config/runtime.exs` | Already correct |
| `README.md` | Host app integration instructions |

### Deleted files

| File | Reason |
|---|---|
| `assets/js/hooks/chart_hook.js` | Replaced by live_charts |
| `assets/package.json` | No npm deps needed |
| `assets/package-lock.json` | No npm deps needed |
| `lib/dai/analytics/*.ex` (6 files) | Moved to `lib/dai/demo/analytics/` |
| `lib/dai_web/live/dashboard_live.ex` | Moved to `lib/dai/` |
| `lib/dai_web/live/dashboard_live.html.heex` | Moved to `lib/dai/` |
| `lib/dai_web/components/dashboard_components.ex` | Moved to `lib/dai/` |

---

## Task 1: Add live_charts dependency and remove Chart.js

**Files:**
- Modify: `mix.exs`
- Delete: `assets/js/hooks/chart_hook.js`
- Delete: `assets/package.json`
- Delete: `assets/package-lock.json`
- Modify: `assets/js/app.js`

- [ ] **Step 1: Add live_charts to mix.exs deps**

In `mix.exs`, add to the `deps` list:

```elixir
{:live_charts, "~> 0.4.0"},
```

- [ ] **Step 2: Fetch deps**

```bash
mix deps.get
```

Expected: live_charts fetched successfully.

- [ ] **Step 3: Delete Chart.js files**

```bash
rm assets/js/hooks/chart_hook.js
rm assets/package.json
rm assets/package-lock.json
rm -rf assets/node_modules
```

- [ ] **Step 4: Update app.js — remove ChartHook import**

In `assets/js/app.js`, remove the ChartHook import line:

```javascript
import ChartHook from "./hooks/chart_hook"
```

And change the hooks object from:

```javascript
hooks: {...colocatedHooks, ChartHook},
```

to:

```javascript
hooks: {...colocatedHooks},
```

- [ ] **Step 5: Verify compilation**

```bash
mix compile
```

Expected: Compiles (dashboard_components.ex will have warnings about ChartHook references — that's OK, we'll fix in Task 5).

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "chore(deps): replace Chart.js with live_charts

Remove chart_hook.js, package.json, node_modules.
Add live_charts hex dependency."
```

---

## Task 2: Create Dai.Config module

**Files:**
- Create: `lib/dai/config.ex`
- Create: `test/dai/config_test.exs`

- [ ] **Step 1: Write test**

Create `test/dai/config_test.exs`:

```elixir
defmodule Dai.ConfigTest do
  use ExUnit.Case, async: true

  alias Dai.Config

  describe "repo/0" do
    test "returns configured repo" do
      assert Config.repo() == Dai.Repo
    end
  end

  describe "schema_contexts/0" do
    test "returns configured schema contexts" do
      contexts = Config.schema_contexts()
      assert is_list(contexts)
    end
  end

  describe "ai_config/0" do
    test "returns AI configuration keyword list" do
      config = Config.ai_config()
      assert is_list(config)
      assert Keyword.get(config, :model) == "claude-sonnet-4-6"
    end
  end

  describe "model/0" do
    test "returns model with default" do
      assert is_binary(Config.model())
    end
  end

  describe "max_tokens/0" do
    test "returns max_tokens with default" do
      assert Config.max_tokens() == 1024
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

```bash
mix test test/dai/config_test.exs
```

Expected: FAIL — `Dai.Config` does not exist.

- [ ] **Step 3: Implement Dai.Config**

Create `lib/dai/config.ex`:

```elixir
defmodule Dai.Config do
  @moduledoc "Centralized configuration reader for the Dai library."

  def repo do
    Application.fetch_env!(:dai, :repo)
  end

  def schema_contexts do
    Application.get_env(:dai, :schema_contexts, [])
  end

  def extra_schemas do
    Application.get_env(:dai, :extra_schemas, [])
  end

  def ai_config do
    Application.get_env(:dai, :ai, [])
  end

  def api_key do
    Keyword.get(ai_config(), :api_key)
  end

  def model do
    Keyword.get(ai_config(), :model, "claude-sonnet-4-6")
  end

  def max_tokens do
    Keyword.get(ai_config(), :max_tokens, 1024)
  end
end
```

- [ ] **Step 4: Add repo config for standalone mode**

In `config/config.exs`, add `repo` and `schema_contexts` to the existing `:dai` config. Find:

```elixir
config :dai,
  ecto_repos: [Dai.Repo],
  generators: [timestamp_type: :utc_datetime]
```

Change to:

```elixir
config :dai,
  ecto_repos: [Dai.Repo],
  generators: [timestamp_type: :utc_datetime],
  repo: Dai.Repo,
  schema_contexts: [Dai.Demo.Analytics]
```

- [ ] **Step 5: Run tests**

```bash
mix test test/dai/config_test.exs
```

Expected: All tests PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/dai/config.ex test/dai/config_test.exs config/config.exs
git commit -m "feat(config): add centralized Dai.Config module

Reads repo, schema_contexts, extra_schemas, and AI settings
from :dai application env. All other modules use this instead
of Application.get_env directly."
```

---

## Task 3: Update AI pipeline to use Dai.Config

**Files:**
- Modify: `lib/dai/ai/client.ex`
- Modify: `lib/dai/ai/sql_executor.ex`

- [ ] **Step 1: Update Client to use Dai.Config**

Replace the contents of `lib/dai/ai/client.ex`:

```elixir
defmodule Dai.AI.Client do
  @moduledoc "Sends prompts to the Claude API via Req and parses JSON responses."

  @api_url "https://api.anthropic.com/v1/messages"

  def generate_plan(prompt, schema_context) do
    with {:ok, api_key} <- fetch_api_key() do
      body = build_request_body(prompt, schema_context)
      call_api(api_key, body)
    end
  end

  defp fetch_api_key do
    case Dai.Config.api_key() do
      nil -> {:error, :api_error}
      key -> {:ok, key}
    end
  end

  defp build_request_body(prompt, schema_context) do
    %{
      model: Dai.Config.model(),
      max_tokens: Dai.Config.max_tokens(),
      system: Dai.AI.SystemPrompt.build(schema_context),
      messages: [%{role: "user", content: prompt}]
    }
  end

  defp call_api(api_key, body) do
    case Req.post(@api_url,
           json: body,
           headers: [
             {"x-api-key", api_key},
             {"anthropic-version", "2023-06-01"},
             {"content-type", "application/json"}
           ],
           receive_timeout: 30_000
         ) do
      {:ok, %Req.Response{status: 200, body: resp_body}} -> parse_response(resp_body)
      _ -> {:error, :api_error}
    end
  end

  defp parse_response(%{"content" => [%{"text" => text} | _]}) do
    case Jason.decode(text) do
      {:ok, plan} when is_map(plan) -> {:ok, plan}
      _ -> {:error, :invalid_json}
    end
  end

  defp parse_response(_), do: {:error, :invalid_json}
end
```

- [ ] **Step 2: Update SqlExecutor to use Dai.Config.repo()**

In `lib/dai/ai/sql_executor.ex`, change:

```elixir
case Ecto.Adapters.SQL.query(Dai.Repo, sql) do
```

to:

```elixir
case Ecto.Adapters.SQL.query(Dai.Config.repo(), sql) do
```

- [ ] **Step 3: Run existing tests**

```bash
mix test test/dai/ai/
```

Expected: All pipeline tests PASS (config returns Dai.Repo in standalone mode).

- [ ] **Step 4: Commit**

```bash
git add lib/dai/ai/client.ex lib/dai/ai/sql_executor.ex
git commit -m "refactor(pipeline): use Dai.Config for repo and AI settings

Client reads API key, model, max_tokens from Dai.Config.
SqlExecutor uses Dai.Config.repo() instead of hardcoded Dai.Repo."
```

---

## Task 4: Rewrite SchemaContext for boot-time introspection

**Files:**
- Modify: `lib/dai/schema_context.ex`
- Modify: `test/dai/schema_context_test.exs`
- Modify: `lib/mix/tasks/gen_schema_context.ex`

- [ ] **Step 1: Update SchemaContext test**

Replace `test/dai/schema_context_test.exs`:

```elixir
defmodule Dai.SchemaContextTest do
  use Dai.DataCase, async: true

  alias Dai.SchemaContext

  describe "get/0" do
    test "returns a non-empty schema context string" do
      context = SchemaContext.get()
      assert is_binary(context)
      assert String.contains?(context, "plans")
      assert String.contains?(context, "users")
      assert String.contains?(context, "subscriptions")
    end

    test "includes column information" do
      context = SchemaContext.get()
      assert String.contains?(context, "email")
      assert String.contains?(context, "amount_cents")
    end

    test "includes association information" do
      context = SchemaContext.get()
      assert String.contains?(context, "belongs_to")
      assert String.contains?(context, "has_many")
    end

    test "respects schema_contexts filter" do
      context = SchemaContext.get()
      # In standalone mode, schema_contexts is [Dai.Demo.Analytics]
      # so only demo schemas should appear
      assert String.contains?(context, "plans")
      assert String.contains?(context, "users")
    end
  end
end
```

- [ ] **Step 2: Rewrite SchemaContext**

Replace `lib/dai/schema_context.ex`:

```elixir
defmodule Dai.SchemaContext do
  @moduledoc "Discovers Ecto schemas at boot and caches a formatted context string."

  @key :dai_schema_context

  def child_spec(opts) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, [opts]}, type: :worker}
  end

  def start_link(_opts) do
    :persistent_term.put(@key, build_context())
    :ignore
  end

  def get do
    :persistent_term.get(@key)
  end

  def reload do
    :persistent_term.put(@key, build_context())
    :ok
  end

  defp build_context do
    schemas = discover_schemas()

    if schemas == [] do
      "No schemas discovered. Check your :dai :schema_contexts configuration."
    else
      schemas
      |> Enum.map(&extract_schema_info/1)
      |> format_context()
    end
  end

  defp discover_schemas do
    contexts = Dai.Config.schema_contexts()
    extras = Dai.Config.extra_schemas()

    :code.all_loaded()
    |> Enum.map(&elem(&1, 0))
    |> Enum.filter(fn mod ->
      Code.ensure_loaded?(mod) and
        function_exported?(mod, :__schema__, 1) and
        (matches_context?(mod, contexts) or mod in extras)
    end)
  end

  defp matches_context?(_mod, []), do: true

  defp matches_context?(mod, contexts) do
    mod_string = Atom.to_string(mod)

    Enum.any?(contexts, fn ctx ->
      String.starts_with?(mod_string, Atom.to_string(ctx))
    end)
  end

  defp extract_schema_info(mod) do
    fields =
      mod.__schema__(:fields)
      |> Enum.map(fn field ->
        type = mod.__schema__(:type, field)
        "#{field} (#{format_type(type)})"
      end)
      |> Enum.join(", ")

    associations =
      mod.__schema__(:associations)
      |> Enum.map(fn assoc_name ->
        assoc = mod.__schema__(:association, assoc_name)
        "#{assoc_type(assoc)} #{assoc_name} (#{assoc.queryable.__schema__(:source)})"
      end)

    pk = mod.__schema__(:primary_key) |> Enum.join(", ")
    source = mod.__schema__(:source)

    assoc_str =
      case associations do
        [] -> ""
        list -> "\n  Associations: #{Enum.join(list, ", ")}"
      end

    "Table: #{source}\n  Primary key: #{pk}\n  Columns: #{fields}#{assoc_str}"
  end

  defp assoc_type(%Ecto.Association.BelongsTo{}), do: "belongs_to"
  defp assoc_type(%Ecto.Association.Has{cardinality: :many}), do: "has_many"
  defp assoc_type(%Ecto.Association.Has{cardinality: :one}), do: "has_one"
  defp assoc_type(%Ecto.Association.ManyToMany{}), do: "many_to_many"
  defp assoc_type(_), do: "unknown"

  defp format_type(type) when is_atom(type), do: Atom.to_string(type)
  defp format_type({:parameterized, {Ecto.Embedded, _}}), do: "embedded"
  defp format_type(type), do: inspect(type)
end
```

- [ ] **Step 3: Update Mix task to use the same discovery logic**

Replace `lib/mix/tasks/gen_schema_context.ex`:

```elixir
defmodule Mix.Tasks.GenSchemaContext do
  @moduledoc "Prints the schema context that Dai sees. Useful for debugging."
  @shortdoc "Show Dai schema context"

  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    context = Dai.SchemaContext.get()
    Mix.shell().info(context)
  end
end
```

- [ ] **Step 4: Remove gen_schema_context from Mix aliases**

In `mix.exs`, remove these two alias lines:

```elixir
"ecto.migrate": ["ecto.migrate", "gen_schema_context"],
"phx.server": ["gen_schema_context", "phx.server"],
```

- [ ] **Step 5: Delete the old JSON file**

```bash
rm -f priv/ai/schema_context.json
rmdir priv/ai 2>/dev/null || true
```

- [ ] **Step 6: Update .gitignore — remove schema_context.json entry**

Remove this line from `.gitignore`:

```
priv/ai/schema_context.json
```

- [ ] **Step 7: Run tests**

```bash
mix test test/dai/schema_context_test.exs
```

Expected: All tests PASS.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "refactor(context): boot-time schema introspection with context filtering

SchemaContext now discovers schemas at startup by scanning loaded modules
and filtering by schema_contexts config. No Mix task or JSON file required.
gen_schema_context Mix task now just prints the context for debugging."
```

---

## Task 5: Move schemas to Dai.Demo.Analytics namespace

**Files:**
- Create: `lib/dai/demo/analytics/plan.ex` (moved + renamed)
- Create: `lib/dai/demo/analytics/user.ex` (moved + renamed)
- Create: `lib/dai/demo/analytics/subscription.ex` (moved + renamed)
- Create: `lib/dai/demo/analytics/invoice.ex` (moved + renamed)
- Create: `lib/dai/demo/analytics/event.ex` (moved + renamed)
- Create: `lib/dai/demo/analytics/feature.ex` (moved + renamed)
- Delete: `lib/dai/analytics/` (old location)
- Modify: `priv/repo/seeds.exs` (update aliases)

- [ ] **Step 1: Create demo directory**

```bash
mkdir -p lib/dai/demo/analytics
```

- [ ] **Step 2: Move and rename all 6 schema files**

For each file, copy to new location and update the module name from `Dai.Analytics.X` to `Dai.Demo.Analytics.X`. Also update all cross-references between schemas.

Create `lib/dai/demo/analytics/plan.ex`:

```elixir
defmodule Dai.Demo.Analytics.Plan do
  use Ecto.Schema
  import Ecto.Changeset

  schema "plans" do
    field :name, :string
    field :price_monthly, :integer, default: 0
    field :tier, :string

    has_many :subscriptions, Dai.Demo.Analytics.Subscription
    has_many :features, Dai.Demo.Analytics.Feature

    timestamps(type: :utc_datetime)
  end

  def changeset(plan, attrs) do
    plan
    |> cast(attrs, [:name, :price_monthly, :tier])
    |> validate_required([:name, :price_monthly, :tier])
    |> unique_constraint(:tier)
  end
end
```

Create `lib/dai/demo/analytics/user.ex`:

```elixir
defmodule Dai.Demo.Analytics.User do
  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field :name, :string
    field :email, :string
    field :role, :string, default: "member"
    field :org_name, :string

    has_many :subscriptions, Dai.Demo.Analytics.Subscription
    has_many :events, Dai.Demo.Analytics.Event

    timestamps(type: :utc_datetime)
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:name, :email, :role, :org_name])
    |> validate_required([:name, :email, :role, :org_name])
    |> unique_constraint(:email)
  end
end
```

Create `lib/dai/demo/analytics/subscription.ex`:

```elixir
defmodule Dai.Demo.Analytics.Subscription do
  use Ecto.Schema
  import Ecto.Changeset

  schema "subscriptions" do
    field :status, :string, default: "active"
    field :started_at, :utc_datetime
    field :cancelled_at, :utc_datetime

    belongs_to :user, Dai.Demo.Analytics.User
    belongs_to :plan, Dai.Demo.Analytics.Plan
    has_many :invoices, Dai.Demo.Analytics.Invoice

    timestamps(type: :utc_datetime)
  end

  def changeset(subscription, attrs) do
    subscription
    |> cast(attrs, [:status, :started_at, :cancelled_at])
    |> validate_required([:status, :started_at])
  end
end
```

Create `lib/dai/demo/analytics/invoice.ex`:

```elixir
defmodule Dai.Demo.Analytics.Invoice do
  use Ecto.Schema
  import Ecto.Changeset

  schema "invoices" do
    field :amount_cents, :integer
    field :status, :string, default: "pending"
    field :due_date, :date
    field :paid_at, :utc_datetime

    belongs_to :subscription, Dai.Demo.Analytics.Subscription

    timestamps(type: :utc_datetime)
  end

  def changeset(invoice, attrs) do
    invoice
    |> cast(attrs, [:amount_cents, :status, :due_date, :paid_at])
    |> validate_required([:amount_cents, :status, :due_date])
  end
end
```

Create `lib/dai/demo/analytics/event.ex`:

```elixir
defmodule Dai.Demo.Analytics.Event do
  use Ecto.Schema
  import Ecto.Changeset

  schema "events" do
    field :name, :string
    field :properties, :map, default: %{}

    belongs_to :user, Dai.Demo.Analytics.User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [:name, :properties])
    |> validate_required([:name])
  end
end
```

Create `lib/dai/demo/analytics/feature.ex`:

```elixir
defmodule Dai.Demo.Analytics.Feature do
  use Ecto.Schema
  import Ecto.Changeset

  schema "features" do
    field :name, :string
    field :enabled, :boolean, default: true

    belongs_to :plan, Dai.Demo.Analytics.Plan

    timestamps(type: :utc_datetime)
  end

  def changeset(feature, attrs) do
    feature
    |> cast(attrs, [:name, :enabled])
    |> validate_required([:name])
  end
end
```

- [ ] **Step 3: Delete old analytics directory**

```bash
rm -rf lib/dai/analytics
```

- [ ] **Step 4: Update seeds.exs aliases**

In `priv/repo/seeds.exs`, change the alias line from:

```elixir
alias Dai.Analytics.{Plan, User, Subscription, Invoice, Event, Feature}
```

to:

```elixir
alias Dai.Demo.Analytics.{Plan, User, Subscription, Invoice, Event, Feature}
```

- [ ] **Step 5: Verify compilation**

```bash
mix compile
```

Expected: Compiles with no errors.

- [ ] **Step 6: Run tests**

```bash
mix test
```

Expected: All tests pass. The SchemaContext test still finds the schemas because `schema_contexts` is `[Dai.Demo.Analytics]`.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "refactor(schema): move sample schemas to Dai.Demo.Analytics

Isolates demo data from library core. Host apps won't see these
schemas because they configure their own schema_contexts."
```

---

## Task 6: Rename DaiWeb namespace to Dai

**Files:**
- Create: `lib/dai/dashboard_live.ex` (moved from `lib/dai_web/live/`)
- Create: `lib/dai/dashboard_live.html.heex` (moved)
- Create: `lib/dai/dashboard_components.ex` (moved)
- Create: `lib/dai/layouts.ex` (new — extracted from DaiWeb.Layouts)
- Modify: `lib/dai_web/router.ex` (update route)
- Modify: `lib/dai_web/components/layouts.ex` (remove dashboard-specific code)
- Delete: `lib/dai_web/live/` (old location)
- Delete: `lib/dai_web/components/dashboard_components.ex` (old location)
- Modify: `test/dai_web/live/dashboard_live_test.exs`

- [ ] **Step 1: Create Dai.Layouts**

Create `lib/dai/layouts.ex`:

```elixir
defmodule Dai.Layouts do
  @moduledoc "Layout components for the Dai dashboard."

  use Phoenix.Component

  import Phoenix.HTML, only: [raw: 1]

  attr :flash, :map, required: true
  attr :inner_content, :any, required: true

  def root(assigns) do
    ~H"""
    {raw @inner_content}
    """
  end

  attr :flash, :map, required: true
  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div class="dai-dashboard">
      <header class="navbar px-4 sm:px-6 lg:px-8 border-b border-base-300">
        <div class="flex-1">
          <span class="flex items-center gap-2">
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="size-6 text-primary">
              <path d="M18.375 2.25c-1.035 0-1.875.84-1.875 1.875v15.75c0 1.035.84 1.875 1.875 1.875h.75c1.035 0 1.875-.84 1.875-1.875V4.125c0-1.035-.84-1.875-1.875-1.875h-.75ZM9.75 8.625c0-1.036.84-1.875 1.875-1.875h.75c1.036 0 1.875.84 1.875 1.875v11.25c0 1.035-.84 1.875-1.875 1.875h-.75a1.875 1.875 0 0 1-1.875-1.875V8.625ZM3 13.125c0-1.036.84-1.875 1.875-1.875h.75c1.036 0 1.875.84 1.875 1.875v6.75c0 1.035-.84 1.875-1.875 1.875h-.75A1.875 1.875 0 0 1 3 19.875v-6.75Z" />
            </svg>
            <span class="text-lg font-bold text-base-content">Dai</span>
          </span>
        </div>
      </header>

      <main class="px-4 py-8 sm:px-6 lg:px-8">
        {render_slot(@inner_block)}
      </main>
    </div>
    """
  end
end
```

- [ ] **Step 2: Create Dai.DashboardLive**

Create `lib/dai/dashboard_live.ex`:

```elixir
defmodule Dai.DashboardLive do
  use Phoenix.LiveView

  alias Dai.AI.{QueryPipeline, Result}
  alias Dai.SchemaContext

  import Dai.DashboardComponents

  @impl true
  def render(assigns) do
    ~H"""
    <Dai.Layouts.app flash={@flash}>
      <div class="max-w-7xl mx-auto">
        <%!-- Query Input --%>
        <div class="mb-10">
          <.form for={@form} phx-submit="query" id="query-form">
            <div class={[
              "relative flex items-center gap-2 rounded-2xl border bg-base-200/50 p-1.5 transition-all duration-300",
              @loading && "border-primary/40 shadow-[0_0_20px_-4px] shadow-primary/20",
              !@loading && "border-base-300 hover:border-primary/30 focus-within:border-primary/50 focus-within:shadow-[0_0_24px_-6px] focus-within:shadow-primary/15"
            ]}>
              <div class={[
                "pl-3 shrink-0 transition-colors duration-300",
                @loading && "text-primary animate-pulse",
                !@loading && "text-base-content/30"
              ]}>
                <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="size-5">
                  <path fill-rule="evenodd" d="M9 4.5a.75.75 0 0 1 .721.544l.813 2.846a3.75 3.75 0 0 0 2.576 2.576l2.846.813a.75.75 0 0 1 0 1.442l-2.846.813a3.75 3.75 0 0 0-2.576 2.576l-.813 2.846a.75.75 0 0 1-1.442 0l-.813-2.846a3.75 3.75 0 0 0-2.576-2.576l-2.846-.813a.75.75 0 0 1 0-1.442l2.846-.813A3.75 3.75 0 0 0 7.466 7.89l.813-2.846A.75.75 0 0 1 9 4.5Z" clip-rule="evenodd" />
                </svg>
              </div>

              <input
                type="text"
                name={@form[:prompt].name}
                id={@form[:prompt].id}
                value={Phoenix.HTML.Form.normalize_value("text", @form[:prompt].value)}
                placeholder="Ask anything about your data..."
                autocomplete="off"
                phx-debounce="300"
                class="flex-1 bg-transparent border-none text-base-content placeholder-base-content/30 text-base py-3 px-2 focus:outline-none"
              />

              <button
                type="submit"
                disabled={@loading}
                class={[
                  "shrink-0 flex items-center gap-2 rounded-xl px-5 py-2.5 font-medium text-sm transition-all duration-200",
                  @loading && "bg-primary/20 text-primary cursor-wait",
                  !@loading && "bg-primary text-primary-content hover:brightness-110 active:scale-[0.97]"
                ]}
              >
                <%= if @loading do %>
                  <span class="loading loading-spinner loading-xs"></span>
                  <span>Thinking</span>
                  <span class="inline-flex gap-0.5">
                    <span class="animate-bounce" style="animation-delay: 0ms">.</span>
                    <span class="animate-bounce" style="animation-delay: 150ms">.</span>
                    <span class="animate-bounce" style="animation-delay: 300ms">.</span>
                  </span>
                <% else %>
                  <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="size-4">
                    <path fill-rule="evenodd" d="M10 17a.75.75 0 0 1-.75-.75V5.612L5.29 9.77a.75.75 0 0 1-1.08-1.04l5.25-5.5a.75.75 0 0 1 1.08 0l5.25 5.5a.75.75 0 1 1-1.08 1.04l-3.96-4.158V16.25A.75.75 0 0 1 10 17Z" clip-rule="evenodd" />
                  </svg>
                  <span>Ask</span>
                <% end %>
              </button>
            </div>
          </.form>
        </div>

        <%!-- Loading skeleton --%>
        <%= if @loading do %>
          <div class="mb-6">
            <div class="rounded-xl border border-base-300/50 bg-base-200/30 p-5 animate-pulse">
              <div class="h-4 bg-base-300/60 rounded-lg w-1/3 mb-3"></div>
              <div class="h-3 bg-base-300/40 rounded-lg w-1/2 mb-5"></div>
              <div class="h-36 bg-base-300/30 rounded-lg"></div>
            </div>
          </div>
        <% end %>

        <%!-- Results Grid --%>
        <div
          id="results"
          phx-update="stream"
          class="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-4"
        >
          <div id="empty-state" class="hidden only:block col-span-full text-center py-24">
            <div class="text-base-content/20 mb-6">
              <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="size-20 mx-auto">
                <path d="M18.375 2.25c-1.035 0-1.875.84-1.875 1.875v15.75c0 1.035.84 1.875 1.875 1.875h.75c1.035 0 1.875-.84 1.875-1.875V4.125c0-1.035-.84-1.875-1.875-1.875h-.75ZM9.75 8.625c0-1.036.84-1.875 1.875-1.875h.75c1.036 0 1.875.84 1.875 1.875v11.25c0 1.035-.84 1.875-1.875 1.875h-.75a1.875 1.875 0 0 1-1.875-1.875V8.625ZM3 13.125c0-1.036.84-1.875 1.875-1.875h.75c1.036 0 1.875.84 1.875 1.875v6.75c0 1.035-.84 1.875-1.875 1.875h-.75A1.875 1.875 0 0 1 3 19.875v-6.75Z" />
              </svg>
            </div>
            <h2 class="text-2xl font-semibold text-base-content/40 mb-3">
              Ask anything about your data
            </h2>
            <p class="text-base-content/30 text-sm max-w-sm mx-auto leading-relaxed">
              Type a question in plain English and get instant charts, metrics, and tables.
            </p>
          </div>
          <div :for={{dom_id, result} <- @streams.results} id={dom_id}>
            <.result_card result={result} />
          </div>
        </div>
      </div>
    </Dai.Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(loading: false, current_prompt: nil, task_ref: nil)
     |> assign(:form, to_form(%{"prompt" => ""}, as: :query))
     |> stream(:results, [])}
  end

  @impl true
  def handle_event("query", %{"query" => %{"prompt" => prompt}}, socket) when prompt != "" do
    run_query(prompt, socket)
  end

  def handle_event("query", %{"prompt" => prompt}, socket) when prompt != "" do
    run_query(prompt, socket)
  end

  def handle_event("query", _params, socket), do: {:noreply, socket}

  def handle_event("dismiss", %{"id" => id}, socket) do
    {:noreply, stream_delete_by_dom_id(socket, :results, "results-#{id}")}
  end

  def handle_event("retry", %{"prompt" => prompt}, socket) do
    run_query(prompt, socket)
  end

  @impl true
  def handle_info({ref, result}, socket) when socket.assigns.task_ref == ref do
    Process.demonitor(ref, [:flush])

    card =
      case result do
        {:ok, r} -> r
        {:error, reason} -> Result.error(reason, socket.assigns.current_prompt)
      end

    {:noreply,
     socket
     |> stream_insert(:results, card, at: 0)
     |> assign(loading: false, task_ref: nil)}
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, socket)
      when socket.assigns.task_ref == ref do
    {:noreply, assign(socket, loading: false, task_ref: nil)}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  defp run_query(prompt, socket) do
    task = Task.async(fn -> QueryPipeline.run(prompt, SchemaContext.get()) end)

    {:noreply,
     assign(socket,
       loading: true,
       current_prompt: prompt,
       task_ref: task.ref,
       form: to_form(%{"prompt" => ""}, as: :query)
     )}
  end
end
```

Note: The template is inlined (no separate .heex file) since the library can't rely on the host app's file structure for template discovery. Icons use inline SVG instead of `<.icon>` since the host app's CoreComponents may not have heroicons.

- [ ] **Step 3: Create Dai.DashboardComponents**

Create `lib/dai/dashboard_components.ex` — same as the current `DaiWeb.DashboardComponents` but:
- Module name: `Dai.DashboardComponents`
- Remove `import DaiWeb.CoreComponents, only: [icon: 1]`
- Replace all `<.icon name="hero-..." class="...">` with inline SVGs
- Replace Chart.js chart component with live_charts (done in Task 7)

For now, just rename the module and use inline SVGs. The chart component will be updated in Task 7.

```elixir
defmodule Dai.DashboardComponents do
  @moduledoc "Function components for dashboard result cards."

  use Phoenix.Component

  alias Dai.AI.Result

  attr :result, Result, required: true

  def result_card(assigns) do
    ~H"""
    <div
      id={"result-#{@result.id}"}
      class={[
        "rounded-lg border border-base-300 bg-base-100 shadow-sm overflow-hidden",
        @result.type == :error && "border-error/30"
      ]}
    >
      <div class="flex items-start justify-between p-4 pb-2">
        <div>
          <h3 class="font-semibold text-base-content text-sm">{@result.title}</h3>
          <p class="text-xs text-base-content/60 mt-0.5">{@result.description}</p>
        </div>
        <button
          phx-click="dismiss"
          phx-value-id={@result.id}
          class="btn btn-ghost btn-xs btn-circle opacity-50 hover:opacity-100"
          aria-label="Dismiss"
        >
          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="size-4">
            <path d="M6.28 5.22a.75.75 0 0 0-1.06 1.06L8.94 10l-3.72 3.72a.75.75 0 1 0 1.06 1.06L10 11.06l3.72 3.72a.75.75 0 1 0 1.06-1.06L11.06 10l3.72-3.72a.75.75 0 0 0-1.06-1.06L10 8.94 6.28 5.22Z" />
          </svg>
        </button>
      </div>
      <div class="p-4 pt-2">
        <.card_body result={@result} />
      </div>
    </div>
    """
  end

  attr :result, Result, required: true

  defp card_body(%{result: %{type: :kpi_metric}} = assigns) do
    ~H"""
    <.kpi_metric result={@result} />
    """
  end

  defp card_body(%{result: %{type: type}} = assigns)
       when type in [:bar_chart, :line_chart, :pie_chart] do
    ~H"""
    <.chart result={@result} />
    """
  end

  defp card_body(%{result: %{type: :data_table}} = assigns) do
    ~H"""
    <.data_table result={@result} />
    """
  end

  defp card_body(%{result: %{type: :error}} = assigns) do
    ~H"""
    <.error_card result={@result} />
    """
  end

  defp card_body(%{result: %{type: :clarification}} = assigns) do
    ~H"""
    <.clarification_card result={@result} />
    """
  end

  attr :result, Result, required: true

  defp kpi_metric(assigns) do
    value = get_kpi_value(assigns.result)
    format = get_in(assigns.result.config, ["format"]) || "number"
    formatted = format_kpi(value, format)
    label = get_in(assigns.result.config, ["label"]) || assigns.result.title
    assigns = assign(assigns, formatted: formatted, label: label)

    ~H"""
    <div class="text-center py-4">
      <div class="text-4xl font-bold text-primary">{@formatted}</div>
      <div class="text-sm text-base-content/60 mt-1">{@label}</div>
    </div>
    """
  end

  attr :result, Result, required: true

  defp chart(assigns) do
    # Placeholder — will be replaced with live_charts in Task 7
    ~H"""
    <div id={"chart-#{@result.id}"} class="h-64 flex items-center justify-center text-base-content/40">
      Chart placeholder (live_charts integration pending)
    </div>
    """
  end

  attr :result, Result, required: true

  defp data_table(assigns) do
    columns = assigns.result.data.columns
    rows = assigns.result.data.rows
    assigns = assign(assigns, columns: columns, rows: rows)

    ~H"""
    <div class="overflow-x-auto max-h-80">
      <table class="table table-xs">
        <thead>
          <tr>
            <th :for={col <- @columns} class="text-base-content/70">{col}</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={row <- @rows} class="hover:bg-base-200/50">
            <td :for={col <- @columns} class="text-sm">{format_cell(row[col])}</td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  attr :result, Result, required: true

  defp error_card(assigns) do
    ~H"""
    <div class="flex flex-col items-center gap-3 py-4">
      <div class="flex items-center gap-2 text-error">
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="size-5">
          <path fill-rule="evenodd" d="M8.485 2.495c.673-1.167 2.357-1.167 3.03 0l6.28 10.875c.673 1.167-.17 2.625-1.516 2.625H3.72c-1.347 0-2.189-1.458-1.515-2.625L8.485 2.495ZM10 5a.75.75 0 0 1 .75.75v3.5a.75.75 0 0 1-1.5 0v-3.5A.75.75 0 0 1 10 5Zm0 9a1 1 0 1 0 0-2 1 1 0 0 0 0 2Z" clip-rule="evenodd" />
        </svg>
        <span class="text-sm">{@result.error}</span>
      </div>
      <button
        phx-click="retry"
        phx-value-prompt={@result.prompt}
        class="btn btn-sm btn-outline btn-error"
      >
        Try again
      </button>
    </div>
    """
  end

  attr :result, Result, required: true

  defp clarification_card(assigns) do
    ~H"""
    <div class="flex flex-col gap-3 py-2">
      <div class="flex items-start gap-2">
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="size-5 text-info shrink-0 mt-0.5">
          <path fill-rule="evenodd" d="M10 2c-2.236 0-4.43.18-6.57.524C1.993 2.755 1 4.014 1 5.426v5.148c0 1.413.993 2.67 2.43 2.902 1.168.188 2.352.327 3.55.414.28.02.521.18.642.413l1.713 3.293a.75.75 0 0 0 1.33 0l1.713-3.293a.783.783 0 0 1 .642-.413 41.102 41.102 0 0 0 3.55-.414c1.437-.231 2.43-1.49 2.43-2.902V5.426c0-1.413-.993-2.67-2.43-2.902A41.289 41.289 0 0 0 10 2ZM6.75 6a.75.75 0 0 0 0 1.5h6.5a.75.75 0 0 0 0-1.5h-6.5Zm0 2.5a.75.75 0 0 0 0 1.5h3.5a.75.75 0 0 0 0-1.5h-3.5Z" clip-rule="evenodd" />
        </svg>
        <p class="text-sm text-base-content">{@result.question}</p>
      </div>
      <form phx-submit="query" class="flex gap-2">
        <input
          type="text"
          name="prompt"
          placeholder="Type your answer..."
          class="input input-sm input-bordered flex-1"
          autocomplete="off"
        />
        <button type="submit" class="btn btn-sm btn-primary">Send</button>
      </form>
    </div>
    """
  end

  # --- Helpers ---

  defp get_kpi_value(%{data: %{rows: [first | _], columns: [col | _]}}), do: Map.get(first, col)
  defp get_kpi_value(_), do: 0

  defp format_kpi(value, "currency") when is_integer(value), do: "$#{format_integer(value)}.00"
  defp format_kpi(value, "currency") when is_float(value), do: "$#{:erlang.float_to_binary(value, decimals: 2)}"
  defp format_kpi(value, "currency"), do: "$#{value}"
  defp format_kpi(value, "percent") when is_float(value), do: "#{:erlang.float_to_binary(value, decimals: 1)}%"
  defp format_kpi(value, "percent") when is_integer(value), do: "#{value}%"
  defp format_kpi(value, _format) when is_integer(value), do: format_integer(value)
  defp format_kpi(value, _format), do: to_string(value)

  defp format_integer(n) do
    n |> Integer.to_string() |> String.reverse() |> String.replace(~r/(\d{3})(?=\d)/, "\\1,") |> String.reverse()
  end

  defp format_cell(nil), do: "-"
  defp format_cell(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M")
  defp format_cell(%Date{} = d), do: Calendar.strftime(d, "%Y-%m-%d")
  defp format_cell(value), do: to_string(value)
end
```

- [ ] **Step 4: Delete old DaiWeb files**

```bash
rm -rf lib/dai_web/live
rm lib/dai_web/components/dashboard_components.ex
```

- [ ] **Step 5: Update DaiWeb router for standalone mode**

In `lib/dai_web/router.ex`, change:

```elixir
live "/", DashboardLive
```

to:

```elixir
live "/", Dai.DashboardLive, :index
```

- [ ] **Step 6: Update test**

In `test/dai_web/live/dashboard_live_test.exs`, the tests should still work since they test the `/` route, not the module name directly.

- [ ] **Step 7: Verify compilation**

```bash
mix compile
```

- [ ] **Step 8: Run all tests**

```bash
mix test
```

Expected: All tests pass.

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "refactor(namespace): move dashboard to Dai.* namespace

Dai.DashboardLive, Dai.DashboardComponents, Dai.Layouts replace
DaiWeb.* equivalents. Uses inline SVGs instead of host app's
CoreComponents. Template inlined in LiveView module."
```

---

## Task 7: Integrate live_charts for chart rendering

**Files:**
- Modify: `lib/dai/dashboard_components.ex`

- [ ] **Step 1: Replace chart placeholder with live_charts**

In `lib/dai/dashboard_components.ex`, replace the `chart/1` function:

```elixir
  attr :result, Result, required: true

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
        chart: %{height: "100%"}
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

Also remove the old `chart_type_string/1` and `build_chart_config/1` helper functions that were for Chart.js.

- [ ] **Step 2: Verify compilation**

```bash
mix compile
```

- [ ] **Step 3: Commit**

```bash
git add lib/dai/dashboard_components.ex
git commit -m "feat(charts): integrate live_charts for chart rendering

Replace Chart.js hook with LiveCharts.build/1 and LiveCharts.chart
component for bar, line, and pie/donut charts."
```

---

## Task 8: Create Dai.Router macro

**Files:**
- Create: `lib/dai/router.ex`

- [ ] **Step 1: Create the router module**

Create `lib/dai/router.ex`:

```elixir
defmodule Dai.Router do
  @moduledoc """
  Router helpers for mounting the Dai dashboard.

  ## Usage

      import Dai.Router

      scope "/" do
        pipe_through :browser
        dai_dashboard "/dashboard"
      end
  """

  defmacro dai_dashboard(path, opts \\ []) do
    quote do
      live unquote(path), Dai.DashboardLive, :index, unquote(opts)
    end
  end
end
```

- [ ] **Step 2: Update DaiWeb.Router to use the macro**

In `lib/dai_web/router.ex`, change the route:

```elixir
  scope "/", DaiWeb do
    pipe_through :browser

    live "/", Dai.DashboardLive, :index
  end
```

to:

```elixir
  import Dai.Router

  scope "/" do
    pipe_through :browser

    dai_dashboard "/"
  end
```

- [ ] **Step 3: Verify compilation and tests**

```bash
mix compile && mix test
```

Expected: All pass.

- [ ] **Step 4: Commit**

```bash
git add lib/dai/router.ex lib/dai_web/router.ex
git commit -m "feat(router): add dai_dashboard/2 macro for host app routing

Host apps import Dai.Router and call dai_dashboard \"/path\"
to mount the dashboard LiveView."
```

---

## Task 9: Update standalone app configuration

**Files:**
- Modify: `lib/dai/application.ex`
- Modify: `lib/dai_web/components/layouts.ex` (restore to scaffold default)

- [ ] **Step 1: Update application.ex**

The standalone app still needs the DaiWeb scaffold to work. Keep it as-is — `Dai.SchemaContext` is already in the supervision tree.

No changes needed to `application.ex`.

- [ ] **Step 2: Restore DaiWeb.Layouts to scaffold default**

The `DaiWeb.Layouts.app` function was customized for the dashboard. Now that the dashboard has its own `Dai.Layouts`, restore the DaiWeb layout to a simple wrapper:

In `lib/dai_web/components/layouts.ex`, replace the `app` function template with:

```heex
    ~H"""
    <main class="px-4 py-8 sm:px-6 lg:px-8">
      {render_slot(@inner_block)}
    </main>

    <.flash_group flash={@flash} />
    """
```

- [ ] **Step 3: Run all tests**

```bash
mix test
```

- [ ] **Step 4: Commit**

```bash
git add lib/dai_web/components/layouts.ex
git commit -m "chore(layout): simplify DaiWeb layout, dashboard uses Dai.Layouts"
```

---

## Task 10: Update README and final verification

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Update README with library integration instructions**

Add a "Use as a library" section to the README, after the "Quick start" section:

```markdown
## Use as a library

Add Dai to an existing Phoenix app:

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

### 3. Supervision tree

```elixir
# application.ex
children = [
  MyApp.Repo,
  Dai.SchemaContext,  # add this before Endpoint
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
```

- [ ] **Step 2: Run precommit**

```bash
mix precommit
```

Expected: All checks pass.

- [ ] **Step 3: Verify standalone mode**

```bash
mix ecto.reset && mix phx.server
```

Visit `http://localhost:4000` — dashboard should work with demo data.

- [ ] **Step 4: Commit and push**

```bash
git add README.md
git commit -m "docs(readme): add library integration instructions"
git push
```
