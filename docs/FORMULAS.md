# Industrial Hub — Formula Reference

Every calculation the app performs, grouped by module and ordered as the
computation pipeline that produces them. Each formula carries an ID so later
stages can reference the earlier ones they consume.

| Module | IDs | Pipeline |
| --- | --- | --- |
| [Capacity](#module-1--capacity) | C1–C19 | Resources → ceiling → bottleneck → verdict |
| [Stock](#module-2--stock-finished-goods) | S1–S7 | Movements → balance → demand match → cover |
| [Supply](#module-3--supply-mini-mrp) | M1–M21 | Burn rate → supplier → projection → reorder |

**Units.** Everything is units/day unless stated. Currency is RM throughout.

**Notation.** `Σ` sums over the stated set. `min`/`max`/`mean`/`ceil`/`clamp`
are the usual functions. `≔` marks a definition used only within that formula.

---

## Contents

- [Module 1 — Capacity](#module-1--capacity)
  - [Stage 1: Resource capacities](#stage-1-resource-capacities)
  - [Stage 2: Ceiling and bottleneck](#stage-2-ceiling-and-bottleneck)
  - [Stage 3: Material supply and demand](#stage-3-material-supply-and-demand)
  - [Stage 4: The verdict](#stage-4-the-verdict)
  - [Stage 5: Derived metrics](#stage-5-derived-metrics)
  - [Stage 6: What-if simulator](#stage-6-what-if-simulator)
  - [Stage 7: Trend aggregation](#stage-7-trend-aggregation)
  - [Stage 8: Benchmark vs Malaysia](#stage-8-benchmark-vs-malaysia)
- [Module 2 — Stock](#module-2--stock-finished-goods)
- [Module 3 — Supply](#module-3--supply-mini-mrp)
- [Cross-module flow](#cross-module-flow)
- [Constants](#constants)
- [Provenance and caveats](#provenance-and-caveats)
- [Test coverage](#test-coverage)

---

# Module 1 — Capacity

```
 machine capacity ─┐
                   ├─→ production ceiling ─┐
manpower capacity ─┘         (C3)          ├─→ achievable ─→ utilisation
       (C1, C2)                            │      (C7)          (C13)
                   material ceiling (C5) ──┤
                   required/day    (C6) ───┴─→ verdict (C8–C10)
```

## Stage 1: Resource capacities

Two independent sums everything else is built on. Both answer the same
question — how many units per day could this resource alone sustain — so they
are directly comparable.

### C1 · Machine capacity

```
machineCapacity = Σ ( ratedOutputPerHour
                    × operatingHoursPerDay
                    × uptimePercent / 100 )

over machines where status == 'Active'
```

Only machines whose `status` is exactly `'Active'` contribute. Every other
status — under maintenance, retired — is excluded outright rather than
derated, so a machine flipped inactive drops its full share of the ceiling.

> `lib/services/capacity_service.dart` · `computeMachineCapacity`

### C2 · Manpower capacity

```
manpowerCapacity = Σ ( workerCount
                     × shiftHours
                     × outputPerWorkerHour )

over every shift — no status filter
```

Note the asymmetry with C1: shifts have no active/inactive concept, so all of
them count. Shifts **sum** rather than max because they are sequential within a
day — two 8-hour shifts genuinely produce for 16 hours.

> `lib/services/capacity_service.dart` · `computeManpowerCapacity`

## Stage 2: Ceiling and bottleneck

### C3 · Production ceiling (effective capacity)

```
effectiveCapacity = min( machineCapacity, manpowerCapacity )
```

A day's output cannot exceed either resource, so the lower one governs. This is
the figure shown as **Daily production ceiling** on the Capacity dashboard.

> `lib/services/capacity_service.dart` · `getSnapshot`

### C4 · Bottleneck resource

```
bottleneckResource = machineCapacity < manpowerCapacity
    ? 'MACHINE'
    : 'MANPOWER'
```

The comparison is strictly `<`, so an **exact tie resolves to `MANPOWER`**.
That tie-break is deliberate and test-covered: on a tie, adding workers is the
cheaper lever, and C12 correctly returns no hiring recommendation because the
gap is zero.

> `lib/services/capacity_service.dart` · `bottleneckResourceFor`

## Stage 3: Material supply and demand

Two external constraints sitting outside the machine/labour pair: what raw
stock physically permits, and what the demand plan actually asks for.

### C5 · Material ceiling

```
materialCeiling = min( currentStock / consumptionPerUnit )

over materials where consumptionPerUnit > 0
null when no material qualifies
```

The scarcest material governs, since one exhausted input halts the line
regardless of the others. Materials with a non-positive consumption rate are
skipped rather than treated as infinite — dividing by zero would poison the
minimum.

> `compute_bottleneck()` — see [Provenance](#provenance-and-caveats)

### C6 · Required per day

```
requiredPerDay = Σ demand_forecast.requiredPerDay
```

Summed across all forecast rows for the factory. Where the Supply module reads
this same figure it first filters to forecasts in effect today (S2), so an
expired or not-yet-started plan cannot inflate demand.

> `compute_bottleneck()` · `demand_forecast`

## Stage 4: The verdict

### C7 · Achievable output

```
achievable = materialCeiling == null
    ? productionCeiling
    : min( productionCeiling, materialCeiling )
```

A null material ceiling means no material data exists, which is treated as
**unconstrained** rather than as zero. This is the number shown as *Achievable
output* on the home dashboard, and the ceiling every logged production day is
scored against.

> `compute_bottleneck()` → `BottleneckResult.achievable`

### C8 · Demand verdict · C9 · Shortfall

```
canMeetDemand = achievable >= requiredPerDay

shortfall = requiredPerDay − achievable    (only when canMeetDemand is false)
```

Shortfall stays null while demand is met, rather than reporting a negative or
zero gap — the dashboard reads its presence, not its sign.

### C10 · Limiter

```
limiter = materialCeiling != null && materialCeiling < productionCeiling
    ? 'RAW MATERIAL'
    : bottleneckResource

null while canMeetDemand is true
```

The limiter differs from the bottleneck resource (C4): C4 always names
whichever of machine or labour is lower, while the limiter can override both
with `'RAW MATERIAL'` when stock is the binding constraint. It is only
populated when demand is missed — this is the value the home dashboard's Smart
Actions switch on.

> `compute_bottleneck()` → `BottleneckResult.limiter`

## Stage 5: Derived metrics

### C11 · Output per worker

```
totalWorkers = Σ shift.workerCount

outputPerWorker = totalWorkers == 0
    ? null
    : effectiveCapacity / totalWorkers
```

Divides the ceiling (C3), not actual output, so it measures **designed**
productivity rather than realised productivity.

> `lib/services/capacity_service.dart` · `outputPerWorker`

### C12 · Hiring gap

```
Only when bottleneckResource == 'MANPOWER' and currentWorkers > 0:

avgOutputPerWorkerDay   = manpowerCapacity / currentWorkers
gap                     = machineCapacity − manpowerCapacity
additionalWorkersNeeded = ceil( gap / avgOutputPerWorkerDay )

null when the result is ≤ 0, or when machines are the bottleneck
```

Sizes the headcount that would lift labour capacity up to — never past — the
machine ceiling. Rounded up because a fraction of a worker cannot be hired.
This is the one number the Gemini insight card narrates; it never computes it.

> `lib/services/capacity_service.dart` · `computeHiringGap`

### C13 · Utilisation percent

```
effectiveCeiling = bottleneck.hasData ? achievable : null

utilisationPercent = (effectiveCeiling != null && effectiveCeiling > 0)
    ? actualOutput / effectiveCeiling × 100
    : null
```

Computed once at log time and **stored on the row**, not recomputed on read —
so a day's utilisation reflects the ceiling as it stood that day, and stays
correct after machines or shifts later change.

> `lib/services/daily_production_service.dart` · `logProduction`

## Stage 6: What-if simulator

The simulator is the one place that re-derives capacity on the client rather
than reading `compute_bottleneck()`. That is deliberate — it is read-only and
needs instant feedback as fields change. Its rates are weighted so the
untouched baseline still lands on C1 and C2.

### C14 · Simulated capacities

```
Rates, derived once from the active fleet:

machineNameplate    = mean( rated × hours )          active machines only
outputPerWorkerHour = C2 / Σ( workerCount × shiftHours )

Baseline field values — chosen so an untouched simulator reproduces C1 and C2:

uptimePercent = Σ( rated × hours × uptime ) / Σ( rated × hours )
shiftHours    = Σ( workerCount × shiftHours ) / totalWorkers

The simulation itself:

simMachineCapacity  = activeMachines × machineNameplate × uptimePercent / 100
simManpowerCapacity = workers × shiftHours × outputPerWorkerHour
simEffective        = min( the two )
```

The simulator needs a *per-machine* rate because it prices machine counts that
don't exist yet — but every mean above is weighted so that, at the untouched
baseline, the arithmetic collapses back onto C1 and C2. An added machine is
therefore worth what an average active machine is worth, and the starting
number matches the dashboard.

Two details carry the weighting:

- `machineNameplate` is the mean of the **product** `rated × hours`, not the
  product of the two means — the latter drops the covariance and understates
  any fleet where the faster machines also run the longer days.
- Uptime is **capacity-weighted**, not a per-machine mean, so a low-uptime
  minor machine cannot drag the whole fleet down.

Residual error is bounded by the whole-number-only input fields: measured at
**+0.06%** on live data (simulator 1 428.8 vs dashboard 1 428), entirely from
rounding uptime to 94%.

> `lib/services/capacity_service.dart` · `SimulatorBaseline.from`
> `lib/screens/capacity/simulator_screen.dart`

## Stage 7: Trend aggregation

Three granularities over the logged daily history. All averaging divides by the
number of rows **actually present**, never by the calendar length — a
partly-logged period reads as its true average rather than as a slump.

### C15 · Rolling 7-day and monthly averages

```
Rolling week — for each of the last 30 anchor days,
over the window [anchor − 6 days … anchor]:

avgActual  = Σ actualOutput      / count(rows in window)
avgCeiling = Σ effectiveCeiling  / count(rows with a ceiling)

Monthly — group rows by year-month, same two means.
Windows with no rows are skipped, not plotted as zero.
```

The actual and ceiling means use **different denominators**: rows missing a
ceiling are excluded from the ceiling average but still count toward the output
average.

> `lib/screens/capacity/production_trend_screen.dart`

### C16 · Dominant bottleneck banner

```
dominant = mode( row.bottleneck )   over the last 30 days, null labels skipped
                                    ties resolve to the first label reached
```

Renders as *"Machine-bound on 1 of the last 30 days"*. Counts logged days only,
so the denominator in that sentence is days **recorded**, not days elapsed.

## Stage 8: Benchmark vs Malaysia

DOSM publishes the Industrial Production Index as an *index*, not a unit count,
so factory output and sector output cannot be compared at their levels.
Rebasing both to 100 at a shared month makes their growth rates comparable.

### C17 · Factory monthly output

```
factoryMonthly[m] = Σ actualOutput in m / count(logged days in m)
```

Averaged per logged day rather than summed, so a month with fewer recorded days
sits on the same footing as DOSM's monthly index.

> `lib/services/daily_production_service.dart` · `getMonthlyAverageOutput`

### C18 · Rebased comparison

```
Keep only months present in BOTH series, ascending.
Let index 0 be the first such month.

factoryIndex[i] = factory[i] / factory[0] × 100
sectorIndex[i]  = sector[i]  / sector[0]  × 100

factoryChangePercent = factoryIndex.last − 100
sectorChangePercent  = sectorIndex.last  − 100

Returns null — and the chart falls back to the sector line alone —
when fewer than 2 months overlap, or factory[0] ≤ 0, or sector[0] ≤ 0.
```

Months the factory never logged are dropped from both series rather than read
as zero output, so a gap **shortens** the comparison instead of registering as
a collapse.

> `lib/services/capacity_service.dart` · `buildSectorComparison`

### C19 · Planned production per day

```
requiredPerDay = Σ activeForecasts.requiredPerDay

plannedProductionPerDay = requiredPerDay > 0
    ? clamp( requiredPerDay, 0, effectiveCapacity )
    : effectiveCapacity
```

The Supply module's bridge into Capacity: demand drives the plan, capped by
what C3 allows, falling back to full capacity when no forecast is set.
`activeForecasts` is filtered by S2.

> `lib/services/supply_service.dart` · `plannedProductionPerDayFor`

---

# Module 2 — Stock (finished goods)

```
movements ─→ current_quantity ─┐
                  (S1)         ├─→ days of cover ─→ status
active demand by product ──────┘      (S3)          (S5)
              (S2)                     │
                                       └─→ stock-out date (S4)
```

Finished goods and raw materials keep **deliberately separate ledgers**. This
module is finished goods; raw materials are M21 in the Supply module.

### S1 · Movement delta and running balance

```
delta = production_in  →  +|quantity|
        returned       →  +|quantity|
        shipment_out   →  −|quantity|
        damaged        →  −|quantity|
        adjustment     →   quantity   (signed as entered)

newQuantity = currentQuantity + delta

Rejected before any write when newQuantity < 0.
```

Only `adjustment` respects the sign the user typed; every other type coerces
the magnitude and applies the sign the type implies, so a mistyped negative on
a shipment cannot silently *add* stock. The balance is stored on
`finished_stock.current_quantity` and updated in the same call that inserts the
ledger row.

Movements are queued locally first and synced opportunistically — the factory
floor rarely has reliable Wi-Fi. A below-zero failure is a real conflict, not a
connectivity problem, so it is surfaced immediately rather than retried
forever.

> `lib/services/stock_service.dart` · `recordMovement`, `recordMovementQueued`

### S2 · Active demand, matched by product name

```
requiredByName[ normalise(productName) ] =
    Σ requiredPerDay  over forecasts active today

normalise(name) ≔ name.trim().toLowerCase()

isActiveOn(day):
    false if periodStart != null and day < periodStart
    false if periodEnd   != null and day > periodEnd
    true otherwise           (both boundaries inclusive, compared date-only)
```

Demand is joined to stock **by product name**, not by foreign key — so a typo
in either name silently breaks that product's days-of-cover. Renaming a product
is what repairs it. An open-ended period (null on either side) is always in
effect on that side, so a forecast with no dates at all counts every day.

> `lib/screens/stock/stock_cover_loader.dart` · `lib/models/demand_forecast.dart`

### S3 · Days of cover (finished goods)

```
daysOfCover = (required != null && required > 0)
    ? currentQuantity / requiredPerDay
    : null
```

Deliberately simpler than the material equivalent (M8): finished goods have no
inbound pipeline to project against, so this is a flat division rather than a
day-by-day walk.

### S4 · Stock-out date

```
stockOutDate = today + floor(daysOfCover) days      null when daysOfCover is null
```

Floored, so a partial final day is not counted as covered.

### S5 · Cover status

```
requiredPerDay == null or 0   →  'No demand set'   neutral
daysOfCover < 7               →  'Low stock'       danger
daysOfCover > 60              →  'Overstocked'     info
otherwise                     →  'Healthy'         success

needsAttention = requiredPerDay > 0 and daysOfCover < 7
```

Note the asymmetry: low stock uses `<` and overstock uses `>`, so exactly 7 and
exactly 60 days both read as *Healthy*.

> `lib/screens/stock/stock_cover_loader.dart` · `ProductCover`

### S6 · Activity heatmap daily totals

```
totals[day] = Σ |quantity|   over all movements on that day, all types combined

window = the last 84 days (12 weeks × 7), pre-seeded to 0
movements outside [start, today] are dropped, not accumulated
```

Absolute values, so a shipment out and a production in of the same size read as
equal *activity* rather than cancelling to zero. This measures throughput, not
net change.

### S7 · Heatmap cell intensity

```
ratio = value / maxVal        maxVal = the busiest day in the window

ratio == 0     → border grey
ratio ≤ 0.25   → primaryLight
ratio ≤ 0.50   → primaryAccent @ 55% alpha
ratio ≤ 0.75   → primaryAccent
otherwise      → primaryDark
```

Scaled against the window's own maximum, so the palette always spans the full
range regardless of absolute volume.

> `lib/screens/stock/stock_trend_screen.dart`

---

# Module 3 — Supply (Mini-MRP)

```
planned production (C19)
        │
        ├─→ burn rate (M1) ─→ reorder level (M2)
        │        │
        │        ├─────────────────┐
suppliers ─→ effective lead (M3)   │
        └─→ best supplier (M4)     │
                  │                │
open POs ─→ inbound (M5, M6) ──────┤
                                   ↓
                          projection walk (M7)
                                   │
                    ┌──────────────┼──────────────┐
              days of cover    stock-out     order-by date
                  (M8)           (M7)            (M9)
                                   │              │
                                   └──→ risk (M10) ←┘
                                          │
                                   suggested qty (M11, M12)
```

## Stage A: Burn and thresholds

### M1 · Burn rate

```
burnRatePerDay = consumptionPerUnit × plannedProductionPerDay
```

The single bridge from Capacity into Supply. `plannedProductionPerDay` is C19,
so demand and capacity both feed every downstream supply number.

### M2 · Reorder level

```
reorderLevel      = consumptionPerUnit × plannedProductionPerDay × 7 × 0.20
belowReorderLevel = currentStock <= reorderLevel
```

A flat **20% of one week's planned consumption** — computed from planned usage
rather than typed in by hand. Deliberately distinct from the lead-time-aware
machinery below: this is a simple low-stock flag, M9/M12 are the real reorder
logic.

> `lib/services/mrp_service.dart` · `reorderLevelFor`

## Stage B: Supplier selection

### M3 · Effective lead days

```
ratingGap        = clamp( 5 − reliabilityRating, 0, 5 )
factor           = 1 + 0.5 × (ratingGap / 5)
effectiveLeadDays = ceil( leadTimeDays × factor )
```

A 5★ supplier is trusted to hit its quoted lead time. Padding scales linearly
to **+50% for a 0★ supplier**, so an unreliable supplier's deliveries are
planned for later than they are quoted. Rounded up — a partial day of lead time
is not lead time you have.

### M4 · Best supplier

```
sort by effectiveLeadDays ascending
     ties → higher reliabilityRating first
pick the first;  null when no supplier is linked
```

Selection is on **effective** lead time, so reliability already sits inside the
primary key rather than being a separate tiebreak.

> `lib/services/mrp_service.dart` · `effectiveLeadDays`, `bestSupplier`

## Stage C: Inbound and projection

### M5 · Inbound deliveries

```
openOrders  = orders where status not in { Delivered, Cancelled }
inboundTotal = Σ openOrders.quantity

date(order) = expectedDelivery
           ?? orderDate + effectiveLeadDays(order's own supplier) days
           ?? orderDate + effectiveLeadDays(material's best supplier) days
```

The fallback uses the **order's own** supplier, not the material's overall best
one — the order was placed with whoever it was placed with.

### M6 · Overdue inbound

```
overdueOrders      = inbound where date < today
overdueInboundTotal = Σ overdueOrders.quantity
```

Still counted toward cover (M7 folds them onto day 0), but surfaced separately
so the UI can flag that the projection is leaning on a late shipment.

### M7 · Projection walk

```
for i in 0 … horizonDays (180):
    day      = today + i
    balance += inbound arriving on day
    balance −= burnRatePerDay          (only when burnRatePerDay > 0)
    record balance
    if stockOutDate is null and balance < 0:
        stockOutDate = day
        daysOfCover  = i

Deliveries dated before today are folded onto day 0 rather than dropped.
```

Order matters: inbound is added **before** burn is subtracted, so a delivery
landing on the day stock would otherwise run out still saves it. Days are built
from `year/month/day + i` rather than `Duration` arithmetic, so a horizon
crossing a daylight-saving transition still lands on local midnight.

### M8 · Days of cover (material)

```
daysOfCover = (burnRatePerDay > 0 && stockOutDate != null)
    ? index of the stock-out day
    : null          rendered as "180+ days" when the horizon was exhausted
```

Null is ambiguous by design and the UI disambiguates it: no burn rate to
project against, **or** cover beyond the horizon.

> `lib/services/mrp_service.dart` · `project`

## Stage D: Acting on it

### M9 · Order-by date

```
orderByDate = stockOutDate − (effectiveLeadDays + safetyStockDays) days

null when there is no stock-out in the horizon, or no supplier
```

The latest date an order can still be placed and land before the projected
stock-out, with the safety buffer reserved. `safetyStockDays` is per-material,
defaulting to **3**.

### M10 · Risk classification

```
no supplier linked                        → noSupplier
stockOutDate != null and ≤ today          → stockedOut
orderByDate  != null and ≤ today          → reorderNow
orderByDate  within 7 days                → watch
otherwise                                 → healthy

needsAttention = risk in { reorderNow, stockedOut, watch } or belowReorderLevel
```

Evaluated in order — the first match wins, so an already-stocked-out material
never also reads as merely *reorderNow*. Note `needsAttention` also fires on M2,
which is why a material can need attention while its risk is `healthy`.

### M11 · Inbound within the cover window

```
windowEnd = today + (effectiveLeadDays + safetyStockDays + 14) days
inboundInWindow = Σ inbound where date <= windowEnd    (boundary day counts)
```

Distinct from M5's `inboundTotal`. A shipment arriving well beyond the window
does not cover today's shortfall, so it must not offset the suggestion — while
the full in-flight figure is still what's shown to the user.

### M12 · Suggested order quantity

```
targetCoverDays = effectiveLeadDays + safetyStockDays + 14
raw             = burnRatePerDay × targetCoverDays − onHand − inboundInWindow

suggestedQty = raw <= 0 ? 0 : ceil( raw / 10 ) × 10
```

Rounded up to the nearest 10 so the suggestion reads as a sensible order
quantity rather than a jagged decimal. The `+14` review period means a fresh
order does not run out again the moment it lands.

> `lib/services/mrp_service.dart` · `suggestedQty`, `_inboundWithinCoverWindow`

## Stage E: Supplier scoring

### M13 · On-time rate

```
withData = orders where status == 'Delivered'
                 and deliveredAt != null
                 and expectedDelivery != null

null when count(withData) < 3

onTimeRate = count( deliveredAt <= expectedDelivery ) / count(withData)
```

Returns null below **3 delivered orders** — too small a sample to trust. Arriving
exactly on the expected date counts as on time.

### M14 · Suggested rating

```
suggestedRating = clamp( onTimeRate × 5, 0, 5 )      null when onTimeRate is null
```

Lets a manually entered reliability rating be compared against what the
delivery history actually says.

### M15 · Latest unit price

```
latestUnitPrice = unitPrice of the order with the greatest orderDate
                  among orders where unitPrice != null

null when the supplier has no priced history
```

### M16 · Supplier comparison sort

```
1. effectiveLeadDays ascending          (same key M4 selects on)
2. unitPrice ascending                  (known prices first; unknown sort last)
3. reliabilityRating descending
```

Primary key matches M4 so the recommended row always sorts to the top.

> `lib/services/mrp_service.dart` · `compareSuppliers`, `onTimeRate`

## Stage F: Consumption and costing

### M17 · Production consumption

```
consumption[materialId] = consumptionPerUnit × unitsProduced

materials with a zero rate are omitted
```

The bill of materials for one run. In the single-product capacity model every
material is consumed in proportion to uniform output. Feeds the auto-decrement
when production is logged.

### M18 · Insufficient materials

```
insufficient = materials where consumptionPerUnit × unitsProduced > currentStock
```

A real *"you could not have made this many"* signal, surfaced as a warning when
logging production. Non-blocking — a consumption failure never undoes the
already-logged production.

### M19 · Order total

```
orderTotal = quantity × unitPrice        null when no price was recorded
```

Null rather than `RM 0.00`, so an older unpriced order renders as "—" instead of
a misleading zero.

### M20 · Inventory value

```
inventoryValue = Σ ( currentStock × unitCost )   over materials where unitCost != null
```

Materials without a recorded cost contribute **nothing** — their value is
unknown, not zero.

### M21 · Raw material movement delta

```
delta = consumption →  −|quantity|
        receipt     →  +|quantity|
        adjustment  →   quantity   (signed as entered)

newStock = currentStock + delta      rejected before writing when < 0
```

The raw-material mirror of S1, on a separate ledger table. One difference in
use: the production auto-decrement **skips** any material without enough stock
(returning its id so the caller can warn) rather than throwing, so one short
material does not fail the whole run.

> `lib/services/material_movement_service.dart`

---

# Cross-module flow

Three numbers cross module boundaries. Everything else stays local.

| Value | Produced by | Consumed by | Effect |
| --- | --- | --- | --- |
| `effectiveCapacity` (C3) | Capacity | Supply, via C19 | Caps planned production |
| `plannedProductionPerDay` (C19) | Supply | Supply M1, M2 | Sets every material's burn rate |
| `materialCeiling` (C5) | Supply data | Capacity C7, C10 | Can override the bottleneck with `RAW MATERIAL` |

The loop is worth noting: raw material stock constrains Capacity's achievable
output (C5 → C7), while Capacity's ceiling constrains Supply's planned
production (C3 → C19 → M1). They are **not** circular in practice because C5
reads current stock while C19 reads the capacity ceiling — different quantities
evaluated at the same instant, not a fixed point being solved.

Demand forecasts feed both sides: C6 sums every row for the bottleneck verdict,
while S2 and C19 filter to rows in effect today.

---

# Constants

| Constant | Value | Used by | Meaning |
| --- | --- | --- | --- |
| `reviewPeriodDays` | 14 | M11, M12 | Extra cover targeted beyond lead + safety |
| `defaultHorizonDays` | 180 | M7, M8 | How far the projection walks |
| `watchWindowDays` | 7 | M10 | Order-by date inside this reads as *watch* |
| `reorderLevelWeeklyBuffer` | 0.20 | M2 | Fraction of a week's consumption |
| `lowCoverDaysThreshold` | 7 | S5 | Below this is *Low stock* |
| `overstockDaysThreshold` | 60 | S5 | Above this is *Overstocked* |
| `safetyStockDays` | 3 (default) | M9, M11, M12 | Per-material, falls back to 3 |
| heatmap window | 84 days | S6 | 12 weeks × 7 |
| min delivery sample | 3 | M13 | Below this, on-time rate is null |

---

# Provenance and caveats

**C5–C10 are transcribed, not read from source.** Since commit `d92312f` the
authoritative bottleneck math runs server-side in the `compute_bottleneck()`
Postgres function (SECURITY INVOKER, so RLS still applies). That function's
body is **not checked into this repository**, and the Supabase MCP connection
available during transcription pointed at a different project.

C5–C10 above come from the client-side implementation the RPC replaced,
recovered from `d92312f^`. Their outputs match what the running app reports on
device (machine 1 428 / labour 2 500 → ceiling 1 428, limiter `MACHINE`), which
is consistent with these formulas — but treat them as **verified by behaviour,
not verified by source** until the SQL body is read back.

**Demand-to-stock matching is by name (S2).** There is no foreign key between
`demand_forecast.product_name` and `finished_stock.product_name`. A typo in
either silently yields `daysOfCover == null` and a *No demand set* status, which
looks identical to genuinely having no forecast.

**Two separate stock ledgers.** Finished goods (S1) and raw materials (M21) do
not share a table or a code path. They behave the same way but must be changed
in both places.

---

# Test coverage

Verified against the assertions actually present in each file, not inferred
from filenames.

| File | Covers |
| --- | --- |
| `test/capacity_service_test.dart` | C1, C2, C4, C12 |
| `test/simulator_baseline_test.dart` | C14, incl. degenerate fleets and extrapolation |
| `test/sector_comparison_test.dart` | C18 |
| `test/supply_mrp_test.dart` | C19, M1, M2, M3, M4, M5, M6, M7, M8, M9, M10, M11, M12, M13, M14, M16 |
| `test/cost_test.dart` | M15, M16, M19, M20 |
| `test/material_consumption_test.dart` | M17, M18 |
| `test/stock_cover_test.dart` | S3, S5 |
| `test/demand_forecast_test.dart` | S2 period boundaries |
| `test/formatters_test.dart` | Display formatting only |

**Not covered by Dart tests.** C5–C10 live in SQL and have no client-side test.
C3 is exercised only indirectly, through the snapshot helper the capacity tests
build. C11, C13, C15, C16, C17, S1, S4, S6, S7 and M21 are reached only through
the screens or services that call them — several are thin DB wrappers where a
unit test would assert little, but C13 (utilisation), C15 (trend averaging) and
S1/M21 (the two ledger deltas) carry real branching logic and are the strongest
candidates if coverage is extended.
