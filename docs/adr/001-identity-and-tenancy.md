# ADR 001 — Identity & Tenancy

Status: Accepted · 2026-07-23

## Context

Reach serves operators (maxi/H-car owners), their drivers, the children they carry, and those children's guardians. One guardian may have children with two different operators — a first-class case, not an edge case. Child data is the most sensitive thing the system holds. A missing tenant filter must never show one family's information to another operator, so isolation must be enforced in exactly one place — never by per-query discipline.

## Decision

Tenant root is the **operator**. Ownership: operator → operator_users, drivers, vehicles, routes, children, guardianships, enrolments (later: trips, invoices). `guardians` is global — one row per WhatsApp number, deliberately holding **no name** — linked to operator-scoped `children` via `guardianships` (with `notify` and `is_billing` flags). A parent with two children at two operators = one guardian row, two child rows in two tenancies. Same child at two operators = two rows (accepted v1 tradeoff).

Isolation is enforced by **Postgres row-level security**:

- Every tenant table carries `operator_id uuid NOT NULL`. One migration-template function installs the byte-identical policy on each: `USING / WITH CHECK (operator_id = current_setting('app.operator_id', true)::uuid)`, RLS FORCEd. `WITH CHECK` is mandatory — it blocks cross-tenant writes, not just reads.
- The backend connects as `reach_app` (NOSUPERUSER, NOBYPASSRLS — never the Supabase service-role key). Every tenant request runs inside a transaction that calls `set_config('app.operator_id', $1, true)`; the single helper `withTenant()` in `src/db/` is the only query path and owns BEGIN/COMMIT. Unset context → NULL → **zero rows: fails closed**.
- Cross-tenant work (webhook phone→guardian resolution, guardian create/phone-reassign, OTP issue/verify, platform admin) runs on a separate `reach_system` login through a small enumerated, audit-logged module. System-private tables (`driver_sessions`, `wa_otp_challenges`, `system_audit_log`) grant `reach_app` nothing.
- The denormalised `operator_id` is kept truthful by **composite FKs** — `(child_id, operator_id) REFERENCES children(id, operator_id)` — a disagreeing row is a constraint violation, not a latent leak.
- All tables live in schema `reach`; `anon`/`authenticated`/`service_role` are REVOKEd from the schema, so Supabase's own API paths get `permission denied` even with BYPASSRLS. CI walks the catalog on every merge: every table is TENANT (template policy, string-equal), GLOBAL_SHARED (allowlisted with reason), or SYSTEM_PRIVATE — anything else fails the build, alongside fail-closed and fence proofs against real Postgres.

Identity per actor:

- **Operator user**: Supabase Auth for the dashboard; role + operator_id resolved from `operator_users` on every request, never from JWT claims.
- **Driver**: not a dashboard user. Opens `…/d/{operator-slug}`, enters phone, gets a 6-digit WhatsApp OTP (auth-category template, 5-min expiry, hashed at rest, rate-limited, non-enumerating responses); ~180-day HttpOnly cookie whose session joins live driver status each request — disabling a driver kills access immediately. Driver phone is unique **per operator**, never globally (a driver may serve two operators as two rows).
- **Guardian**: never authenticates; identity is the WhatsApp number. In v1, **inbound messages never make a claim about a child** — STOP handling (global pause + operator surfacing) and one static reply with the operator contact block, nothing else. No code path can name the wrong child because no automated reply names a child at all. Unknown numbers get silence.
- **Child**: a data subject, not an actor. Stored: given name (exactly what the boarded message says), optional dashboard-only disambiguator, guardianships, enrolment. No surname, DOB, photo, or school records. Child names and guardian phones never appear in logs — IDs only; bind-parameter logging disabled; unique-violation messages (which embed phone numbers) caught before any logger.

## Consequences

- (+) A forgotten filter is a zero-row bug, not a leak; every new table inherits isolation from one template.
- (+) Two-guardian children, shared phones, phone changes, and two-operator drivers all have defined homes (guardianship flags; `reassignGuardianPhone` repoints only the acting operator's links).
- (−) The GUC defends against forgotten filters, **not** SQL injection — parameterised queries and lint rules stay load-bearing.
- (−) Bugs surface as silent empty results; the debugging tax is real and `withTenant()` being the only path is what keeps it tractable.
- (−) Session-level `SET` is a standing tenant-bleed footgun under pooled connections — lint-banned; only `SET LOCAL`-equivalent inside the helper.
- (−) Supabase Studio/superuser and backups bypass everything in this ADR: org membership + MFA are production access control, not IT hygiene.
- (−) CI must run real Postgres with real roles on every merge, forever.
- (−) `reach_system` attracts growth; more than ~10 functions is a design smell. Additions require review + audit coverage.
- (?) INTERVIEW-DEPENDENT, left configurable: billing per child vs per family (default: `is_billing` flag per guardianship, one payer per child); whether the static reply names children (default: no — safest for shared/observed phones); archived-child purge window (default: 365 days, survives an invoice-dispute cycle).
