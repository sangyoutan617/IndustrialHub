# Industrial Hub

## Admin module — design decisions

- **No `alerts` table.** Low-stock and output-shortfall alerts (Priority 1.2,
  `admin_factory_detail_screen.dart`) are computed live from
  `raw_materials.current_stock` vs `reorder_level` and from the bottleneck
  engine, not read from a stored table. This was a deliberate choice over
  the originally planned `app_alerts` table: derived alerts are always
  accurate and can never go stale, at the cost of not being individually
  dismissible. There is no "resolve" action — the only way to clear a
  low-stock alert is to raise a purchase order (via the existing Module 3
  flow) or otherwise change the underlying stock.
- The admin layer is read-only for oversight. State changes (e.g. raising a
  PO from a low-stock alert) always go through the owning module's normal
  screens, never by writing stock levels directly from an admin screen.
- **No bulk-delete or reset action in the app.** The Data & Seed Management
  screen (Priority 1.4, `admin_data_screen.dart`) only offers `Run seed`
  (insert-only, guarded against duplicating the demo factory) and read-only
  simulated-vs-real row counts per table. Deleting simulated rows or
  resetting the demo factory is a deliberate omission — bulk-delete logic
  isn't exposed in the client. If that maintenance is ever needed, it's a
  server-side operation an operator runs directly via SQL in the Supabase
  SQL Editor, not a button in the app.

## Limitations and future work

- **Single-product capacity model.** The capacity/bottleneck model assumes a
  single product line per factory, so output is expressed in uniform units.
  This isolates the constraint logic (machine vs manpower vs raw material)
  from product-mix complexity. Extending to a multi-product model would
  require per-product machine-hour and material-consumption rates across
  `raw_materials` (Module 3), `demand_forecast` and `finished_stock`
  (Module 2) — a larger, cross-module change, and identified here as future
  work rather than built, since it would mean reworking tables owned by
  other members.
- **Government data (MSIC/IPI/productivity) is a static snapshot, not a live
  feed.** Chosen for demo reliability and to avoid a runtime dependency on
  external API availability. See "Government data refresh" below for the
  documented manual procedure — there is no in-app refresh action.
- **Downtime tracking is factory-level, not per-machine.** `downtime_hours`
  (Priority 3's `daily_production` table) is one total per factory per day.
  There is no per-machine downtime column or table anywhere in the schema,
  so the downtime trend on the production trend screen (Priority 7.5) shows
  a daily total with a "worst day" flag rather than a per-machine
  breakdown. Real per-machine tracking would need a new table (e.g.
  `machine_downtime_log(machine_id, factory_id, log_date, downtime_hours)`)
  plus a logging entry point on the machine screens — identified as future
  work, not built here.

## Government data refresh

`msic_codes`, `ipi_benchmarks`, and `productivity_benchmarks` are seeded
once from DOSM data published via data.gov.my and are not re-fetched live.
To refresh them:

1. Sources — Department of Statistics Malaysia (DOSM) open data, via
   OpenDOSM (open.dosm.gov.my):
   - MSIC industry classification (`msic_codes`):
     https://open.dosm.gov.my/data-catalogue/msic
   - Sectoral labour productivity, annual (`productivity_benchmarks`):
     https://open.dosm.gov.my/data-catalogue/productivity_annual
   - Industrial Production Index, 2-digit division (`ipi_benchmarks`):
     https://open.dosm.gov.my/data-catalogue/ipi_2d

   These published datasets were cleaned and reshaped to match the table
   columns in step 3 before import — they are not loaded verbatim.
2. Filters applied to the source data before import (from the live schema's
   shape — see `lib/models/ipi_benchmark.dart`, `msic_code.dart`,
   `productivity_benchmark.dart`):
   - IPI: series = `abs` (absolute index, not year-on-year change), last 12
     months only, one row per `(division, date)`.
   - MSIC: 2-digit division codes only (`msic_codes.msic_code`), with a
     `category` column used to join to `productivity_benchmarks.sector`.
   - Productivity: latest available `year` per `sector`.
3. Column mapping (source CSV → Supabase table):
   - `ipi_benchmarks`: `date`, `division`, `division_name`, `production_index`.
   - `msic_codes`: `msic_code`, `description`, `category`.
   - `productivity_benchmarks`: `sector`, `year`, `value_added_per_worker`,
     `value_added_per_hour`.
4. Re-import via the Supabase Dashboard → Table Editor → open the target
   table → **Insert** → **Import data from CSV**, with the CSV columns
   matching the names above. This upserts additively; to fully replace a
   table's contents, clear it first (Table Editor → Delete rows, or a
   `TRUNCATE` in the SQL Editor) before importing.
5. Automated/scheduled ingestion from the data.gov.my API is not built —
   flagged as future work, not attempted here.

## Performance basics (Priority 7.6)

- Indexes on the frequently-filtered columns the spec names (`factory_id`,
  `log_date`, `status`, `material_id`) — see the SQL block provided
  alongside this change; not committed as a migration file since this repo
  has no `supabase/migrations` folder, same as every other schema change in
  this module.
- **"Limit + load more" pagination was built on the purchase-orders list**
  (`order_list_screen.dart` / `OrderService.getOrdersPageForMaterials()`),
  matching Priority 6's own "doing this for ONE calculation is enough to
  make the point" reasoning — not applied to every list. It was later
  **superseded**, not kept: a teammate's "Supply" PR (merged into `main`
  after this was written) independently rebuilt that same screen with
  status filtering, inline editing, and deletion, and fetches the full
  order list rather than paginating it. Since that version is a genuine
  improvement in every other respect, the merge resolution adopted it
  wholesale and dropped the pagination method rather than trying to bolt
  "load more" onto a screen that also does client-side status filtering
  (the same tension noted below for the admin Users list). The pattern
  itself is still worth applying to a long, unfiltered, ever-growing list
  if one shows up later — it just isn't demonstrated live in this repo
  anymore.
- It was deliberately **not** applied to the admin Users list
  (`admin_users_screen.dart`), which already has full-list client-side
  search; paginating it would mean either only searching already-loaded
  users or rebuilding search as a server-side query, and the existing
  full-fetch is a reasonable bound for this app's scale.

## Shared AI service (Gemini)

A shared AI narration service exists so every module can add its own
"AI insight" feature on the same foundation, rather than each module wiring
up its own Gemini integration. The design is documented in full below.

- **`supabase/functions/gemini-generate`** — a Supabase Edge Function that
  holds the Gemini API key server-side (`GEMINI_API_KEY` secret via
  `supabase secrets set`). The key never reaches the client. Requires a
  logged-in user's JWT (platform-level `verify_jwt = true` in
  `supabase/config.toml`, plus an in-function check as a second layer).
  Uses the `gemini-flash-latest` model alias rather than a pinned version
  (`gemini-1.5-flash` was retired after this was first built) so the
  function doesn't need a redeploy every time Google rotates the
  flash-tier model underneath it.
- **`lib/services/ai_service.dart`** — thin client wrapper. `AiService.generate(prompt, {system})`
  calls the Edge Function and returns the plain-text reply, or throws a
  clean `Exception` on failure.
- **`lib/widgets/ai_insight_card.dart`** — the shared `AiInsightCard` widget.
  Takes a `buildPrompt()` callback and an optional `system` prompt; renders
  idle/loading/ready/quiet-failure states. Never blocks the screen's real
  (deterministic) data if the AI call fails.
  - Answers are cached in-memory, keyed by the exact prompt text, so
    navigating away (pushing a route, switching tabs) and back reuses the
    previous answer instead of re-calling Gemini — it only regenerates when
    the underlying numbers actually change the prompt, or the user taps the
    manual regenerate button.

**Design principle every module's AI feature must follow:** the deterministic
engine computes the numbers; Gemini only explains or narrates them. Never
send raw data and ask Gemini to do the arithmetic — compute the figures in
Dart first, then ask only for a plain-language explanation of numbers already
given to it.

**Module 1 (capacity) — bottleneck explanation + hiring recommendation.**
`CapacityDashboardScreen` mounts an `AiInsightCard` below the production
ceiling card. `CapacityService.computeHiringGap()` deterministically computes
how many additional workers (at the current average output rate) would
remove a labour bottleneck; the AI card only narrates that result plus the
machine/labour capacity figures — it never sees raw shift/machine rows.

**Module 2 (stock) — finished-goods cover explanation.**
`StockDashboardScreen` mounts an `AiInsightCard` below the "Days of cover"
card. The dashboard's `_load()` computes days of cover and the predicted
stock-out date per product; the AI card only narrates which product runs
out first, the low/overstocked counts, and one next step. It's gated so an
empty factory (no demand forecast) spends no AI call.

**Module 3 (supply) — raw-material supply-risk explanation.**
`MaterialListScreen` mounts an `AiInsightCard` below the summary card.
`MrpService` (via `SupplyService.load`) computes each material's burn rate,
days of cover, stock-out and latest safe order-by dates, recommended
(reliability-adjusted) supplier, and suggested order quantity; the AI card
only narrates which material to reorder first and from whom. If no capacity
is set, the prompt tells the model to treat risk as unknown rather than
safe, matching the on-screen caveat.

All three follow the same rule — the deterministic engine computes every
number, Gemini only explains it — and reuse the same `AiInsightCard` and
`gemini-generate` Edge Function.

## Production trend (Priority 3)

- `daily_production` rows are written from `DailyProductionService.logProduction()`,
  which lives in Module 1 (capacity) per the spec. The spec also says Module 2
  (stock) should trigger this when logging production — that integration was
  **not** wired in, since it means writing into another module's code path and
  the spec explicitly says to agree that with the Module 2 owner first. Instead,
  the production trend screen has its own "Log production" entry point so the
  feature is fully usable standalone. If/when the stock module should trigger
  it automatically, call `DailyProductionService.logProduction()` from wherever
  Module 2 records a production movement.
