# Dependency Audit — Dai

Date: 2026-06-02 · Scope: `mix.exs` / `mix.lock` · Project type: reusable Phoenix LiveView **library** (also runs standalone)

## Dependency health score: 72 / 100

Solid security posture (no CVEs/retired packages, no unused deps), but the score is held down by a **library-hygiene problem**: every heavy standalone-scaffold runtime dependency is declared as an unconditional hard dep and is therefore forced onto every host app that pulls Dai in as a git dep. This is the single most impactful issue for this project. Secondary deductions for a missing audit tool and minor version drift.

---

## 1. Vulnerabilities

- `mix deps.audit` — **not available** (`mix_audit` / `:mix_audit` is not a declared dependency).
  - **Recommendation:** add `{:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false}` and wire it into `precommit` so the dep tree is CVE-scanned on every commit. Currently there is zero automated supply-chain scanning.
- `mix hex.audit` — clean. **No retired packages.**
- No known-vulnerable versions among locked deps at time of audit.

Summary: no active CVEs/retired packages found, but the project has no automated vuln scanner installed.

## 2. Outdated

All packages are within their declared requirement ranges; nothing is majorly behind. Minor patch/minor drift available:

| Package | Current | Latest | Note |
|---|---|---|---|
| `phoenix` | 1.8.5 | 1.8.7 | patch — safe |
| `phoenix_live_view` | 1.1.28 | 1.1.31 | patch — pinned back by `live_charts` (see §5) |
| `bandit` | 1.10.4 | 1.11.1 | minor — HTTP server, standalone-only |
| `ecto_sql` | 3.13.5 | 3.14.0 | minor |
| `swoosh` | 1.24.0 | 1.26.0 | minor |
| `postgrex` | 0.22.0 | 0.22.2 | patch |
| `req` | 0.5.17 | 0.5.18 | patch — on the AI/HTTP path, worth bumping |
| `jason` | 1.4.4 | 1.4.5 | patch |
| `gettext` | 0.26.2 | 1.0.2 | **major** available but capped by `~> 0.26` requirement — standalone-scaffold only, low priority |

**`live_charts ~> 0.4.0` risk assessment (AI-output rendering path):** This is a young, low-version (0.4.0, pre-1.0) package and it sits directly on the chart-rendering path for AI-generated output. Risks:
- Pre-1.0 semver — minor bumps may break.
- It constrains `phoenix_live_view` to `~> 1.0.0`, which is what blocks LiveView from updating past 1.1.28 (and is the reason the `override: true` exists — see §5).
- Single-purpose rendering dep with a small ecosystem footprint; if it goes unmaintained, the chart rendering layer is stranded.
- **Recommendation:** wrap chart rendering behind a project-owned module (per "wrap third-party APIs" rule) if not already, pin an exact-ish range, and track upstream for a 1.0 / LiveView 1.1-compatible release. Re-evaluate before any production host integration.

Summary: no majorly-behind security-relevant deps; only minor drift. `live_charts` is the one to watch due to pre-1.0 status and its LiveView version cap.

## 3. Unused

- `mix deps.unlock --check-unused` → **clean** (no unused locked deps).
- `swoosh` — **used**: `lib/dai/mailer.ex` (`use Swoosh.Mailer, otp_app: :dai`) and `lib/dai_web/router.ex`. Note: the mailer is library-namespaced (`Dai.Mailer`) but is never started or referenced by the library's runtime path — see §4.
- `dns_cluster` — **used**: `lib/dai/application.ex`, but **only inside the `standalone?` branch**. Not used in library mode.
- `phoenix_live_dashboard` — **used**: `lib/dai_web/router.ex`, `lib/dai_web/endpoint.ex`. **The library router (`lib/dai/router.ex`) does NOT use it** — the only match there is a code comment. Standalone-scaffold only.
- `telemetry_metrics` — **used**: `lib/dai_web/telemetry.ex` only. Standalone-scaffold only.
- `gettext` — **used**: `lib/dai_web.ex`, `lib/dai_web/components/{layouts,core_components}.ex`, `lib/dai_web/gettext.ex`. **Entirely inside the `lib/dai_web/` standalone scaffold** — the `Dai.*` library core does not use it.
- `bandit` — **used**: `config/config.exs`, `config/runtime.exs` (endpoint adapter). Standalone-only; also an *optional* transitive dep of `phoenix`.

Summary: no truly dead deps, but several are confined entirely to the standalone scaffold (`lib/dai_web/`) — which is the §4 hygiene issue, not a §3 issue.

## 4. Library-dependency hygiene — MOST IMPORTANT

Dai is shipped as a git dependency into host apps. `Dai.Application.start/1` proves the intent: in **library mode it starts an empty supervisor** and explicitly clears `:ecto_repos` and the `DaiWeb.Endpoint` config. All of the following are started/used **only** in the `standalone?` branch or only inside `lib/dai_web/`, yet they are declared as **unconditional hard runtime deps** and will be compiled into and force-loaded by every host app:

| Dep | Used only in | Problem |
|---|---|---|
| `bandit ~> 1.5` | standalone endpoint config | Forces a second HTTP server onto host apps that already run Bandit/Cowboy. Already optional in `phoenix`. |
| `dns_cluster ~> 0.2.0` | standalone supervisor branch | Clustering concern that belongs to the host app, not a dashboard library. |
| `phoenix_live_dashboard ~> 0.8.3` | `lib/dai_web/` only | Pulls a whole dashboard UI + `ecto_psql_extras` surface into host apps that will never mount it. |
| `telemetry_metrics ~> 1.0` | `lib/dai_web/telemetry.ex` | Standalone telemetry supervisor only. |
| `telemetry_poller ~> 1.0` | standalone telemetry | Same. |
| `gettext ~> 0.26` | `lib/dai_web/` scaffold | The `Dai.*` core ships its own components and does not i18n through gettext. |
| `swoosh ~> 1.16` | `Dai.Mailer` (never started by lib runtime) | A natural-language data-dashboard library has no reason to force an email stack onto host apps. |

**Recommendation (high priority):** split the dependency list so scaffold-only deps do not leak into host apps. Two viable approaches:

1. **`only: [:dev, :test]`-scope the standalone scaffold deps** that are purely for running Dai by itself: `phoenix_live_dashboard`, `dns_cluster`, `swoosh`, `telemetry_metrics`, `telemetry_poller`, `gettext`, and ideally `bandit`. Combine with `runtime: false` where they are only needed at compile time for the scaffold.
2. If any must remain compilable in `:prod` for the standalone release, mark them `optional: true` so host apps are not forced to resolve them, and document that standalone mode requires them.

Correctly scoped today: `phoenix_live_reload` (`only: :dev`), `lazy_html` (`only: :test`), `esbuild`/`tailwind` (`runtime: Mix.env() == :dev`), `heroicons` (`app: false, compile: false`). So the pattern is understood in this file — it just has not been applied to the runtime scaffold deps. This is the headline fix.

## 5. The `phoenix_live_view ~> 1.1.0, override: true`

- **Why the override exists:** `live_charts` declares `phoenix_live_view ~> 1.0.0`. Without `override: true`, Hex resolution would refuse to combine that with Dai's own `~> 1.1.0` requirement (and `phoenix_live_dashboard`'s `~> 0.19 or ~> 1.0`). The override forces the tree onto LV 1.1.x.
- **Smell:** this is a genuine transitive-conflict workaround driven by `live_charts` lagging behind LV 1.1. It also pins the resolvable LV version (1.1.28 vs 1.1.31 latter is "update not possible" purely because of `live_charts`'s `~> 1.0.0` ceiling interacting with the lock).
- **Library-context risk:** `override: true` in a *library*'s mix.exs is propagated and will silently force the host app's LiveView version too. That is acceptable for a LiveView-centric UI library, but it is fragile: when the host app or another dep needs a different LV major, this override becomes a hard conflict the host cannot easily resolve.
- **Recommendation:** track `live_charts` for a release that declares `phoenix_live_view ~> 1.1` (or `~> 1.0 or ~> 1.1`); once available, the override can likely be dropped or relaxed. Add a code comment in `mix.exs` documenting *why* the override is present (currently undocumented), so future maintainers don't remove it and break resolution.

---

## Score justification

- Security: no CVEs, no retired packages, no unused deps → strong baseline.
- **−15** library-hygiene: ~7 heavy runtime deps forced onto host apps that only the standalone scaffold needs (headline issue for a library).
- **−6** no automated vuln scanner (`mix_audit` absent from precommit).
- **−4** `live_charts` pre-1.0 on the AI-rendering path and capping LiveView updates.
- **−3** `override: true` transitive-conflict workaround, undocumented in mix.exs.

Net: **72 / 100**.
