# Reach

School-transport visibility for Trinidad & Tobago, by Novara AI Solutions.

- **To parents:** *Know they reach.* A WhatsApp message when your child boards, and one when they arrive.
- **To drivers and operators:** *Proof you reached.* Credit for doing the job — an enrolment list, an automated monthly invoice run, and a reconciliation view.

## Product law

1. **Positioning is non-negotiable.** Never "tracking", "monitoring", or "watching" in any product string — the driver is being credited, not surveilled. CI enforces a vocabulary ban on product code (`scripts/check-positioning.sh`). If a UI string or notification reads like surveillance, it is a bug.
2. **A false "reached" message is the worst possible bug.** Uncertain states produce silence or an explicit "we don't know" — never a confident wrong claim.
3. **Invoice-only money model.** Reach generates the bill, sends reminders, and reconciles. The parent pays the operator directly. No code path may hold funds (see ADR 002).
4. **Operator isolation is enforced in the database** (Postgres RLS), never by per-query discipline (see ADR 001).
5. **Child data is minimised** — given name, guardianship, enrolment; nothing else. Names never appear in logs.

## Stack

Node/Express backend · Supabase (Postgres) · React + Vite frontend · WhatsApp Business API (Meta webhooks, HMAC-validated) · numbered `.sql` migrations.

## Layout

```
backend/    Express API (port 3001)
frontend/   React dashboard (port 5173, proxies /api → 3001)
db/         migration runner + db/migrations/NNNN_name.sql
docs/adr/   architecture decision records — read these first
scripts/    CI helper scripts
```

## Dev commands

```bash
cd backend  && npm run dev     # API on :3001
cd frontend && npm run dev     # dashboard on :5173
cd backend  && npm test        # backend tests
cd db && DATABASE_URL=postgres://... npm run migrate   # apply pending migrations
```

## CI

Three required checks on every merge to `main` (direct pushes are blocked): `lint` (backend + frontend + positioning check), `test`, and `migrate-dry-run` (all migrations applied in order against an ephemeral Postgres 15).

## ADRs

| # | Title | Status |
|---|-------|--------|
| [001](docs/adr/001-identity-and-tenancy.md) | Identity & tenancy | Accepted |
| [002](docs/adr/002-money-model.md) | Money model (invoice-only) | Accepted |
| 003 | Trip state machine | Pending |
| 004 | Location write economics | Pending |
