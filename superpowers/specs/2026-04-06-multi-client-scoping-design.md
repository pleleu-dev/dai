# Multi-Client Scoping Design

Hub is a CRM that serves multiple apps. Each app is represented as a **Client**. Users create clients (e.g., "MyApp - Staging", "MyApp - Prod") and all CRM data is scoped to the selected client. This design adds a client selection flow, scoped admin UI, scoped API routes, and a generic query scoping feature for Dai.

## Decision Log

- **Client = App + Environment.** No separate environment entity. Users create distinct clients for staging vs prod if needed. Keeps the model flat and flexible.
- **All users see all clients.** No per-user access control on clients. Fine for a small team.
- **API keys locked to a client.** A key for Client A cannot push data to Client B.
- **Dai scoping via prompt rules + warning logs.** No post-generation SQL injection. No hard rejection. Claude is instructed via CRITICAL system prompt rule; PlanValidator logs warnings if the scope column is missing.

---

## 1. Client Selection Page

**Route:** `GET /admin/clients`

After login, users land on this page. It displays:

- A grid of client cards, each showing:
  - Client name
  - Organization count
  - Account count
- A "New Client" button that opens a simple inline form (name only). On submit, creates the client (with auto-generated slug) and navigates into it.

Clicking a card navigates to `/admin/clients/:client_slug/organizations`.

If a user navigates to any `/admin/clients/:slug/...` route directly (e.g., bookmark), the `on_mount` hook resolves the slug. If invalid, redirect to `/admin/clients`.

---

## 2. Admin Route Restructure

All admin pages move under `/admin/clients/:client_slug/...`.

```elixir
# Client selection — no client context
scope "/admin", HubWeb do
  live "/clients", ClientLive.Index, :index
end

# Scoped admin pages
scope "/admin/clients/:client_slug", HubWeb do
  live "/organizations", OrganizationLive.Index, :index
  live "/organizations/:id", OrganizationLive.Show, :show
  live "/accounts", AccountLive.Index, :index
  live "/accounts/:id", AccountLive.Show, :show
  live "/contacts", ContactLive.Index, :index
  live "/notifications", NotificationLive.Index, :index
  live "/workflows", WorkflowLive.Index, :index
  live "/settings", ClientSettingsLive.Index, :index

  dai_dashboard "/explore",
    layout: {HubWeb.Layouts, :admin},
    on_mount: [{HubWeb.AdminNav, :default}],
    scope_value: &get_client_id/1
end
```

**`on_mount` hook (e.g., `HubWeb.ClientScope`):**
- Reads `:client_slug` from params
- Queries `Hub.Clients.get_client_by_slug(slug)`
- Assigns `@current_client` to socket
- Redirects to `/admin/clients` if not found

**Sidebar changes:**
- Top of sidebar shows current client name with a "Switch" link → `/admin/clients`
- All nav links include the `@current_client.slug` in their paths

---

## 3. Data Scoping

All CRM context functions (`Hub.CRM`) accept and enforce `client_id`:

- **Organizations:** Already have `client_id` FK. `list_organizations/2` filters by `client_id`. No schema change.
- **Accounts:** Scoped through organization. Queries join `accounts → organizations` and filter by `organizations.client_id`.
- **Contacts:** Scoped through account → organization. Queries join up the chain.
- **Notifications:** Same join chain as contacts.
- **Workflows:** Same join chain as contacts.

All LiveView `mount/3` and `handle_event/3` functions pass `@current_client.id` to context functions.

---

## 4. API Route Changes

Current flat routes move under `/api/v1/clients/:client_id/...`:

```
POST   /api/v1/clients/:client_id/organizations
GET    /api/v1/clients/:client_id/organizations
GET    /api/v1/clients/:client_id/organizations/:id
PATCH  /api/v1/clients/:client_id/organizations/:id
POST   /api/v1/clients/:client_id/organizations/:org_id/accounts
GET    /api/v1/clients/:client_id/organizations/:org_id/accounts
PATCH  /api/v1/clients/:client_id/accounts/:id
POST   /api/v1/clients/:client_id/accounts/:account_id/contacts
GET    /api/v1/clients/:client_id/accounts/:account_id/contacts
PATCH  /api/v1/clients/:client_id/contacts/:id
GET    /api/v1/clients/:client_id/notifications
POST   /api/v1/clients/:client_id/notifications
```

**Auth enforcement:**
- `RequireApiKey` plug validates the bearer token as before
- New plug or extension: verify `api_key.client_id == params["client_id"]`
- Mismatch → 403 Forbidden

---

## 5. Client Settings Page

**Route:** `GET /admin/clients/:client_slug/settings`

A LiveView with:
- Edit client name (form with save)
- API key display (masked after creation, shown once on generate)
- Regenerate API key (with confirmation)
- Delete client (with confirmation modal, cascades to all data)

---

## 6. Dai Query Scoping (new Dai feature)

A generic feature for Dai — any host app can configure mandatory query scoping.

### Configuration

**Static config (column + table):**
```elixir
config :dai,
  query_scope: %{
    column: "client_id",
    table: "organizations",
    description: "All queries must filter through organizations.client_id"
  }
```

**Runtime value delivery (via router macro):**
```elixir
dai_dashboard "/explore",
  scope_value: &get_client_id/1   # fn(session) -> value
```

The `scope_value` function receives the session map and returns the runtime value (e.g., the selected client's UUID).

### SystemPrompt injection

When `query_scope` is configured and a runtime value is available, `SystemPrompt.build/1` appends a rule:

```
CRITICAL SCOPING RULE: Every query you generate MUST filter by
organizations.client_id = '<runtime_value>'. For tables that do not have
client_id directly, JOIN through the organizations table to enforce this filter.
Never return data across multiple clients.
```

### PlanValidator warning

After Claude returns a plan, `PlanValidator` checks if the generated SQL contains the scope column name. If missing, it logs a warning but does NOT reject the query. This is a monitoring aid, not a hard gate.

### Backward compatibility

When `query_scope` is not configured:
- No prompt changes
- No validation changes
- Feature is completely invisible

---

## 7. Migration

One migration needed:

```elixir
alter table(:clients) do
  add :slug, :string
end

create unique_index(:clients, [:slug])
```

Backfill existing clients with slugs generated from their names (same algorithm as accounts: downcase, replace non-alphanumeric with hyphens, trim). If duplicates arise, append a numeric suffix (e.g., `my-app-2`).

No other schema changes required — organizations already have `client_id`.

---

## 8. Affected Files Summary

### Hub (this repo)

**New files:**
- `lib/hub_web/live/admin/client_live/index.ex` — client selection page
- `lib/hub_web/live/admin/client_settings_live/index.ex` — client settings
- `lib/hub_web/plugs/require_client_scope.ex` — on_mount hook for client resolution
- `priv/repo/migrations/TIMESTAMP_add_slug_to_clients.exs`

**Modified files:**
- `lib/hub_web/router.ex` — restructure admin routes under client scope
- `lib/hub_web/components/layouts/admin.html.heex` — add client name + switch link to sidebar
- `lib/hub_web/components/layouts.ex` — update nav_link paths to include client slug
- `lib/hub/crm.ex` — add client_id parameter to all list/filter functions
- `lib/hub/clients.ex` — add `get_client_by_slug/1`, slug generation
- `lib/hub/clients/client.ex` — add slug field to schema
- `lib/hub_web/live/admin/organization_live/index.ex` — scope by current_client
- `lib/hub_web/live/admin/organization_live/show.ex` — scope by current_client
- `lib/hub_web/live/admin/account_live/index.ex` — scope by current_client
- `lib/hub_web/live/admin/account_live/show.ex` — scope by current_client
- `lib/hub_web/live/admin/contact_live/index.ex` — scope by current_client
- `lib/hub_web/live/admin/notification_live/index.ex` — scope by current_client
- `lib/hub_web/live/admin/workflow_live/index.ex` — scope by current_client
- `lib/hub_web/controllers/api/v1/*_controller.ex` — update to read client_id from URL
- `lib/hub_web/plugs/require_api_key.ex` — verify key belongs to URL client_id
- All controller tests — update routes to include client_id

### Dai (separate repo)

**Modified files:**
- `lib/dai/router.ex` — add `scope_value` option to `dai_dashboard` macro
- `lib/dai/ai/system_prompt.ex` — inject scoping rule when configured
- `lib/dai/ai/plan_validator.ex` — add warning log when scope column missing
- `lib/dai/config.ex` — add `query_scope/0` and `scope_value/0` readers
- `lib/dai/dashboard_live.ex` — pass scope value through to pipeline

---

## 9. Out of Scope

- Per-user client access control
- Grouping clients by project/app (e.g., "MyApp" grouping staging + prod)
- Data promotion between clients (staging → prod)
- Multiple scope columns
- Post-generation SQL injection for scoping
