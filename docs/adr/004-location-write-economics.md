# ADR 004 — Location Write Economics

Status: Accepted · 2026-07-24

## Context

The driver pays for his own mobile data and his phone must survive an 8-hour working day, of which Reach's runs occupy two or three hours. V1 deliberately has no live map for parents — board and arrival events only (ADR 003) — so every location write must justify itself against an actual consumer, not an imagined one. Location is also among the most sensitive data the system touches, second only to child identity.

## Decision

**Capture only during a `started` trip.** The driver's trip page requests geolocation (browser Geolocation API, screen wake-lock where supported) from trip start to trip completion, and at no other time. No trip running — Reach asks the phone for nothing. This, not clever throttling, is what makes the battery budget work: GPS is active for the runs, never the day.

**One persisted fix per 30 seconds, and nothing else.** The page holds the freshest fix in memory and posts at most one every 30 seconds; the backend writes it to `trip_path`. There is **no separate live-ping channel in v1** — nothing consumes one. Parents get no map, and the operator's "is the run underway" view is fully served by 30-second freshness. The cheapest ping is the one never sent. If a live consumer ever ships, an ephemeral channel (held in memory with a short TTL, never persisted) bolts on beside the stored record without touching this design.

**One extra fix per driver tap.** Each state transition (start, boarded, reached school) stamps the current fix into the transition's `trip_events` context — corroboration for the record at the moments that matter, costing three-to-a-dozen extra writes per run.

**The budget, stated so it can be falsified:** ~250-byte payload posted every 30s over a kept-alive HTTPS connection is under 100 KB per 75-minute run — roughly **4 MB per month** for a twice-daily run across 22 school days. Battery: 2–3 hours of foreground GPS on run days, zero otherwise. If real-world testing shows worse, the knob is the 30-second cadence, which is per-operator configuration, not schema.

**Location belongs to the trip and the vehicle, never the child.** `trip_path` is a standard ADR 001 tenant table — `operator_id`, trip reference, timestamp, lat/lng, accuracy. No row references a child, and no query path joins a child to coordinates. A gap in the trail (phone slept, signal died) is just a gap: messages never depend on location (ADR 003), so missing fixes degrade the record, never the product's honesty.

**Retention: 30 days, then deleted** (per-operator configurable). The long-term "Proof you reached" record is the `trip_events` state trail — who tapped what, when — not GPS breadcrumbs. Paths exist to resolve near-term disputes and tune routes, and then they leave the system.

**GPS never generates claims.** Already law under ADR 003; restated here because this is the ADR someone will read before proposing a geofence. The only sanctioned future use is driver-prompt assist — "you're near the school, tap Reached when parked" — which is still a tap.

## Consequences

- (+) Data cost is invisible to the driver (~4 MB/month against multi-GB prepaid plans) and battery draw is confined to the runs.
- (+) Privacy surface is small and shrinking: coordinates tie to a vehicle's trip for 30 days, never to a child, ever.
- (+) No live-ping infrastructure to build, scale, or pay for in v1.
- (−) A browser page must stay open and foregrounded for capture; screen-off or app-switching produces gaps. Accepted: the trail is corroboration, not evidence-of-record, and drivers already run their phones mounted and on.
- (−) 30-second granularity means the operator's view can lag by half a minute; anyone wanting real-time chase must wait for a v2 ephemeral channel.
- (−) After 30 days, location disputes can no longer be settled with GPS — only with the state trail. Deliberate.
- (?) INTERVIEW-DEPENDENT, left configurable: cadence (default 30s), retention (default 30 days), whether operators want the trail visible at all in their dashboard v1 (default: yes, active-trip only).
