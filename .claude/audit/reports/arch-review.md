# Architecture Review — Dai Library

Date: 2026-06-02

## Score: 74 / 100

---

## Finding 1 — CRITICAL: Folders have no user/tenant isolation

**Impact: Security**

`Dai.Folders.Folder` and `Dai.Folders.SavedQuery` schemas carry no `user_token` field. Every Folders query (`list_folders/0`, `list_saved_queries/1`) returns all rows across all users. Any authenticated session can delete or rename another user's folders by guessing a UUID, because `delete_folder_by_id/1` and `rename_folder/2` do a bare `repo().get(Folder, id)` with no ownership check.

Affected files:
- `lib/dai/folders/folder.ex:9` — schema has no `user_token` column
- `lib/dai/folders/saved_query.ex:9` — ditto
- `lib/dai/folders.ex:44-52` — `rename_folder/2`, `delete_folder_by_id/2`, `list_folders/0` unscoped
- `lib/dai/dashboard_live.ex:370` — `handle_event("delete_folder")` passes raw client-supplied `id` directly to context, no ownership assertion

The `user_token` is already stored in `socket.assigns` (line 225) and threaded through `DashboardLayout` and `DashboardPreferences`. It is simply not applied to the Folders context at all.

**Recommendation:** Add `user_token :string` (or `:binary_id`) to both schemas + migration. Scope every Folders query: `where(user_token: ^user_token)`. Pass `user_token` as first argument to all mutating Folders context functions and validate ownership before `repo().delete/1`.

---

## Finding 2 — MODERATE: `DashboardLive` is a borderline god-module

**Impact: Maintainability**

`lib/dai/dashboard_live.ex` is 584 lines with 26 `handle_event` clauses and 6 `handle_info` clauses. The 26 events span four distinct concerns:

| Group | Events | Lines |
|-------|--------|-------|
| Query execution | query, retry, run_suggestion, edit_suggestion, confirm_action | ~50 |
| Folder/sidebar management | save_query, save_query_new_folder, create_folder, load_folder, run_saved_query, load_all_folder_queries, delete_folder, delete_saved_query, rename_folder, rename_saved_query | ~120 |
| Layout/panel persistence | layout_changed, panel_resized | ~10 |
| Schema explorer | select_table, deselect_table, reset_explorer | ~30 |

It is not yet a true god-module — the `render/1` template (lines 20–202), `mount/3`, and the private helpers hold it together coherently — but the folder-management block is a natural extraction target. The module does not reach into Repo directly (clean), and all side effects go through context modules (clean).

**Recommendation:** Extract folder `handle_event` clauses and their private helpers into a dedicated `Dai.FolderEventHandler` module (plain module exporting functions, not a LiveComponent). `DashboardLive` delegates: `FolderEventHandler.handle_event(event, params, socket)`. This keeps `DashboardLive` under ~380 lines and makes folder logic independently testable. Do not split into a LiveComponent — no isolated state or lifecycle is needed.

---

## Finding 3 — MODERATE: Component types duplicated in `Result` type spec and `SystemPrompt`

**Impact: Maintainability / drift risk**

`Dai.AI.Component` is the declared single source of truth (`lib/dai/ai/component.ex`), but the five visualization-type atoms are also hardcoded in two other places:

- `lib/dai/ai/result.ex:7-11` — `@type t` union lists all five atoms manually, plus `:clarification | :error | :action_confirmation | :action_result`. If a new component type is added to `Component`, `Result.t()` must be updated separately or specs silently drift.
- `lib/dai/ai/system_prompt.ex:19-45` — type names appear as strings in the prompt template (unavoidable — they are the API contract with Claude). This duplication is **acceptable** as it is a text prompt, not code logic.
- `lib/dai/dashboard_components.ex:53-68` — pattern-matches on component type atoms in `card_body/1` function heads. If a new type is added to `Component`, a new `card_body` clause must be added manually with no compiler guard.

**Recommendation:** The `Result.t()` type spec duplication is the actionable one. Derive the type from `Component` at compile time:

```elixir
# In Dai.AI.Component
def component_types, do: Map.keys(@types) |> Enum.map(&to_atom/1)
```

Then in `Result`, add `@spec type_list :: [atom()]` and a module attribute that references it. For `card_body`, add a catch-all clause that raises at runtime for unknown types — at least you get an immediate error rather than silent rendering failure.

---

## Finding 4 — LOW: Three xref cycles, all benign

`mix xref graph --format cycles` reports three cycles:

1. **Demo analytics schemas** (`event ↔ feature ↔ invoice ↔ plan ↔ subscription ↔ user`) — Ecto `belongs_to`/`has_many` compile-time references between schemas in the same context. Benign; standard Ecto pattern. No action needed.

2. **`DaiWeb` scaffold** (`layouts ↔ endpoint ↔ router`) — The standalone scaffold's boot-time references. Benign; standard Phoenix scaffold pattern. Importantly, this cycle lives entirely in `lib/dai_web/` and does not touch `lib/dai/`. It disappears when the library is used as a dependency (host app provides its own endpoint/router).

3. **`Folders` schemas** (`folder.ex ↔ saved_query.ex`) — Mutual `has_many`/`belongs_to` aliases. Benign; same pattern as demo schemas.

No action needed for any cycle.

---

## Finding 5 — LOW: `DashboardLive` mount queries DB unconditionally (missing `connected?` guard)

**Impact: Performance / double-render**

`lib/dai/dashboard_live.ex:213-214`:

```elixir
prefs = DashboardPreferences.get_preferences(user_token)
saved_layouts = DashboardLayout.get_layouts(user_token)
```

These two Repo queries run on both the static render (dead socket) and the connected mount, doubling DB load on every page load. The global CLAUDE.md iron law is: no unconditional DB queries in mount — use `assign_async` or `connected?` branch.

`lib/dai/dashboard_live.ex:229`:
```elixir
folders: Folders.list_folders(),
```
Same issue — unconditional query.

**Recommendation:** Wrap all three behind `if connected?(socket)` with safe defaults for the static render, or use `assign_async` if you want SSR data with spinner replacement. Example pattern:

```elixir
if connected?(socket) do
  prefs = DashboardPreferences.get_preferences(user_token)
  saved_layouts = DashboardLayout.get_layouts(user_token)
  assign(socket, panel_sizes: prefs.panel_sizes, saved_layouts: saved_layouts, folders: Folders.list_folders())
else
  assign(socket, panel_sizes: %{}, saved_layouts: [], folders: [])
end
```

---

## Clean Areas (no action needed)

- **Library/host boundary** — Zero `DaiWeb.*` references exist under `lib/dai/`. The library is fully isolated from the standalone scaffold.
- **AI pipeline cohesion** — `Client → PlanValidator → SqlExecutor → ResultAssembler` separation is clean. Each module has a single responsibility. `QueryPipeline` is 30 lines and pure orchestration. No leakage between steps.
- **No direct Repo calls in LiveView** — `DashboardLive` delegates 100% of persistence to context modules.
- **No `DaiWeb.*` dependency in library code** — confirmed by grep.
- **Ecto.Multi used correctly** — `save_query_to_new_folder/3` at `folders.ex:76` uses `Ecto.Multi` for the folder+query atomic insert.
- **`Dai.Config` indirection** — all modules read config through `Dai.Config`, none call `Application.get_env` directly.
- **xref cycles** — all three are benign Ecto schema mutual references or standard Phoenix scaffold patterns.

---

## Priority Order

| # | Severity | Finding | Effort |
|---|----------|---------|--------|
| 1 | Critical | Folders not scoped by user — IDOR vulnerability | Medium (migration + context changes) |
| 2 | Moderate | Component type list duplicated in `Result.t()` | Small |
| 3 | Moderate | `DashboardLive` approaching god-module (26 handle_events) | Medium |
| 4 | Low | Unconditional DB queries in mount | Small |
| 5 | None | xref cycles | No action |
