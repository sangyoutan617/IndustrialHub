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

1. Source: data.gov.my, Department of Statistics Malaysia (DOSM) datasets.
   `TODO: insert the exact dataset URLs/IDs used for the MSIC code list, the
   Industrial Production Index (IPI), and sectoral labour productivity —
   not recorded anywhere in this repo, so pull them from whoever did the
   original import before publishing this section.`
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
- **"Limit + load more" pagination is demonstrated on one screen** (the
  purchase-orders list, `order_list_screen.dart` /
  `OrderService.getOrdersPageForMaterials()`), matching Priority 6's own
  "doing this for ONE calculation is enough to make the point" reasoning —
  not applied to every list. It was deliberately **not** applied to the
  admin Users list (`admin_users_screen.dart`), which already has full-list
  client-side search; paginating it would mean either only searching
  already-loaded users or rebuilding search as a server-side query, and the
  existing full-fetch is a reasonable bound for this app's scale. Extend the
  same pattern to other long lists (materials, suppliers, machines) if they
  grow large enough in practice to need it.

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
