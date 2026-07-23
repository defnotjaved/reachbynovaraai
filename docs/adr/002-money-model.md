# ADR 002 — Money Model (Invoice-Only)

Status: Accepted · 2026-07-23

## Context

Parents pay operators TT$200–400 per child per month, overwhelmingly in cash handed to the driver or conductor on the maxi. Operators spend every month chasing it. If a parent's payment ever lands in a Novara-controlled account before reaching the operator, Novara is issuing e-money in T&T: CBTT EMI approval, TT$500,000–1,000,000 minimum capital, PSP registration, and FIUTT registration, with no published de-minimis exemption. No T&T provider has been confirmed to support split settlement — assume it does not exist.

## Decision

Reach is the **record of money, never the route for it**. There are two flows, and they never mix:

1. **Parent → operator** (the school-run fees Reach bills for). Reach generates monthly invoices, sends WhatsApp reminders, and records what the operator's side receives. Settlement is direct to the operator: cash to the driver/conductor (the dominant rail — v1 optimises for it), bank transfer against a Reach reference code, or, in future, a pay-link that settles into an account the operator owns. **No code path may hold, route, split, or net these funds.**
2. **Operator → Novara** (our revenue). Novara charges the operator a service fee for Reach — flat or percentage, pricing TBD — settled by the operator on their cadence (weekly is the working assumption). In v1 this is out-of-band and manual, like any vendor invoice. It is never deducted from parent money, because Novara never holds parent money to deduct from.

Mechanics for flow 1:

- **Append-only ledger.** `ledger_entries` follows the ADR 001 tenant template. Entry types: `invoice_issued` (debit), `payment_recorded` (credit), `adjustment` (signed reversal). The `reach_app` role has INSERT and SELECT only — **no UPDATE or DELETE grants exist on this table**, so immutability is a database fact, not a convention. Corrections are reversing entries, always.
- **Balance derived, never stored.** A balance is `SUM(entries)` per enrolment, computed in views/queries. No `balance` column exists anywhere in the schema.
- **Idempotent on every external reference.** The invoice run is idempotent on unique `(enrolment_id, billing_period)` — re-running a month cannot double-bill. Payment recording is idempotent on unique `(operator_id, external_ref)` where a reference exists. Reminder sends dedupe on (invoice, template, day).
- **A payment is an attestation.** V1 "paid" means the operator marks it, recorded with who, when, method (`cash`, `bank_transfer`, `wallet`, `other`) and who physically received it (driver/conductor vs owner). Reach is the record, not the bank; disputes are parent↔operator, with the ledger as evidence.
- **TTD only**, `numeric(8,2)`, amounts from `enrolments.monthly_fee_ttd`, calendar-month billing periods.

## Consequences

- (+) Zero licensing exposure: Novara is billing software plus a vendor invoice, two shapes regulators already understand.
- (+) Future rails slot in without touching this ADR, provided settlement stays operator-owned: a per-operator WiPay Me link in reminders (config, not architecture); later the WiPay Payments API keyed to the operator's own account — Reach holding the operator's API key is a credential, not custody — with the callback auto-recording payments through the `external_ref` idempotency; operator-owned e-money wallets (PayWise, PAYPR, etc.) as a recorded method.
- (−) **Forbidden architecture, permanently:** central collection into any Novara account with payouts to operators. That is e-money issuance regardless of which provider sits in front of it.
- (−) Reconciliation is only as strong as attestation until a processor callback exists; "paid" is the operator's word, timestamped.
- (−) No refund machinery: a refund is the operator's own cash act, recorded as an `adjustment`.
- (?) INTERVIEW-DEPENDENT, left configurable: proration for mid-month starts (default: none — full month, operator can waive via adjustment); whether cash is received by driver, conductor, or owner (recorded per payment, no schema change either way); Novara fee shape (flat vs percentage) and cadence (weekly default).
