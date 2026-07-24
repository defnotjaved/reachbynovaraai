# ADR 003 — Trip State Machine

Status: Accepted · 2026-07-24

## Context

The product's one unforgivable bug is a confident wrong claim to a parent — "reached school" when the child did not, or "didn't board" when they did. Every design choice here subordinates to that: uncertain states must produce silence or an explicit "we don't know", never a guess. The second constraint comes from ADR 001's doctrine: an invariant is only real if it is enforced in exactly one place, and that place should be the database.

## Decision

Two state machines, both with every legal transition enumerated — anything not listed raises an error.

**Trip** (one route-run on one service date, with a direction): `scheduled → started → completed | cancelled`, and `scheduled → cancelled`. `completed` and `cancelled` are terminal, with one guarded exception below.

**Child-per-trip** (`trip_children` row): `expected → boarded → dropped_off`, plus `expected → absent`.
- `expected → boarded` — driver tap.
- `boarded → dropped_off` — automatic for all boarded children when a to-school trip completes.
- `expected → absent` — driver tap, or automatic at trip completion for children still expected.
- Undo transitions: `boarded → expected` and `absent → expected` — legal **only while every message caused by the original transition is still queued** (see outbox below); the reverse transition and the cancellation of the queued message commit atomically.
- Illegal forever: `boarded → absent` (the correction path is deliberately two steps through `expected`), `expected → dropped_off` (cannot skip boarding), any exit from `dropped_off`.

**One place owns transitions — the database.** The `state` columns of `trips` and `trip_children` are excluded from `reach_app`'s column-level UPDATE grant; the only write path is `reach.transition_trip()` / `reach.transition_trip_child()`, single Postgres functions that whitelist the legal pairs, raise on everything else, and append every transition to `trip_events` (from/to state, actor kind and id, client timestamp, server timestamp, request id). `trip_events` is INSERT-only like the ledger — no UPDATE or DELETE grants exist. **That table is the "Proof you reached" record.** The functions run SECURITY DEFINER as a dedicated role that is itself RLS-bound with the standard tenant policy, so ADR 001's isolation guarantee survives inside them.

**The false-"reached" defence — three rules:**
1. Parent messages fire **only on affirmative driver taps**. Never from timers, geofences, GPS inference, or auto-transitions. Auto-`absent` at trip completion is recorded but never messaged — a wrong "didn't board" is nearly as trust-ending as a wrong "reached".
2. Every message goes through a **transactional outbox**: the transition and its queued message commit together, and the send fires only after a grace delay (default 60 seconds, per-operator configurable). Within that window the driver's Undo tap reverses the transition and cancels the queued message before it ever leaves. A mis-tap on a bouncing maxi costs nothing.
3. `completed → started` is permitted **only while no completion message has been sent** — the same outbox guard, so a mis-tapped "Reached school" is recoverable exactly until the messages fire, and absolutely terminal after.

**Uncertainty = silence to the parent, visibility to the operator.** A trip that never completes (dead phone, no signal) sends nothing and sits open on the operator's dashboard past its expected window. Cancelling a `started` trip freezes child states as they are, flags the trip for the operator, and sends nothing automatically — what happened next is a human conversation, not a system claim.

## Consequences

- (+) A parent can receive a wrong claim only if the driver affirmatively taps the wrong thing twice: once to make it and once by letting the grace window lapse. No code path can invent an event.
- (+) The audit trail is complete by construction — there is no way to change a state without leaving a `trip_events` row.
- (+) The undo guard is an invariant ("no caused message has been sent"), not a clock, so grace-window tuning never opens a correctness hole.
- (−) Parent messages are always at least the grace delay late. 60 seconds of latency is the price of never lying; operators can tune it down once their drivers stop mis-tapping.
- (−) Transitions living in SQL functions means testing them needs real Postgres (already true for RLS per ADR 001) and migrations for every rule change.
- (−) A driver who never taps produces silent days — the dashboard makes that visible to the operator, but Reach cannot manufacture the missing events. Adoption is operational, not technical.
- (?) INTERVIEW-DEPENDENT, left configurable: whether the pilot covers the afternoon home-bound run (schema carries `direction` from day one; default is morning-only, and home-bound drop-offs would be per-child driver taps rather than trip-completion automatic); whether parents ever get absence notifications (default: never in v1); grace delay length (default 60s).
