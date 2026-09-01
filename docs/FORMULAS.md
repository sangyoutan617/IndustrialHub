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
stageCapacity(s) = Σ ( ratedOutputPerHour × operatingHoursPerDay × unitCount )
                   over the *Active* machines whose stage == s
                   (a stage that has machine rows but no Active one contributes 0)

machineCapacity  = min( stageCapacity(s) )  over every stage that has machine rows
                   0 when no machine row exists, or when any stage is fully down
```

A line is a **flow**. Each machine belongs to a `stage` (Mixing → Extrusion →
Packaging …). Machines **in the same stage run in parallel** — their
capacities add. Distinct stages run in **series**, so the product can only go
as fast as its **slowest stage**. A blank `stage` means "its own stage": an
unstaged machine is a standalone step keyed by its own id, so a factory that
never assigns stages gets `min` over one-machine stages (each machine its own
bottleneck) rather than the old factory-wide sum.

A `machines` row is also a **group** of `unit_count` identical machines that
share one rate, schedule, stage and status (`unit_count` defaults to 1). All
units in the group count toward their stage's parallel total.

Only machines whose `status` is exactly `'Active'` contribute their rate.
Every other status — under maintenance, retired, downtime, repair — adds 0.
There is no uptime-percentage derate: a machine either counts at its full
nameplate rate or not at all. But because the stages are a series, a stage
whose machines are **all** non-Active stops the whole product: that stage's
`stageCapacity` is 0, so `machineCapacity` is 0. A stage that still has one
Active machine keeps running at that machine's rate. Actual stoppage
durations are tracked as discrete events — see `machine_downtime_log` and the
Active → Downtime → Repair → Active workflow — rather than folded into this
formula as an estimated percentage.

`machine_downtime_log.machines_down` records how many of a group's units a
given event took down. It is **informational only** — displayed on the
machine page, never folded into this sum. Logging downtime flips the group's
`status` to `'Downtime'` (and so out of C1) **only when the whole group is
down** (`machines_down >= unit_count`); a partial stoppage leaves the group
Active and its C1 contribution unchanged.

> `lib/services/capacity_service.dart` · `computeMachineCapacity`

### C2 · Manpower capacity

```
stationCapacity = workerCount × shiftHours × outputPerWorkerHour

manpowerCapacity = min( stationCapacity )  over the product's manpower rows
                   0 when there are no rows
```

Each `manpower` row is a **task station** in the labour flow (Filling,
Wrapping, Packing …), not a time shift. The stations run in series, so the
**slowest station** caps the line — the same flow logic as C1. Adding people
to a station raises that row's `workerCount`. There is no active/inactive
concept for stations.

> `lib/services/capacity_service.dart` · `computeManpowerCapacity`

## Stage 2: Ceiling and bottleneck

### C3 · Production ceiling (effective capacity)

```
effectiveCapacity = min( machineCapacity, manpowerCapacity )
```

A day's output cannot exceed either resource, so the lower one governs. Both
inputs are now themselves bottleneck minima (C1 across machine stages, C2
across labour stations), so `effectiveCapacity` is really "the slowest step
anywhere in the machine **or** labour flow". This is the figure shown as
**Daily production ceiling** on the Capacity dashboard.

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
materialCeiling = min( rawMaterial.currentStock / bomEntry.quantityPerUnit )

over this product's own product_materials (BOM) rows
where quantityPerUnit > 0
null when no BOM row qualifies
```

Scoped to the one product `compute_bottleneck()` was called for — each
product has its own bill of materials (`product_materials`), so a material
shared by several products can be scarce for one and plentiful for another.
The scarcest ingredient governs, since one exhausted input halts that
product's line regardless of the others. Rows with a non-positive rate are
skipped rather than treated as infinite — dividing by zero would poison the
minimum.

> `compute_bottleneck(p_factory_id, p_product_id)` — joins
> `product_materials`/`raw_materials` directly in SQL; see
> [Provenance](#provenance-and-caveats)

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
needs instant feedback as fields change.

### C14 · Simulated capacities

```
simMachineCapacity  = machines × machineHours × machineRate      (C1, one stage)
simManpowerCapacity = workers  × shiftHours   × outputPerWorkerHour  (C2, one station)
simEffective        = min( simMachineCapacity, simManpowerCapacity )   (C3)
```

Six raw fields, no rate-weighting. The simulator models **one machine stage
against one labour station** — it does not span a multi-stage flow. All six
fields are pre-filled from the selected product's real data: the machine
fields from that product's slowest machine stage
(`machines = Σ unitCount`, `machineHours` = the stage's first row's hours,
`machineRate = stageCapacity / (machines × machineHours)`), the labour fields
from its slowest task station verbatim. So an untouched simulator reproduces
C3 exactly when the product has a single stage and a single station, and sits
at "slowest stage vs slowest station" otherwise.

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

**Logging production writes here too.** When a day's output is logged (or
re-logged) on the production trend screen, the *change* vs the previously
logged output is applied to that product's finished stock — `production_in`
for an increase, a signed `adjustment` for a downward correction (mirroring
M17a's delta-aware material deduction). The finished-stock row is created at 0
if it doesn't exist yet. Best-effort: a failure never undoes the logged
production, and a downward correction that would push stock below zero is
surfaced rather than applied.

> `lib/services/stock_service.dart` · `recordMovement`, `recordMovementQueued`,
> `getOrCreateStockForProduct`
> `lib/screens/capacity/production_trend_screen.dart` · `_updateFinishedStock`

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
planned production per product (C19), fanned in
across every product via the BOM ─→ burn rate (M1) ─→ reorder level (M2)
                                            │
                                            ├─────────────────┐
suppliers ─→ effective lead (M3)                              │
        └─→ best supplier (M4)                                │
                  │                                            │
open POs ─→ inbound (M5, M6) ──────────────────────────────────┤
                                                                ↓
                                                       projection walk (M7)
                                                                │
                                  ┌──────────────┬──────────────┤
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
burnRatePerDay = Σ ( plannedPerProduct[bomEntry.productId]
                    × bomEntry.quantityPerUnit )

over every product_materials (BOM) row for this material,
across every product in the factory
```

The bridge from Capacity into Supply — but no longer a single rate, since a
material can be shared by several products' recipes at different rates.
`plannedPerProduct[productId]` is that product's own C19
(`plannedProductionPerDayFor`, clamped to *that product's* achievable
output), so every product using this material contributes its own share of
the burn rate, not one factory-wide number.

> `lib/services/mrp_service.dart` · `aggregateBurnRate`
> `lib/services/supply_service.dart` · `SupplyOverview.load`

### M2 · Reorder level

```
reorderLevel      = burnRatePerDay (M1) × 7 × 0.20
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
consumption[materialId] = Σ bomEntry.quantityPerUnit × unitsProduced

over that product's own product_materials (BOM) rows,
BOM lines with a zero rate are omitted
```

That product's own bill of materials for one run — the underlying math is
unchanged from before multi-product, just scoped to one product's BOM rows
instead of a single factory-wide rate. This is **never invoked from a
manually typed quantity** — the only caller is the automatic deduction that
runs whenever production is logged (M17a below), driven entirely by
`unitsProduced`, which the product's recipe then converts per material.

> `lib/services/mrp_service.dart` · `computeProductionConsumption`

### M17a · Automatic deduction on a logged (or re-logged) day

```
unitsDelta = newActualOutput − previouslyLoggedActualOutput (0 if none)

unitsDelta > 0 → consume  M17's consumption[materialId], at magnitude unitsDelta
unitsDelta < 0 → return   M17's consumption[materialId], at magnitude |unitsDelta|
unitsDelta = 0 → no movement written
```

Always automatic, never optional — there is no manual "record usage" input
for production consumption any more. Comparing against what was
*previously* logged for that exact (factory, product, day) — rather than
always deducting the full new total — means correcting an already-logged
day's output (e.g. fixing a typo) deducts or returns only the difference,
instead of double-counting the original amount. A downward correction
therefore returns stock rather than consuming more.

> `lib/services/daily_production_service.dart` · `getForDate`
> `lib/services/material_movement_service.dart` · `recordProductionConsumption`
> `lib/screens/capacity/production_trend_screen.dart` · `_openLogDialog`

### M18 · Insufficient materials

```
insufficient = BOM materials where quantityPerUnit × unitsProduced > currentStock
```

A real *"you could not have made this many"* signal, surfaced as a warning when
logging production. Non-blocking — a consumption failure never undoes the
already-logged production. Only ever evaluated on the consuming (positive
`unitsDelta`) side of M17a — a return can't fail for insufficient stock.

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

Numbers that cross module boundaries. Everything else stays local.

| Value | Produced by | Consumed by | Effect |
| --- | --- | --- | --- |
| `effectiveCapacity` (C3) | Capacity | Supply, via C19 | Caps one product's planned production |
| `plannedProductionPerDay` (C19), per product | Supply | Supply M1, M2 | Fanned across the BOM (`product_materials`) into every material that product's recipe uses — no longer a single factory-wide rate |
| `materialCeiling` (C5) | Supply data | Capacity C7, C10 | Can override the bottleneck with `RAW MATERIAL`, scoped to that product's own BOM |
| logged `actual_output` delta | Capacity (production trend) | Stock (S1) + raw materials (M21) | Adds a `production_in` finished-stock movement **and** deducts recipe materials — both delta-aware, so re-logging corrects rather than double-counts |

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

**C5–C10 now verified against source.** The authoritative bottleneck math
runs server-side in the `compute_bottleneck()` Postgres function (SECURITY
INVOKER, so RLS still applies). Its body is still **not checked into this
repository** (no `supabase/migrations` folder — schema/function changes are
applied live and recorded in commit/PR descriptions instead, see the
project's migration workflow), but the live SQL for both overloads —
`compute_bottleneck(p_factory_id)` (factory-wide, used by a couple of
not-yet-product-scoped admin/report call sites) and
`compute_bottleneck(p_factory_id, p_product_id)` (the one everything else
calls) — has been read directly via the Supabase MCP connection during this
session, most recently while removing `uptime_percent` and again while
verifying C5's BOM join, then when the machine-capacity sum gained the
`× unit_count` factor, and most recently when **both** capacity aggregates
changed from `SUM` to bottleneck `MIN`, and again when a fully-down stage was
made to zero the ceiling: machine capacity is now `MIN` over stage-grouped
sums where the group is over **all** the product's machine rows
(`GROUP BY COALESCE(NULLIF(lower(btrim(stage)),''), 'machine:'||machine_id)`)
and the per-stage sum is `SUM(CASE WHEN status = 'Active' THEN rated × hours ×
unit_count ELSE 0 END)`, so a stage with rows but no Active machine reports 0.
Manpower capacity is `MIN(worker_count × shift_hours × output_per_worker_hour)`
over the rows. The factory-wide overload keeps the same MIN logic across all
products (no worse than the old cross-product SUM blend). C5–C10 above match
that live SQL as of this writing; if the function is redefined again later,
re-read it rather than assuming these formulas still hold.

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
| `test/simulator_baseline_test.dart` | C14 prefill — slowest stage/station, parallel collapse, degenerate |
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
candidates if coverage is extended. M17a (the delta-vs-previous-log direction
switch) is the newest of these: `recordProductionConsumption`'s sign-selects-
direction logic is thin enough that its correctness rests on M17's own
(covered) math plus manual/on-device verification of the delta calculation
itself, rather than a unit test of the DB-touching wrapper.
