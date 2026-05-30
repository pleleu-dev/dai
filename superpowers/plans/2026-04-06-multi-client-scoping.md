# Multi-Client Scoping Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add client selection flow, scope all admin UI and API routes to a selected client, and build a generic Dai query scoping feature.

**Architecture:** Client gets a `slug` field for URL-friendly routing. A new `on_mount` hook resolves the slug and assigns `@current_client`. All admin LiveViews and API controllers scope queries through `client_id`. Dai gets a configurable `query_scope` + `scope_value` for prompt-based scoping.

**Tech Stack:** Phoenix 1.8, LiveView 1.1, Ecto, PostgreSQL, Tailwind/DaisyUI, Dai (git dependency)

---

### Task 1: Add slug to Client schema and migration

**Files:**
- Modify: `lib/hub/clients/client.ex`
- Modify: `lib/hub/clients.ex`
- Create: `priv/repo/migrations/TIMESTAMP_add_slug_to_clients.exs`
- Modify: `test/support/fixtures/clients_fixtures.ex`

- [ ] **Step 1: Create migration**

```bash
mix ecto.gen.migration add_slug_to_clients
```

Edit the generated file:

```elixir
defmodule Hub.Repo.Migrations.AddSlugToClients do
  use Ecto.Migration

  def change do
    alter table(:clients) do
      add :slug, :string
    end

    create unique_index(:clients, [:slug])
  end
end
```

- [ ] **Step 2: Add slug field to Client schema**

In `lib/hub/clients/client.ex`, add `slug` to the schema and changeset:

```elixir
defmodule Hub.Clients.Client do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "clients" do
    field :name, :string
    field :slug, :string
    field :webhook_url, :string
    field :webhook_secret, :string

    has_many :api_keys, Hub.Clients.ApiKey

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(client, attrs) do
    client
    |> cast(attrs, [:name, :slug, :webhook_url, :webhook_secret])
    |> validate_required([:name])
    |> maybe_generate_slug()
    |> unique_constraint(:name)
    |> unique_constraint(:slug)
  end

  defp maybe_generate_slug(changeset) do
    case get_field(changeset, :slug) do
      nil ->
        name = get_field(changeset, :name) || ""
        slug = name |> String.downcase() |> String.replace(~r/[^a-z0-9]+/, "-") |> String.trim("-")
        put_change(changeset, :slug, slug)

      _ ->
        changeset
    end
  end
end
```

- [ ] **Step 3: Add `get_client_by_slug/1` and client stats to Clients context**

In `lib/hub/clients.ex`, add:

```elixir
def get_client_by_slug(slug) do
  Repo.get_by(Client, slug: slug)
end

def list_clients_with_counts do
  Client
  |> order_by(:name)
  |> Repo.all()
  |> Enum.map(fn client ->
    org_count = Repo.aggregate(from(o in "organizations", where: o.client_id == ^client.id), :count)
    account_count =
      Repo.aggregate(
        from(a in "accounts",
          join: o in "organizations", on: a.organization_id == o.id,
          where: o.client_id == ^client.id),
        :count
      )

    %{client: client, org_count: org_count, account_count: account_count}
  end)
end

def delete_client(%Client{} = client) do
  Repo.delete(client)
end
```

- [ ] **Step 4: Run migration**

```bash
mix ecto.migrate
```

Expected: migration succeeds, `slug` column added to `clients`.

- [ ] **Step 5: Commit**

```bash
git add lib/hub/clients/client.ex lib/hub/clients.ex priv/repo/migrations/*add_slug_to_clients* test/support/fixtures/clients_fixtures.ex
git commit -m "feat(clients): add slug field to client schema"
```

---

### Task 2: Client selection LiveView

**Files:**
- Create: `lib/hub_web/live/admin/client_live/index.ex`

- [ ] **Step 1: Create the client selection LiveView**

```elixir
defmodule HubWeb.Admin.ClientLive.Index do
  use HubWeb, :live_view

  alias Hub.Clients

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, clients: Clients.list_clients_with_counts(), show_form: false, form: to_form(%{"name" => ""}))}
  end

  @impl true
  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  @impl true
  def handle_event("toggle-form", _params, socket) do
    {:noreply, assign(socket, show_form: !socket.assigns.show_form)}
  end

  @impl true
  def handle_event("create-client", %{"name" => name}, socket) do
    case Clients.create_client(%{name: name}) do
      {:ok, client} ->
        {:noreply, push_navigate(socket, to: ~p"/admin/clients/#{client.slug}/organizations")}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto">
      <div class="mb-8 flex items-center justify-between">
        <div>
          <h1 class="text-2xl font-bold text-base-content">Select a Client</h1>
          <p class="text-sm text-base-content/60 mt-1">Choose which client to manage</p>
        </div>
        <button phx-click="toggle-form" class="btn btn-primary btn-sm">
          <.icon name="hero-plus" class="size-4" /> New Client
        </button>
      </div>

      <div :if={@show_form} class="mb-6 rounded-lg border border-base-300 bg-base-100 p-4">
        <.form for={@form} phx-submit="create-client" class="flex gap-3">
          <.input field={@form[:name]} placeholder="Client name..." class="flex-1" />
          <button type="submit" class="btn btn-primary btn-sm">Create</button>
          <button type="button" phx-click="toggle-form" class="btn btn-ghost btn-sm">Cancel</button>
        </.form>
      </div>

      <div class="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
        <.link
          :for={%{client: client, org_count: org_count, account_count: account_count} <- @clients}
          navigate={~p"/admin/clients/#{client.slug}/organizations"}
          class="block rounded-lg border border-base-300 bg-base-100 p-6 hover:border-primary/50 hover:shadow-sm transition-all"
        >
          <h3 class="text-lg font-semibold text-base-content">{client.name}</h3>
          <div class="mt-3 flex gap-4 text-sm text-base-content/60">
            <span>{org_count} organizations</span>
            <span>{account_count} accounts</span>
          </div>
        </.link>
      </div>

      <div :if={@clients == []} class="text-center py-12 text-base-content/40">
        <p class="text-lg">No clients yet</p>
        <p class="text-sm mt-1">Create your first client to get started</p>
      </div>
    </div>
    """
  end
end
```

- [ ] **Step 2: Commit**

```bash
git add lib/hub_web/live/admin/client_live/index.ex
git commit -m "feat(admin): add client selection page"
```

---

### Task 3: ClientScope on_mount hook

**Files:**
- Create: `lib/hub_web/live/client_scope.ex`

- [ ] **Step 1: Create the on_mount hook**

This hook reads `:client_slug` from params, resolves the client, and assigns it. All scoped admin LiveViews will use this.

```elixir
defmodule HubWeb.ClientScope do
  import Phoenix.LiveView
  import Phoenix.Component

  alias Hub.Clients

  def on_mount(:default, %{"client_slug" => slug}, _session, socket) do
    case Clients.get_client_by_slug(slug) do
      nil ->
        {:halt, push_navigate(socket, to: "/admin/clients")}

      client ->
        {:cont, assign(socket, :current_client, client)}
    end
  end

  def on_mount(:default, _params, _session, socket) do
    {:cont, socket}
  end
end
```

- [ ] **Step 2: Commit**

```bash
git add lib/hub_web/live/client_scope.ex
git commit -m "feat(admin): add ClientScope on_mount hook"
```

---

### Task 4: Restructure admin routes

**Files:**
- Modify: `lib/hub_web/router.ex`

- [ ] **Step 1: Update admin routes**

Replace the entire admin scope in `lib/hub_web/router.ex`:

```elixir
  # Admin routes (authenticated)
  scope "/admin", HubWeb.Admin do
    pipe_through [:browser, :require_auth]

    # Client selection — no client context needed
    live_session :admin_clients,
      on_mount: [{HubWeb.AdminNav, :default}],
      layout: {HubWeb.Layouts, :app} do
      live "/clients", ClientLive.Index, :index
    end

    # Scoped admin pages — require client context
    live_session :admin,
      on_mount: [{HubWeb.AdminNav, :default}, {HubWeb.ClientScope, :default}],
      layout: {HubWeb.Layouts, :admin} do
      live "/clients/:client_slug/organizations", OrganizationLive.Index, :index
      live "/clients/:client_slug/organizations/:id", OrganizationLive.Show, :show
      live "/clients/:client_slug/accounts", AccountLive.Index, :index
      live "/clients/:client_slug/accounts/:id", AccountLive.Show, :show
      live "/clients/:client_slug/contacts", ContactLive.Index, :index
      live "/clients/:client_slug/notifications", NotificationLive.Index, :index
      live "/clients/:client_slug/workflows", WorkflowLive.Index, :index
      live "/clients/:client_slug/settings", ClientSettingsLive.Index, :index
    end

    import Dai.Router

    dai_dashboard("/clients/:client_slug/explore",
      layout: {HubWeb.Layouts, :admin},
      on_mount: [{HubWeb.AdminNav, :default}, {HubWeb.ClientScope, :default}]
    )
  end

  # API routes (authenticated via API key)
  scope "/api/v1/clients/:client_id", HubWeb.API.V1 do
    pipe_through [:api, :require_api_key]

    resources "/organizations", OrganizationController, only: [:index, :show, :create, :update] do
      resources "/accounts", AccountController, only: [:index, :create]
    end

    resources "/accounts", AccountController, only: [:update] do
      resources "/contacts", ContactController, only: [:index, :create]
    end

    resources "/contacts", ContactController, only: [:update]
    resources "/notifications", NotificationController, only: [:index, :create]
  end
```

- [ ] **Step 2: Redirect old /admin root to /admin/clients**

In the public routes scope, add a redirect so `/admin` goes to `/admin/clients`:

```elixir
  # Public routes
  scope "/", HubWeb do
    pipe_through :browser

    get "/", PageController, :home
    get "/admin", PageController, :admin_redirect
  end
```

In `lib/hub_web/controllers/page_controller.ex`, add:

```elixir
def admin_redirect(conn, _params) do
  redirect(conn, to: ~p"/admin/clients")
end
```

- [ ] **Step 3: Update post-login redirect**

In `lib/hub_web/controllers/auth_controller.ex`, change the redirect after login:

```elixir
# Change:
|> redirect(to: ~p"/admin/organizations")
# To:
|> redirect(to: ~p"/admin/clients")
```

In `lib/hub_web/controllers/page_controller.ex`, update the home redirect (if it redirects to `/admin/organizations`):

```elixir
# Change:
redirect(conn, to: ~p"/admin/organizations")
# To:
redirect(conn, to: ~p"/admin/clients")
```

- [ ] **Step 4: Verify compilation**

```bash
mix compile --warnings-as-errors
```

Expected: compiles (may have warnings about unused assigns — we'll fix those in next tasks).

- [ ] **Step 5: Commit**

```bash
git add lib/hub_web/router.ex lib/hub_web/controllers/page_controller.ex lib/hub_web/controllers/auth_controller.ex
git commit -m "feat(admin): restructure routes under client scope"
```

---

### Task 5: Update admin layout sidebar for client context

**Files:**
- Modify: `lib/hub_web/components/layouts/admin.html.heex`
- Modify: `lib/hub_web/components/layouts.ex`

- [ ] **Step 1: Update admin layout template**

Replace `lib/hub_web/components/layouts/admin.html.heex` with client-aware version. The `@current_client` assign is set by the `ClientScope` on_mount hook.

```heex
<div class="flex h-screen bg-base-200">
  <aside class="hidden w-64 flex-shrink-0 border-r border-base-300 bg-base-100 md:block">
    <div class="flex h-full flex-col">
      <div class="flex h-16 items-center justify-between border-b border-base-300 px-6">
        <span class="text-xl font-bold text-base-content">Hub</span>
      </div>
      <div class="border-b border-base-300 px-4 py-3">
        <.link navigate={~p"/admin/clients"} class="flex items-center gap-2 text-sm text-base-content/60 hover:text-base-content">
          <.icon name="hero-arrow-left" class="size-3" />
          Switch Client
        </.link>
        <p class="mt-1 text-sm font-semibold text-base-content truncate">{@current_client.name}</p>
      </div>
      <nav class="flex-1 space-y-1 px-3 py-4">
        <.nav_link
          path={~p"/admin/clients/#{@current_client.slug}/organizations"}
          current={@current_path}
          label="Organizations"
          icon="hero-building-office-2"
        />
        <.nav_link
          path={~p"/admin/clients/#{@current_client.slug}/accounts"}
          current={@current_path}
          label="Accounts"
          icon="hero-user-group"
        />
        <.nav_link
          path={~p"/admin/clients/#{@current_client.slug}/contacts"}
          current={@current_path}
          label="Contacts"
          icon="hero-users"
        />
        <.nav_link
          path={~p"/admin/clients/#{@current_client.slug}/notifications"}
          current={@current_path}
          label="Notifications"
          icon="hero-bell"
        />
        <.nav_link
          path={~p"/admin/clients/#{@current_client.slug}/workflows"}
          current={@current_path}
          label="Workflows"
          icon="hero-arrow-path"
        />
        <.nav_link
          path={~p"/admin/clients/#{@current_client.slug}/explore"}
          current={@current_path}
          label="Explore"
          icon="hero-magnifying-glass"
        />
        <.nav_link
          path={~p"/admin/clients/#{@current_client.slug}/settings"}
          current={@current_path}
          label="Settings"
          icon="hero-cog-6-tooth"
        />
      </nav>
      <div class="border-t border-base-300 p-4">
        <.link
          href={~p"/auth/logout"}
          method="delete"
          class="text-sm text-base-content/50 hover:text-base-content/80"
        >
          Sign out
        </.link>
      </div>
    </div>
  </aside>

  <div class="flex flex-1 flex-col overflow-hidden">
    <main class="flex-1 overflow-y-auto p-6">
      <.flash_group flash={@flash} />
      {@inner_content}
    </main>
  </div>
</div>
```

- [ ] **Step 2: Commit**

```bash
git add lib/hub_web/components/layouts/admin.html.heex
git commit -m "feat(admin): add client context to admin sidebar"
```

---

### Task 6: Scope admin LiveViews to current client

**Files:**
- Modify: `lib/hub_web/live/admin/organization_live/index.ex`
- Modify: `lib/hub_web/live/admin/organization_live/show.ex`
- Modify: `lib/hub_web/live/admin/account_live/index.ex`
- Modify: `lib/hub_web/live/admin/account_live/show.ex`
- Modify: `lib/hub_web/live/admin/contact_live/index.ex`
- Modify: `lib/hub_web/live/admin/notification_live/index.ex`
- Modify: `lib/hub_web/live/admin/workflow_live/index.ex`

All admin LiveViews need to use `@current_client` (set by the `ClientScope` on_mount hook) to scope their queries.

- [ ] **Step 1: Update OrganizationLive.Index**

Replace `list_organizations/1` to use `@current_client.id`:

```elixir
defmodule HubWeb.Admin.OrganizationLive.Index do
  use HubWeb, :live_view

  alias Hub.CRM

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, search: "", filter: :all)}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    orgs = list_organizations(socket.assigns)
    {:noreply, stream(socket, :organizations, orgs, reset: true)}
  end

  @impl true
  def handle_event("search", %{"search" => search}, socket) do
    socket = assign(socket, search: search)
    {:noreply, stream(socket, :organizations, list_organizations(socket.assigns), reset: true)}
  end

  @impl true
  def handle_event("filter", %{"filter" => filter}, socket) do
    socket = assign(socket, filter: String.to_existing_atom(filter))
    {:noreply, stream(socket, :organizations, list_organizations(socket.assigns), reset: true)}
  end

  @impl true
  def handle_event("approve", %{"id" => id}, socket) do
    CRM.get_organization!(id) |> CRM.approve_organization()
    {:noreply, stream(socket, :organizations, list_organizations(socket.assigns), reset: true)}
  end

  defp list_organizations(%{current_client: client, search: search, filter: filter}) do
    opts = [{:archived, false}]
    opts = if search != "", do: [{:search, search} | opts], else: opts

    opts =
      case filter do
        :approved -> [{:approved, true} | opts]
        :pending -> [{:approved, false} | opts]
        _ -> opts
      end

    CRM.list_organizations(client.id, opts)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <div class="mb-6 flex items-center justify-between">
        <h1 class="text-2xl font-bold text-base-content">Organizations</h1>
      </div>

      <div class="mb-4 flex gap-4">
        <form phx-change="search" class="flex-1">
          <.input
            type="text"
            name="search"
            value={@search}
            placeholder="Search organizations..."
            phx-debounce="300"
          />
        </form>
        <form phx-change="filter">
          <select name="filter" class="select select-bordered select-sm">
            <option value="all" selected={@filter == :all}>All</option>
            <option value="approved" selected={@filter == :approved}>Approved</option>
            <option value="pending" selected={@filter == :pending}>Pending</option>
          </select>
        </form>
      </div>

      <div class="overflow-hidden rounded-lg border border-base-300 bg-base-100">
        <table class="table">
          <thead>
            <tr>
              <th>Name</th>
              <th>Status</th>
              <th>Detections</th>
              <th class="text-right">Actions</th>
            </tr>
          </thead>
          <tbody id="organizations" phx-update="stream">
            <tr :for={{id, org} <- @streams.organizations} id={id}>
              <td>
                <.link
                  navigate={~p"/admin/clients/#{@current_client.slug}/organizations/#{org.id}"}
                  class="font-medium text-primary hover:underline"
                >
                  {org.name}
                </.link>
              </td>
              <td>
                <span class={[
                  "badge badge-sm",
                  if(org.approved, do: "badge-success", else: "badge-warning")
                ]}>
                  {if org.approved, do: "Approved", else: "Pending"}
                </span>
              </td>
              <td class="text-base-content/60">{org.detection_count}</td>
              <td class="text-right">
                <button
                  :if={!org.approved}
                  phx-click="approve"
                  phx-value-id={org.id}
                  class="text-sm text-success hover:underline"
                >
                  Approve
                </button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
    """
  end
end
```

- [ ] **Step 2: Update OrganizationLive.Show**

```elixir
defmodule HubWeb.Admin.OrganizationLive.Show do
  use HubWeb, :live_view

  alias Hub.CRM

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    org = CRM.get_organization!(id)
    accounts = CRM.list_accounts(org.id)
    {:ok, assign(socket, organization: org, accounts: accounts)}
  end

  @impl true
  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <div class="mb-6">
        <.link
          navigate={~p"/admin/clients/#{@current_client.slug}/organizations"}
          class="text-sm text-base-content/50 hover:text-base-content/80"
        >
          &larr; Back
        </.link>
      </div>
      <div class="mb-6 flex items-center justify-between">
        <h1 class="text-2xl font-bold text-base-content">{@organization.name}</h1>
        <span class={[
          "badge",
          if(@organization.approved, do: "badge-success", else: "badge-warning")
        ]}>
          {if @organization.approved, do: "Approved", else: "Pending"}
        </span>
      </div>
      <div class="mb-8 grid grid-cols-3 gap-4">
        <div class="rounded-lg border border-base-300 bg-base-100 p-4">
          <p class="text-sm text-base-content/60">Detections</p>
          <p class="text-2xl font-bold">{@organization.detection_count}</p>
        </div>
        <div class="rounded-lg border border-base-300 bg-base-100 p-4">
          <p class="text-sm text-base-content/60">Accounts</p>
          <p class="text-2xl font-bold">{length(@accounts)}</p>
        </div>
      </div>
      <h2 class="mb-4 text-lg font-semibold text-base-content">Accounts</h2>
      <div class="overflow-hidden rounded-lg border border-base-300 bg-base-100">
        <table class="table">
          <thead>
            <tr>
              <th>Name</th>
              <th>Region</th>
              <th>Status</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={account <- @accounts}>
              <td>
                <.link
                  navigate={~p"/admin/clients/#{@current_client.slug}/accounts/#{account.id}"}
                  class="font-medium text-primary hover:underline"
                >
                  {account.name}
                </.link>
              </td>
              <td class="text-base-content/60">{account.geographic_region || "—"}</td>
              <td class="text-base-content/60">{account.relationship_status}</td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
    """
  end
end
```

- [ ] **Step 3: Update AccountLive.Index**

Add client scoping via join through organization:

```elixir
defmodule HubWeb.Admin.AccountLive.Index do
  use HubWeb, :live_view

  import Ecto.Query
  alias Hub.Repo
  alias Hub.CRM.Account

  @impl true
  def mount(_params, _session, socket), do: {:ok, assign(socket, search: "")}

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, stream(socket, :accounts, list_accounts(socket.assigns), reset: true)}
  end

  @impl true
  def handle_event("search", %{"search" => search}, socket) do
    {:noreply,
     socket |> assign(search: search) |> stream(:accounts, list_accounts(socket.assigns |> Map.put(:search, search)), reset: true)}
  end

  defp list_accounts(%{current_client: client, search: search}) do
    Account
    |> join(:inner, [a], o in assoc(a, :organization))
    |> where([a, o], o.client_id == ^client.id)
    |> order_by(:name)
    |> preload(:organization)
    |> then(fn q ->
      if search != "", do: where(q, [a], ilike(a.name, ^"%#{search}%")), else: q
    end)
    |> Repo.all()
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <h1 class="mb-6 text-2xl font-bold text-base-content">Accounts</h1>
      <div class="mb-4">
        <form phx-change="search">
          <.input
            type="text"
            name="search"
            value={@search}
            placeholder="Search accounts..."
            phx-debounce="300"
          />
        </form>
      </div>
      <div class="overflow-hidden rounded-lg border border-base-300 bg-base-100">
        <table class="table">
          <thead>
            <tr>
              <th>Name</th>
              <th>Organization</th>
              <th>Region</th>
              <th>Status</th>
            </tr>
          </thead>
          <tbody id="accounts" phx-update="stream">
            <tr :for={{id, account} <- @streams.accounts} id={id}>
              <td>
                <.link
                  navigate={~p"/admin/clients/#{@current_client.slug}/accounts/#{account.id}"}
                  class="font-medium text-primary hover:underline"
                >
                  {account.name}
                </.link>
              </td>
              <td class="text-base-content/60">{account.organization.name}</td>
              <td class="text-base-content/60">{account.geographic_region || "—"}</td>
              <td class="text-base-content/60">{account.relationship_status}</td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
    """
  end
end
```

- [ ] **Step 4: Update AccountLive.Show**

```elixir
defmodule HubWeb.Admin.AccountLive.Show do
  use HubWeb, :live_view

  alias Hub.CRM

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    account = CRM.get_account!(id) |> Hub.Repo.preload([:organization, :contacts, :notifications])
    {:ok, assign(socket, account: account)}
  end

  @impl true
  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <div class="mb-6">
        <.link
          navigate={~p"/admin/clients/#{@current_client.slug}/accounts"}
          class="text-sm text-base-content/50 hover:text-base-content/80"
        >
          &larr; Back
        </.link>
      </div>
      <h1 class="mb-6 text-2xl font-bold text-base-content">{@account.name}</h1>
      <div class="mb-8 grid grid-cols-4 gap-4">
        <div class="rounded-lg border border-base-300 bg-base-100 p-4">
          <p class="text-sm text-base-content/60">Organization</p>
          <p class="font-medium">{@account.organization.name}</p>
        </div>
        <div class="rounded-lg border border-base-300 bg-base-100 p-4">
          <p class="text-sm text-base-content/60">Region</p>
          <p class="font-medium">{@account.geographic_region || "—"}</p>
        </div>
        <div class="rounded-lg border border-base-300 bg-base-100 p-4">
          <p class="text-sm text-base-content/60">Status</p>
          <p class="font-medium">{@account.relationship_status}</p>
        </div>
        <div class="rounded-lg border border-base-300 bg-base-100 p-4">
          <p class="text-sm text-base-content/60">Contact</p>
          <p class="font-medium">{@account.contact_email || "—"}</p>
        </div>
      </div>
      <h2 class="mb-4 text-lg font-semibold">Contacts ({length(@account.contacts)})</h2>
      <div class="overflow-hidden rounded-lg border border-base-300 bg-base-100">
        <table class="table">
          <thead>
            <tr>
              <th>Name</th>
              <th>Email</th>
              <th>Status</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={contact <- @account.contacts}>
              <td>{contact.contact_name}</td>
              <td class="text-base-content/60">{contact.contact_email}</td>
              <td class="text-base-content/60">{contact.status}</td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
    """
  end
end
```

- [ ] **Step 5: Update ContactLive.Index**

Add client scoping through the join chain `contacts → accounts → organizations`:

```elixir
defmodule HubWeb.Admin.ContactLive.Index do
  use HubWeb, :live_view

  import Ecto.Query
  alias Hub.Repo
  alias Hub.CRM.Contact

  @impl true
  def mount(_params, _session, socket), do: {:ok, assign(socket, search: "", status_filter: nil)}

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, stream(socket, :contacts, list_contacts(socket.assigns), reset: true)}
  end

  @impl true
  def handle_event("search", %{"search" => search}, socket) do
    socket = assign(socket, search: search)
    {:noreply, stream(socket, :contacts, list_contacts(socket.assigns), reset: true)}
  end

  @impl true
  def handle_event("filter", %{"status" => status}, socket) do
    socket = assign(socket, status_filter: if(status == "", do: nil, else: status))
    {:noreply, stream(socket, :contacts, list_contacts(socket.assigns), reset: true)}
  end

  defp list_contacts(%{current_client: client, search: search, status_filter: status}) do
    Contact
    |> join(:inner, [c], a in assoc(c, :account))
    |> join(:inner, [c, a], o in assoc(a, :organization))
    |> where([c, a, o], o.client_id == ^client.id)
    |> then(fn q -> if search != "", do: where(q, [c], ilike(c.contact_name, ^"%#{search}%") or ilike(c.contact_email, ^"%#{search}%")), else: q end)
    |> then(fn q -> if status, do: where(q, [c], c.status == ^status), else: q end)
    |> order_by([c], desc: c.inserted_at)
    |> Repo.all()
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <h1 class="mb-6 text-2xl font-bold text-base-content">Contacts</h1>
      <div class="mb-4 flex gap-4">
        <form phx-change="search" class="flex-1">
          <.input type="text" name="search" value={@search} placeholder="Search contacts..." phx-debounce="300" />
        </form>
        <form phx-change="filter">
          <select name="status" class="select select-bordered select-sm">
            <option value="">All</option>
            <option value="new" selected={@status_filter == "new"}>New</option>
            <option value="contacted" selected={@status_filter == "contacted"}>Contacted</option>
            <option value="converted" selected={@status_filter == "converted"}>Converted</option>
            <option value="dismissed" selected={@status_filter == "dismissed"}>Dismissed</option>
          </select>
        </form>
      </div>
      <div class="overflow-hidden rounded-lg border border-base-300 bg-base-100">
        <table class="table">
          <thead>
            <tr>
              <th>Name</th>
              <th>Email</th>
              <th>Status</th>
              <th>Score</th>
            </tr>
          </thead>
          <tbody id="contacts" phx-update="stream">
            <tr :for={{id, contact} <- @streams.contacts} id={id}>
              <td class="font-medium">{contact.contact_name}</td>
              <td class="text-base-content/60">{contact.contact_email}</td>
              <td><span class={["badge badge-sm", status_badge(contact.status)]}>{contact.status}</span></td>
              <td class="text-base-content/60">{contact.lead_score}</td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  defp status_badge("new"), do: "badge-info"
  defp status_badge("contacted"), do: "badge-warning"
  defp status_badge("converted"), do: "badge-success"
  defp status_badge("dismissed"), do: "badge-ghost"
  defp status_badge(_), do: "badge-ghost"
end
```

- [ ] **Step 6: Update NotificationLive.Index**

```elixir
defmodule HubWeb.Admin.NotificationLive.Index do
  use HubWeb, :live_view

  import Ecto.Query
  alias Hub.Repo
  alias Hub.CRM.Notification

  @impl true
  def mount(_params, _session, socket), do: {:ok, assign(socket, status_filter: nil)}

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, stream(socket, :notifications, list_notifications(socket.assigns), reset: true)}
  end

  @impl true
  def handle_event("filter", %{"status" => status}, socket) do
    socket = assign(socket, status_filter: if(status == "", do: nil, else: status))
    {:noreply, stream(socket, :notifications, list_notifications(socket.assigns), reset: true)}
  end

  defp list_notifications(%{current_client: client, status_filter: status}) do
    Notification
    |> join(:inner, [n], a in assoc(n, :account))
    |> join(:inner, [n, a], o in assoc(a, :organization))
    |> where([n, a, o], o.client_id == ^client.id)
    |> then(fn q -> if status, do: where(q, [n], n.status == ^status), else: q end)
    |> order_by([n], desc: n.inserted_at)
    |> Repo.all()
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <h1 class="mb-6 text-2xl font-bold text-base-content">Notifications</h1>
      <div class="mb-4">
        <form phx-change="filter">
          <select name="status" class="select select-bordered select-sm">
            <option value="">All</option>
            <option value="pending" selected={@status_filter == "pending"}>Pending</option>
            <option value="sent" selected={@status_filter == "sent"}>Sent</option>
            <option value="delivered" selected={@status_filter == "delivered"}>Delivered</option>
            <option value="bounced" selected={@status_filter == "bounced"}>Bounced</option>
            <option value="failed" selected={@status_filter == "failed"}>Failed</option>
          </select>
        </form>
      </div>
      <div class="overflow-hidden rounded-lg border border-base-300 bg-base-100">
        <table class="table">
          <thead>
            <tr>
              <th>Subject</th>
              <th>Recipient</th>
              <th>Status</th>
              <th>Sent</th>
            </tr>
          </thead>
          <tbody id="notifications" phx-update="stream">
            <tr :for={{id, n} <- @streams.notifications} id={id}>
              <td class="font-medium">{n.subject}</td>
              <td class="text-base-content/60">{n.recipient_email || "—"}</td>
              <td><span class={["badge badge-sm", notif_badge(n.status)]}>{n.status}</span></td>
              <td class="text-base-content/60">
                {if n.sent_at, do: Calendar.strftime(n.sent_at, "%Y-%m-%d %H:%M"), else: "—"}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  defp notif_badge("pending"), do: "badge-warning"
  defp notif_badge("sent"), do: "badge-info"
  defp notif_badge("delivered"), do: "badge-success"
  defp notif_badge("bounced"), do: "badge-error"
  defp notif_badge("failed"), do: "badge-error"
  defp notif_badge(_), do: "badge-ghost"
end
```

- [ ] **Step 7: Update WorkflowLive.Index**

```elixir
defmodule HubWeb.Admin.WorkflowLive.Index do
  use HubWeb, :live_view

  import Ecto.Query
  alias Hub.Repo
  alias Hub.CRM.Workflow

  @impl true
  def mount(_params, _session, socket), do: {:ok, assign(socket, status_filter: nil)}

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, stream(socket, :workflows, list_workflows(socket.assigns), reset: true)}
  end

  @impl true
  def handle_event("filter", %{"status" => status}, socket) do
    socket = assign(socket, status_filter: if(status == "", do: nil, else: status))
    {:noreply, stream(socket, :workflows, list_workflows(socket.assigns), reset: true)}
  end

  defp list_workflows(%{current_client: client, status_filter: status}) do
    Workflow
    |> join(:inner, [w], a in assoc(w, :account))
    |> join(:inner, [w, a], o in assoc(a, :organization))
    |> where([w, a, o], o.client_id == ^client.id)
    |> then(fn q -> if status, do: where(q, [w], w.status == ^status), else: q end)
    |> order_by([w], desc: w.inserted_at)
    |> preload(:account)
    |> Repo.all()
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <h1 class="mb-6 text-2xl font-bold text-base-content">Workflows</h1>
      <div class="mb-4">
        <form phx-change="filter">
          <select name="status" class="select select-bordered select-sm">
            <option value="">All</option>
            <option value="pending" selected={@status_filter == "pending"}>Pending</option>
            <option value="in_progress" selected={@status_filter == "in_progress"}>In Progress</option>
            <option value="completed" selected={@status_filter == "completed"}>Completed</option>
            <option value="cancelled" selected={@status_filter == "cancelled"}>Cancelled</option>
          </select>
        </form>
      </div>
      <div class="overflow-hidden rounded-lg border border-base-300 bg-base-100">
        <table class="table">
          <thead>
            <tr>
              <th>Account</th>
              <th>Step</th>
              <th>Status</th>
              <th>Last Activity</th>
            </tr>
          </thead>
          <tbody id="workflows" phx-update="stream">
            <tr :for={{id, wf} <- @streams.workflows} id={id}>
              <td class="font-medium">{wf.account.name}</td>
              <td>Step {wf.current_step} of 5</td>
              <td><span class={["badge badge-sm", wf_badge(wf.status)]}>{wf.status}</span></td>
              <td class="text-base-content/60">
                {if wf.last_activity_at, do: Calendar.strftime(wf.last_activity_at, "%Y-%m-%d %H:%M"), else: "—"}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  defp wf_badge("pending"), do: "badge-warning"
  defp wf_badge("in_progress"), do: "badge-info"
  defp wf_badge("completed"), do: "badge-success"
  defp wf_badge("cancelled"), do: "badge-ghost"
  defp wf_badge(_), do: "badge-ghost"
end
```

- [ ] **Step 8: Verify compilation**

```bash
mix compile --warnings-as-errors
```

- [ ] **Step 9: Commit**

```bash
git add lib/hub_web/live/admin/
git commit -m "feat(admin): scope all LiveViews to current client"
```

---

### Task 7: Update API controllers for client-scoped routes

**Files:**
- Modify: `lib/hub_web/plugs/require_api_key.ex`
- Modify: `lib/hub_web/controllers/api/v1/organization_controller.ex`
- Modify: `lib/hub_web/controllers/api/v1/account_controller.ex`
- Modify: `lib/hub_web/controllers/api/v1/contact_controller.ex`
- Modify: `lib/hub_web/controllers/api/v1/notification_controller.ex`

- [ ] **Step 1: Add client_id verification to RequireApiKey plug**

After authenticating the key, verify the key's client matches the `:client_id` URL param:

```elixir
defmodule HubWeb.Plugs.RequireApiKey do
  @moduledoc """
  Plug that authenticates API requests via Bearer token.
  Assigns `current_client` on success, returns 401/403 on failure.
  """

  import Plug.Conn
  alias Hub.Clients

  def init(opts), do: opts

  def call(conn, _opts) do
    with ["Bearer " <> raw_key] <- get_req_header(conn, "authorization"),
         {:ok, client} <- Clients.authenticate_key(raw_key),
         :ok <- verify_client_scope(conn, client) do
      assign(conn, :current_client, client)
    else
      {:error, :client_mismatch} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(403, Jason.encode!(%{error: "forbidden"}))
        |> halt()

      _ ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(401, Jason.encode!(%{error: "unauthorized"}))
        |> halt()
    end
  end

  defp verify_client_scope(conn, client) do
    case conn.params["client_id"] do
      nil -> :ok
      client_id when client_id == client.id -> :ok
      _ -> {:error, :client_mismatch}
    end
  end
end
```

- [ ] **Step 2: Update OrganizationController**

The client_id now comes from the URL params (already verified by the plug):

```elixir
defmodule HubWeb.API.V1.OrganizationController do
  use HubWeb, :controller

  alias Hub.CRM

  action_fallback HubWeb.FallbackController

  def index(conn, %{"client_id" => client_id} = params) do
    opts = []
    opts = if params["approved"], do: [{:approved, params["approved"]} | opts], else: opts
    opts = if params["search"], do: [{:search, params["search"]} | opts], else: opts

    organizations = CRM.list_organizations(client_id, opts)
    render(conn, :index, organizations: organizations)
  end

  def show(conn, %{"id" => id}) do
    organization = CRM.get_organization!(id)
    render(conn, :show, organization: organization)
  end

  def create(conn, %{"client_id" => client_id, "name" => name} = params) do
    case CRM.upsert_organization(client_id, name, Map.take(params, ~w(notes))) do
      {:ok, %{detection_count: 0} = org} ->
        conn |> put_status(:created) |> render(:show, organization: org)

      {:ok, org} ->
        render(conn, :show, organization: org)
    end
  end

  def update(conn, %{"id" => id} = params) do
    org = CRM.get_organization!(id)
    attrs = Map.take(params, ~w(approved notes))

    with {:ok, updated} <- CRM.update_organization(org, attrs) do
      render(conn, :show, organization: updated)
    end
  end
end
```

- [ ] **Step 3: AccountController, ContactController, NotificationController remain mostly the same**

These controllers already get their scoping through the nested resource URL (`organization_id`, `account_id`). The `client_id` in the URL is verified by the plug. No code changes needed beyond accepting the `client_id` param that Phoenix passes through.

Verify they compile:

```bash
mix compile --warnings-as-errors
```

- [ ] **Step 4: Commit**

```bash
git add lib/hub_web/plugs/require_api_key.ex lib/hub_web/controllers/api/v1/
git commit -m "feat(api): scope API routes under client_id with key verification"
```

---

### Task 8: Update API tests

**Files:**
- Modify: `test/hub_web/controllers/api/v1/organization_controller_test.exs`
- Modify: `test/hub_web/controllers/api/v1/account_controller_test.exs`
- Modify: `test/hub_web/controllers/api/v1/contact_controller_test.exs`
- Modify: `test/hub_web/controllers/api/v1/notification_controller_test.exs`

- [ ] **Step 1: Update organization controller test**

Update all route paths to include `client_id`:

```elixir
defmodule HubWeb.API.V1.OrganizationControllerTest do
  use HubWeb.ConnCase

  import Hub.ClientsFixtures
  import Hub.CRMFixtures

  setup do
    client = client_fixture()
    {:ok, _api_key, raw_key} = Hub.Clients.create_api_key(client)

    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer #{raw_key}")
      |> put_req_header("content-type", "application/json")

    %{conn: conn, client: client}
  end

  describe "index" do
    test "lists organizations for the authenticated client", %{conn: conn, client: client} do
      organization_fixture(%{client: client, name: "TestOrg"})
      conn = get(conn, ~p"/api/v1/clients/#{client.id}/organizations")
      assert [%{"name" => "TestOrg"}] = json_response(conn, 200)["data"]
    end

    test "does not list other clients' organizations", %{conn: conn, client: client} do
      organization_fixture(%{name: "OtherOrg"})
      conn = get(conn, ~p"/api/v1/clients/#{client.id}/organizations")
      assert [] = json_response(conn, 200)["data"]
    end

    test "returns 403 when client_id does not match API key", %{conn: conn} do
      other_client = client_fixture(%{name: "Other"})
      conn = get(conn, ~p"/api/v1/clients/#{other_client.id}/organizations")
      assert json_response(conn, 403)["error"] == "forbidden"
    end
  end

  describe "create" do
    test "creates organization", %{conn: conn, client: client} do
      conn = post(conn, ~p"/api/v1/clients/#{client.id}/organizations", %{name: "NewOrg"})
      assert %{"name" => "NewOrg"} = json_response(conn, 201)["data"]
    end

    test "upserts when name exists", %{conn: conn, client: client} do
      organization_fixture(%{client: client, name: "Existing"})
      conn = post(conn, ~p"/api/v1/clients/#{client.id}/organizations", %{name: "Existing"})
      assert %{"name" => "Existing", "detection_count" => 1} = json_response(conn, 200)["data"]
    end
  end

  describe "update" do
    test "updates organization", %{conn: conn, client: client} do
      org = organization_fixture(%{client: client})
      conn = patch(conn, ~p"/api/v1/clients/#{client.id}/organizations/#{org.id}", %{approved: true})
      assert %{"approved" => true} = json_response(conn, 200)["data"]
    end
  end
end
```

- [ ] **Step 2: Update account, contact, notification controller tests similarly**

Update all `~p"/api/v1/organizations/..."` paths to `~p"/api/v1/clients/#{client.id}/organizations/..."` in each test file. The pattern is the same — prepend `/clients/#{client.id}` to every route.

- [ ] **Step 3: Run all tests**

```bash
mix test test/hub_web/controllers/api/v1/
```

Expected: all tests pass.

- [ ] **Step 4: Commit**

```bash
git add test/hub_web/controllers/api/v1/
git commit -m "test(api): update API tests for client-scoped routes"
```

---

### Task 9: Client Settings LiveView

**Files:**
- Create: `lib/hub_web/live/admin/client_settings_live/index.ex`

- [ ] **Step 1: Create the settings LiveView**

```elixir
defmodule HubWeb.Admin.ClientSettingsLive.Index do
  use HubWeb, :live_view

  alias Hub.Clients

  @impl true
  def mount(_params, _session, socket) do
    client = socket.assigns.current_client
    api_keys = Hub.Repo.preload(client, :api_keys).api_keys

    {:ok,
     assign(socket,
       form: to_form(Clients.Client.changeset(client, %{})),
       api_keys: api_keys,
       new_raw_key: nil,
       show_delete_confirm: false
     )}
  end

  @impl true
  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  @impl true
  def handle_event("save", %{"client" => attrs}, socket) do
    case Clients.update_client(socket.assigns.current_client, attrs) do
      {:ok, client} ->
        {:noreply,
         socket
         |> assign(current_client: client, form: to_form(Clients.Client.changeset(client, %{})))
         |> put_flash(:info, "Client updated")}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  @impl true
  def handle_event("generate-key", _params, socket) do
    {:ok, api_key, raw_key} = Clients.create_api_key(socket.assigns.current_client)
    api_keys = [api_key | socket.assigns.api_keys]
    {:noreply, assign(socket, api_keys: api_keys, new_raw_key: raw_key)}
  end

  @impl true
  def handle_event("dismiss-key", _params, socket) do
    {:noreply, assign(socket, new_raw_key: nil)}
  end

  @impl true
  def handle_event("confirm-delete", _params, socket) do
    {:noreply, assign(socket, show_delete_confirm: true)}
  end

  @impl true
  def handle_event("cancel-delete", _params, socket) do
    {:noreply, assign(socket, show_delete_confirm: false)}
  end

  @impl true
  def handle_event("delete-client", _params, socket) do
    {:ok, _} = Clients.delete_client(socket.assigns.current_client)
    {:noreply, push_navigate(socket, to: ~p"/admin/clients")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-2xl">
      <h1 class="mb-6 text-2xl font-bold text-base-content">Client Settings</h1>

      <div class="rounded-lg border border-base-300 bg-base-100 p-6 mb-6">
        <h2 class="text-lg font-semibold mb-4">General</h2>
        <.form for={@form} phx-submit="save">
          <.input field={@form[:name]} label="Name" />
          <div class="mt-4">
            <button type="submit" class="btn btn-primary btn-sm">Save</button>
          </div>
        </.form>
      </div>

      <div class="rounded-lg border border-base-300 bg-base-100 p-6 mb-6">
        <div class="flex items-center justify-between mb-4">
          <h2 class="text-lg font-semibold">API Keys</h2>
          <button phx-click="generate-key" class="btn btn-sm btn-outline">Generate Key</button>
        </div>

        <div :if={@new_raw_key} class="mb-4 rounded-lg border border-warning/50 bg-warning/10 p-4">
          <p class="text-sm font-medium text-warning mb-2">
            Copy this key now — it won't be shown again:
          </p>
          <code class="text-xs break-all select-all">{@new_raw_key}</code>
          <button phx-click="dismiss-key" class="btn btn-ghost btn-xs mt-2">Dismiss</button>
        </div>

        <div :if={@api_keys == []} class="text-sm text-base-content/40">No API keys</div>
        <div :for={key <- @api_keys} class="flex items-center justify-between py-2 border-b border-base-200 last:border-0">
          <div>
            <span class="text-sm font-mono text-base-content/60">{key.label || "unlabeled"}</span>
            <span :if={key.last_used_at} class="text-xs text-base-content/40 ml-2">
              Last used: {Calendar.strftime(key.last_used_at, "%Y-%m-%d %H:%M")}
            </span>
          </div>
        </div>
      </div>

      <div class="rounded-lg border border-error/30 bg-error/5 p-6">
        <h2 class="text-lg font-semibold text-error mb-2">Danger Zone</h2>
        <p class="text-sm text-base-content/60 mb-4">
          Deleting this client will permanently remove all its organizations, accounts, contacts, notifications, and workflows.
        </p>
        <button :if={!@show_delete_confirm} phx-click="confirm-delete" class="btn btn-error btn-sm btn-outline">
          Delete Client
        </button>
        <div :if={@show_delete_confirm} class="flex gap-2">
          <button phx-click="delete-client" class="btn btn-error btn-sm">Yes, delete everything</button>
          <button phx-click="cancel-delete" class="btn btn-ghost btn-sm">Cancel</button>
        </div>
      </div>
    </div>
    """
  end
end
```

- [ ] **Step 2: Verify compilation and run**

```bash
mix compile --warnings-as-errors
```

- [ ] **Step 3: Commit**

```bash
git add lib/hub_web/live/admin/client_settings_live/index.ex
git commit -m "feat(admin): add client settings page"
```

---

### Task 10: Dai query scoping feature (Dai repo)

This task produces a prompt for modifying the Dai repo. The changes should be made in the Dai dependency.

**Files (in Dai repo):**
- Modify: `lib/dai/config.ex`
- Modify: `lib/dai/router.ex`
- Modify: `lib/dai/dashboard_live.ex`
- Modify: `lib/dai/ai/system_prompt.ex`
- Modify: `lib/dai/ai/query_pipeline.ex`
- Modify: `lib/dai/ai/plan_validator.ex`

**Prompt for Dai changes:**

> Add a generic query scoping feature to Dai. This allows host apps to configure a mandatory WHERE clause that Claude must include in every generated SQL query.
>
> **1. Config (`lib/dai/config.ex`):** Add two new functions:
> - `query_scope/0` — reads `Application.get_env(:dai, :query_scope)`, returns `nil` if not configured. Expected shape: `%{column: "client_id", table: "organizations", description: "..."}`
> - No `scope_value` in config — the runtime value is passed through the session.
>
> **2. Router (`lib/dai/router.ex`):** Add a new `scope_value` option to `dai_dashboard/2`. This is a function `fn(session) -> value` that extracts the runtime scope value. Pass it through the session map under key `"dai_scope_value"`, same pattern as `user_token`.
>
> **3. DashboardLive (`lib/dai/dashboard_live.ex`):** In `mount/3`, read `"dai_scope_value"` from session. Store it in assigns as `@scope_value`. Pass it to `QueryPipeline.run/3`.
>
> **4. SystemPrompt (`lib/dai/ai/system_prompt.ex`):** Change `build/1` to `build/2` accepting an optional `scope` argument (a map with `:column`, `:table`, `:value`, `:description` or `nil`). When scope is provided, append this rule after the existing rules:
>
> ```
> CRITICAL SCOPING RULE: Every SQL query you generate MUST include a filter on {table}.{column} = '{value}'. For tables that do not have {column} directly, you MUST JOIN through the {table} table to enforce this filter. Never return data that is not scoped to this value. This is a hard security requirement.
> ```
>
> When scope is `nil`, don't add anything.
>
> **5. QueryPipeline (`lib/dai/ai/query_pipeline.ex`):** Update `run/2` to `run/3` with an optional `scope` parameter. Pass it to `Client.generate_plan/3`.
>
> **6. Client (`lib/dai/ai/client.ex`):** Update `generate_plan/2` to `generate_plan/3` with optional `scope`. Pass scope to `SystemPrompt.build/2`.
>
> **7. PlanValidator (`lib/dai/ai/plan_validator.ex`):** After validation passes, if `Dai.Config.query_scope()` is configured, check if the SQL string contains the scope column name. If not, log a warning with `Logger.warning("Dai query missing scope column: #{column}")`. Do NOT reject the query.
>
> **Backward compatibility:** All new parameters are optional with `nil` defaults. When `query_scope` is not configured and no `scope_value` is passed, behavior is identical to current.

- [ ] **Step 1: Make changes in Dai repo per the prompt above**

- [ ] **Step 2: After Dai changes, update Hub's config**

In `config/config.exs`, update the Dai config:

```elixir
config :dai,
  repo: Hub.Repo,
  schema_contexts: [Hub.CRM],
  query_scope: %{
    column: "client_id",
    table: "organizations",
    description: "All queries must filter through organizations.client_id to scope data to the selected client"
  },
  actions: [
    Hub.DaiActions.ApproveOrganization,
    Hub.DaiActions.MarkContactContacted,
    Hub.DaiActions.TriggerNotification
  ]
```

In `lib/hub_web/router.ex`, update the `dai_dashboard` call to pass `scope_value`:

```elixir
    dai_dashboard("/clients/:client_slug/explore",
      layout: {HubWeb.Layouts, :admin},
      on_mount: [{HubWeb.AdminNav, :default}, {HubWeb.ClientScope, :default}],
      scope_value: {HubWeb.Router.Helpers, :get_client_id}
    )
```

Create a helper function to extract the client_id from the session. The exact mechanism depends on how `ClientScope` stores the value. Since `on_mount` assigns `@current_client` to the socket but the session function runs before mount, we need to store the client_id in the session during the `on_mount`:

Update `lib/hub_web/live/client_scope.ex` to also store client_id in the session-accessible path. Since Dai's `scope_value` function receives the session map (set by the router macro), we need to put the client_slug in the Dai session and resolve it there.

Actually, looking at Dai's router macro pattern, `scope_value` is a function that gets called with the conn at session-building time. The simplest approach:

```elixir
# In router.ex dai_dashboard call:
dai_dashboard("/clients/:client_slug/explore",
  layout: {HubWeb.Layouts, :admin},
  on_mount: [{HubWeb.AdminNav, :default}, {HubWeb.ClientScope, :default}],
  scope_value: &HubWeb.DaiHelpers.get_scope_value/1
)
```

Create `lib/hub_web/dai_helpers.ex`:

```elixir
defmodule HubWeb.DaiHelpers do
  def get_scope_value(conn) do
    slug = conn.params["client_slug"]
    case Hub.Clients.get_client_by_slug(slug) do
      nil -> nil
      client -> client.id
    end
  end
end
```

- [ ] **Step 3: Commit Hub changes**

```bash
git add config/config.exs lib/hub_web/router.ex lib/hub_web/dai_helpers.ex
git commit -m "feat(dai): configure query scoping for client isolation"
```

---

### Task 11: Run full test suite and fix

- [ ] **Step 1: Run all tests**

```bash
mix test
```

- [ ] **Step 2: Fix any failures**

Common issues to expect:
- Route helper paths changed — update any remaining `~p"/admin/..."` to `~p"/admin/clients/#{client.slug}/..."`
- Missing `current_client` assign in test socket — update test setup
- CRM test may need client fixtures

- [ ] **Step 3: Run precommit**

```bash
mix precommit
```

- [ ] **Step 4: Commit fixes**

```bash
git add -A
git commit -m "fix: resolve test failures after client scoping migration"
```
