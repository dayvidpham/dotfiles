---
title: "Two-Sided Marketplace Payment Architecture — Reference Mapping"
date: "2026-08-05"
depth: "deep-dive"
request: "marketplace payment research"
---

## Executive Summary

This document maps the payment and credit architecture of four open-source
references relevant to building a two-sided data marketplace (customers pay for
data access; businesses can additionally pay providers to supply data). The
primary structural reference is **`5x5x5x5/marketplace`** (MIT, Python/FastAPI),
a generic two-sided pay/payout engine whose buyer-price vs. seller-payout split,
platform margin, escrow, payout, and dispute lifecycles map almost one-to-one
onto the requested model. The billing/credit half (the hypercredits analog) is
covered by **Lago** (MIT, prepaid credit wallets) and **OpenMeter** (Apache,
usage metering + credit grants). The data-commodity/listing half is covered by
**Ocean Protocol's Market** (Apache, data publishing + purchase).

The key architectural insight: **a two-sided market is really two money legs
around one platform-margin ledger.** Buyer charges and seller payouts are
computed independently, booked as separate immutable cash records, and reconciled
against a third `Transaction` ledger that holds only the platform's spread. This
document reverse-engineers that design from source and extracts the invariants a
built-from-scratch implementation should adopt.

---

## 1. The reference codebases (local clones)

| Repo | Path on disk | Language/Stack | License | Role in this research |
|---|---|---|---|---|
| 5x5x5x5/marketplace | `~/codebases/marketplace` | Python, FastAPI, SQLAlchemy, Stripe | MIT | Two-sided pay/payout engine (primary) |
| getlago/lago | `~/codebases/lago` | Ruby/Rails (api submodule) | MIT | Prepaid credit wallets + metering |
| openmeterio/openmeter | `~/codebases/openmeter` | Go | Apache-2.0 | Usage metering + credit grants |
| oceanprotocol/market | `~/codebases/market` | TypeScript/Next.js | Apache-2.0 | Data marketplace listing/purchase |

All line references below are to these clones. Note: `lago/api` and `lago/front`
are git submodules; the billing logic lives in `lago/api` (initialized during
this research).

---

## 2. Marketplace: the money model

### 2.1 Core doctrine (from `marketplace/CLAUDE.md`)

Six non-negotiables shape the whole design:

1. **Information asymmetry is a model-layer invariant.** `BuyerJobView`,
   `SellerJobView`, `SellerOfferView`, `BuyerDisputeOut`, `SellerDisputeOut`,
   `AdminDisputeOut` are separate Pydantic views; buyer endpoints return buyer
   views, seller endpoints return seller views. Each side sees only its own
   number. This is enforced by the response-model metadata, not by hope.
2. **Money is `Decimal`, quantized at the boundary.** `models.to_money`
   (2 dp, half-up) is the single money gate. The pricing pipeline stays pure
   `float` (multiplicative ratios); quantization happens only where money is
   stored or compared.
3. **`Payment`/`Payout` record cash movement; `Transaction` stays the margin
   ledger.** They are deliberately separate tables. `Transaction.margin` books
   at job completion regardless of the payout provider's status.
4. **The margin floor is checked net-of-fees.** Both enforcement sites compare
   against `matching.required_spread(buyer_price, margin_floor, fees)`, never
   the gross spread.
5. **`adjustments` is append-only; `Transaction` rows are immutable.** A dispute
   resolution never edits a booked row; it appends `refund`/`clawback`/
   `chargeback_loss`/`chargeback_fee` rows and reports gross and net margin.
6. **Providers are reached only through `payments/port.py`.** `fake.py` and
   `stripe_provider.py` are the only two implementations; the API layer never
   imports a provider SDK directly.

### 2.2 The persisted schema (`marketplace/src/marketplace/entities.py`)

```
ServiceType  (service_type_id, base_buyer_price, base_seller_payout)
Pipeline     (service_type_id, buyer[], seller[])        # adjuster name lists
PlatformConfig (singleton row id=1: margin_floor, fee_pct/fixed, matching_strategy, adjuster_params)
SellerProfile (id, tier, capacity, rating_sum/count, completed_jobs, provider_account_id, payments_ready)
BuyerProfile  (id, completed_jobs, rating_sum/count)
Quote        (id, buyer_id, service_type_id, buyer_price, created_at, expires_at)   # single-use
Job          (id, quote_id, buyer_id, service_type_id, buyer_price,
               seller_id, seller_payout, status, accepted_at, completed_at)
Offer        (id, job_id, seller_id, seller_payout, status, offered_at, expires_at, responded_at)
Transaction  (id, job_id, buyer_price, seller_payout, margin, completed_at)  # admin ledger
Payment      (id, job_id [unique], buyer_id, amount, fee_estimate, status, provider_payment_id, client_secret)
Payout       (id, job_id [unique], seller_id, amount, status, provider_transfer_id)
Dispute      (id, job_id [unique], source, buyer_id, reason, status, refund_amount, clawback_amount,
               provider_dispute_id, resolved_at)
Adjustment   (id, job_id, dispute_id, kind [REFUND|CLAWBACK|CHARGEBACK_LOSS|CHARGEBACK_FEE], amount, provider_ref)
WebhookEvent (id, provider_event_id [unique])           # dedup ledger
IdempotencyRecord (principal, key [unique], path, response_status, response_body)
```

Key design choices visible in the schema:

- **Two independent money columns on `Job`**: `buyer_price` and `seller_payout`.
  They are computed by separate pipelines and are never required to be related
  by a fixed ratio — the platform margin is whatever falls between them.
- **`Transaction` is the only revenue-recognition record.** `margin` is booked
  at completion; `Payment`/`Payout` are cash-lifecycle records that can diverge
  from it (a payout may later fail; a charge may be refunded).
- **`Fee` is a stamp-time snapshot.** `Payment.fee_estimate` is computed once at
  charge time from the platform fee config and never recomputed.
- **Money is `Numeric(12,2)`** with a `CheckConstraint("amount >= 0")` on
  `Adjustment`; the sign of an adjustment lives in its `kind`, never the amount.

### 2.3 The pricing engine (`marketplace/src/marketplace/pricing.py`)

Buyer and seller prices are computed independently via **pluggable adjuster
pipelines**. An adjuster is `(price, ctx) -> price`; a pipeline runs a configured
ordered list of adjusters per service-type, per side. Registering a new adjuster
requires code; composing/tuning does not.

```python
# Pure float ratios; money is quantized only at the boundary.
@register("surge_by_demand_ratio")      # buyer-side surge from live demand/supply
@register("time_of_day_multiplier")     # either side, per-hour multiplier
@register("new_buyer_discount")         # buyer-side, first-job discount
@register("supply_incentive")           # seller-side bonus when demand > supply
@register("seller_tier_multiplier")     # seller-side, by tier
```

`PricingContext` carries `side`, `now`, `buyer_completed_jobs`, `seller_tier`,
`live_supply`, `live_demand`, and per-adjuster `params`. All adjuster parameters
are clamped via `_bounded()` at read time (a bad admin value can't drive prices
negative or to infinity).

### 2.4 The matching engine (`marketplace/src/marketplace/matching.py`)

`matching.py` is the single place a seller's payout is computed
(`seller_payout_for`) and the single place the margin floor is enforced
(`passes_floor`). Strategies are pluggable: `cheapest_payout`, `fifo`,
`highest_rated`. All strategies share:

```python
def effective_floor(buyer_price, floor) -> Decimal:
    return max(floor.absolute, floor.pct * buyer_price)

def required_spread(buyer_price, floor, fees) -> Decimal:
    return effective_floor(buyer_price, floor) + estimated_fee(buyer_price, fees)

def passes_floor(buyer_price, payout, floor, fees) -> bool:
    return (buyer_price - payout) >= required_spread(buyer_price, floor, fees)
```

The floor is **net of estimated fees** — the platform must clear its margin
*and* the payment provider's cut, or the match is rejected.

### 2.5 The end-to-end lifecycle (from `marketplace/src/marketplace/api.py`)

The full flow, with the enforcing function and line:

```
BUYER                          SELLER                           PLATFORM
----                           ------                           --------
1. POST /v1/buyer/quotes       —                                compute buyer pipeline price
   (create_quote, api.py:557)  —                                probe cheapest payout; bump
                                                                price up to clear floor,
                                                                never leaking seller_payout
2. POST /v1/buyer/jobs         —                                delete quote (single-use),
   (create_job, api.py:621)    —                                _match_and_offer → EXPIRED
                                                                or create Offer (T-timed)
                                 OFFER_RECEIVED (2-min clock)
3. (poll)                      POST /v1/seller/offers/{id}/accept
                               (accept_offer, api.py:1031)
                               — locks SellerProfile (capacity),
                                 locks Job, calls
                                 provider.charge_buyer INSIDE the
                                 locked region (atomic commit),
                                 books Payment
                               — offer→ACCEPTED, job→ACCEPTED
                                 (or AWAITING_PAYMENT if async)
4. (webhook) payment_succeeded → job→ACCEPTED (if it was AWAITING_PAYMENT)
   (_apply_payment_event, api.py:1929)
5. work happens
6. POST /v1/seller/jobs/{id}/complete
   (complete_job, api.py:1127) — books Transaction (margin ledger),
                                 calls provider.transfer_to_seller
                                 (escrow exit), books Payout.
                                 Transfer failure does NOT fail
                                 completion — payout→FAILED, admin
                                 retries via retry_payout
7. POST /v1/buyer/jobs/{id}/review  → rating
8. disputes/chargebacks (below)
```

**Escrow-equivalent:** the buyer's charge is captured at offer acceptance
(`charge_buyer` inside the locked region), and the seller's payout is only
transferred at job completion (`transfer_to_seller`). The platform holds the
buyer's money as float between capture and payout — this *is* the escrow.

### 2.6 Concurrency and locking (the DB's job, `api.py`)

The repo's stated rule: *"Concurrency is the DB's job."* There is no process-level
lock. The patterns that make this safe:

- **`session.get(X, id, with_for_update=True)`** for every status transition —
  quote consumption, offer accept, job complete, capacity check.
- **Canonical lock order: Payment → Job.** Commented explicitly at
  `api.py:676-679`: locking Job first would ABBA-deadlock against a racing
  webhook. `_sweep_stale_payments` and `_apply_payment_event` both follow
  Payment-then-Job.
- **`populate_existing=True`** on the locked re-read after an unlocked peek
  (`cancel_job` api.py:684, `_sweep_stale_payments` api.py:263). Without it, the
  identity-map's cached attributes would mask state that changed between the
  unlocked select and the locked re-get.
- **Charging inside the locked region** (`accept_offer` api.py:1057-1069): the
  capacity increment and the payment commit atomically; on `PaymentError`
  everything rolls back and the offer stays acceptable. The outbound idempotency
  key means a retry reuses the same PaymentIntent.
- **Idempotency keys on every outbound leg** — `charge:{job.id}`,
  `transfer:{job.id}`, `refund:{job.id}[:...]`, `reversal:{job.id}:dispute`.

### 2.7 Idempotency (`marketplace/src/marketplace/idempotency.py`)

Client-facing idempotency via an optional `Idempotency-Key` header on POSTs:

- First response is stored per `(principal, key)` and replayed byte-for-byte,
  except 401/403 (auth-state answers, not operation outcomes) and 5xx.
- Same key on a different path → 409.
- **The response is buffered and only forwarded AFTER the IdempotencyRecord
  commits** (finding F2b): the record must be durable before the client can
  possibly retry, or an immediate same-key retry re-executes instead of
  replaying.
- If storing the replay record fails after the domain work committed, it's
  logged and swallowed rather than turning a success into a 500.
- `/v1/auth/*` is excluded — auth responses carry raw bearer tokens that must
  never be captured.
- Known limitation (documented): a true race on concurrent duplicates lets both
  execute; the unique constraint drops one record and downstream row locks make
  the duplicate safe. A reserve-then-execute two-phase insert is the upgrade if
  exactly-once matters most.

### 2.8 Webhook handling (`_apply_payment_event`, `api.py:1929`)

The provider event sink is **unauthenticated by design** — authenticity comes
from the provider's signature (verified in `parse_webhook`). Duplicates no-op via
the `WebhookEvent` dedup ledger. The normalized `PaymentEvent` routes to the row
it affects:

- `payment_succeeded` / `payment_failed` → the `Payment` by
  `provider_payment_id` (locked). `REFUNDED` is terminal — late events never
  resurrect the charge. A late success after a void must not resurrect a dead
  job (`api.py:1942-1953`).
- `account_updated` → updates `SellerProfile.payments_ready`.
- `transfer_paid` / `transfer_failed` → the `Payout` by `provider_transfer_id`.
- `chargeback_opened` → creates/annotates a provider-sourced `Dispute`.
- `chargeback_closed` → sets `CHARGEBACK_WON`/`CHARGEBACK_LOST` (unless admin
  already arbitrated), books `CHARGEBACK_LOSS` + `CHARGEBACK_FEE` adjustments.

### 2.9 Dispute resolution (`resolve_dispute`, `api.py:1603`)

The most careful money-handling code in the repo. The shape:

1. **All 4xx guards hoisted before ANY provider call** — a 4xx must never fire
   after money has already moved. Refund can't exceed `buyer_price`; clawback
   can't exceed `seller_payout`; a FAILED payout (no money the seller kept) can't
   be clawed back.
2. **Pin amounts + commit, THEN run provider legs.** The pin survives a later
   provider-leg rollback, forcing retries to converge on the same amounts
   instead of silently diverging after a leg already executed.
3. **Provider legs are idempotent by key** (`refund:{job.id}:dispute`,
   `reversal:{job.id}:dispute`). A failure raises 502 with nothing further
   recorded; the retry replays the succeeded leg and completes the other.
4. **Re-acquire the row lock after the pin's commit** (which released it) with
   `populate_existing=True` before mutating status — sees a concurrent winner.
5. **Book append-only `Adjustment` rows** (`REFUND`, `CLAWBACK`), never edit
   `Transaction` or `Payment.status`. A partial refund leaves the charge
   `SUCCEEDED`; `REFUNDED` stays reserved for the cancel path's full refund.

### 2.10 Margin accounting (`margins_summary`, `api.py:1776`)

The financial-reporting view is a **cash view**, not accrual:

```
gross_revenue       = Σ buyer_price over completed Transaction rows
seller_payouts      = Σ seller_payout over Transaction rows
platform_margin     = Σ margin over Transaction rows
take_rate           = platform_margin / gross_revenue
adjustments_net     = Σ amount × sign (REFUND −1, CLAWBACK +1,
                      CHARGEBACK_LOSS −1, CHARGEBACK_FEE −1)
platform_margin_net = platform_margin + adjustments_net
fees_estimated      = Σ Payment.fee_estimate where status in (SUCCEEDED, REFUNDED)
platform_margin_net_of_fees = platform_margin_net − fees_estimated
```

The docstring flags the cash-view subtleties: a fee is sunk the moment a charge
captures, so refunded jobs' fees show as losses, and charged-but-in-flight jobs
dip net until their margin books at completion.

### 2.11 The payment provider port (`payments/port.py`)

The seam between the marketplace and money movers. The app only talks to this
`Protocol`; `fake.py` (dev/tests) and `stripe_provider.py` (production) implement
it. Amounts cross as 2-dp Decimals and convert to integer minor units at the edge
(`to_minor_units`). The port surface:

```
create_seller_account(seller_id, *, idempotency_key) -> AccountResult
onboarding_link(provider_account_id, return_url) -> str
charge_buyer(*, buyer_id, amount, currency, job_id, idempotency_key) -> ChargeResult
cancel_charge(provider_payment_id) -> None
refund(provider_payment_id, *, idempotency_key, amount=None) -> RefundResult
transfer_to_seller(*, provider_account_id, amount, currency, job_id, idempotency_key) -> TransferResult
reverse_transfer(provider_transfer_id, *, amount, idempotency_key) -> ReversalResult
parse_webhook(payload, signature) -> PaymentEvent
```

The Stripe adapter (`payments/stripe_provider.py`) uses **Controller-properties
connected accounts** (the legacy Standard/Express/Custom types are deprecated),
`PaymentIntents` for buyer charges, `Transfers` for payouts, and signed webhooks.
It deliberately fails fast at construction if `STRIPE_WEBHOOK_SECRET` is empty
(an empty secret would let forged webhooks pass HMAC verification). Transfer
failure handling is instructive: `cancel_charge` treats "already canceled" as
success so a void that preceded a DB rollback stays retryable instead of wedging
the job (`stripe_provider.py:111-125`).

---

## 3. The billing/credit half (hypercredits analog)

### 3.1 Lago — prepaid credit wallets (Ruby/Rails, in `lago/api`)

Lago's wallet model is the closest open-source analog to Hypcreds-style prepaid
credits. The relevant tree:

```
app/models/wallet.rb                          # the wallet aggregate
app/models/wallet_transaction.rb              # funding/spending entries
app/models/wallet_credit.rb
app/models/wallet_target.rb
app/models/usage_monitoring/wallet_credits_balance_alert.rb
app/services/wallets/create_interval_wallet_transactions_service.rb  # recurring top-ups
app/services/wallets/balance/allocate_ongoing_usage_by_wallets_service.rb  # deduct as usage accrues
app/services/credits/allocate_prepaid_credits_by_wallets_service.rb  # fund the wallet
app/services/validators/wallet_transaction_amount_limits_validator.rb
app/models/usage_monitoring/wallet_credits_ongoing_balance_alert.rb  # low-balance alert
```

Key concepts to borrow:
- **Wallets are fed by funding transactions** (`allocate_prepaid_credits`) and
  **drained by usage** (`allocate_ongoing_usage`). Credits are an entry-ledger,
  not a magic number.
- **Interval top-ups** for recurring plans (`create_interval_wallet_transactions`).
- **Low-balance alerts** are a first-class model, not a dashboard afterthought.

### 3.2 OpenMeter — usage metering + credit grants (Go)

OpenMeter splits the problem into metering (raw usage events) and entitlements
(how much the customer is allowed). The relevant tree:

```
openmeter/openmeter/meter/                     # raw usage event metering
openmeter/openmeter/entitlement/metered/       # metered usage vs. balance
openmeter/openmeter/credit/                    # credit ledger
openmeter/openmeter/credit/grant/              # credit grants (the "wallet" analog)
openmeter/openmeter/billing/charges/creditpurchase/   # buying credits
openmeter/openmeter/billing/charges/models/creditrealization/  # realizing credits against usage
openmeter/openmeter/billing/models/creditsapplied/      # applying credits to invoices
```

OpenMeter's model is the cleaner mental model for Hyper: **usage is metered
continuously; credit grants pre-fund consumption; entitlements gate it.** This
maps directly onto hypercredits (a prepaid grant of metered tokens).

---

## 4. The data-commodity half (Ocean Protocol Market)

Ocean Market (`~/codebases/market`, Apache-2.0, Next.js) is the closest
"both-directions" data reference: providers publish datasets for sale, consumers
pay to access. The relevant code:

- `src/pages/publish/` and `src/components/Publish/` — provider listing flow
- `src/pages/asset/` and `src/components/Asset/AssetActions/` — consumer purchase
- `src/@utils/order.ts` — the buy/compute order flow
- `src/@types/subgraph/OrdersData.d.ts` — the on-chain order record

Its payout mechanics are blockchain-native (datatokens, automated market makers,
fixed-rate exchanges), so it is best paired with the off-chain rails from
`marketplace` for a non-crypto implementation. Its value here is the **data
listing + access-control** surface, not the money movement.

---

## 5. Synthesis: a buildable architecture for a two-sided data market

Combining the strongest elements, a minimal-but-correct implementation would be:

| Concern | Borrow from | Core idea |
|---|---|---|
| Pay/payout split | `marketplace` | Independent `buyer_price` / `seller_payout` columns; platform keeps the spread |
| Money safety | `marketplace` | `Decimal` quantized at boundary; immutable `Transaction` ledger; append-only `Adjustment` |
| Escrow | `marketplace` | Charge buyer at accept; pay seller at completion; platform holds the float |
| Idempotency | `marketplace` | `Idempotency-Key` header; durable-before-replay; idempotency keys on every provider leg |
| Concurrency | `marketplace` | DB row locks, canonical Payment→Job order, `populate_existing` |
| Webhooks | `marketplace`/Stripe | Signature-verified, dedup ledger, `REFUNDED` terminal |
| Disputes | `marketplace` | Hoist 4xx guards, pin amounts, idempotent legs, append-only adjustments |
| Prepaid credits | Lago | Wallet = funding − usage entry ledger; interval top-ups; low-balance alerts |
| Usage metering | OpenMeter | Meter events continuously; credit grants pre-fund; entitlements gate |
| Data listing/access | Ocean Market | Provider publish + consumer purchase of data assets |

### 5.1 Invariants worth adopting verbatim

1. A buyer's view never contains the seller's payout, and vice versa.
2. Money is quantized `Decimal` at every storage/compare boundary; the pricing
   core stays pure `float`.
3. Cash movement (`Payment`/`Payout`) is separate from the margin ledger
   (`Transaction`); a payout failure never rewrites the completed margin.
4. The platform margin floor is checked **net of estimated provider fees**.
5. Dispute/refund outcomes are append-only adjustments; booked rows are immutable.
6. Every outbound provider call carries an idempotency key; the client response
   is only released after the replay record commits.
7. Provider SDKs are reached only through a port; the API never imports them.

### 5.2 Known gaps / where to extend for the data-supply direction

The `marketplace` reference covers "consumer pays + provider gets paid" but the
**data-bounty direction** (businesses requesting data and paying suppliers to
provide it) is symmetric: it is the same `buyer_price`/`seller_payout` machinery
with the roles' data objects swapped. The genuinely open-source mature examples
of that direction (Ocean Protocol, Vana, Streamr Data Unions) are blockchain-
bound; the cleanest non-crypto path is to reuse the `marketplace` engine and
model a "data request" as a service-type whose compliance is the supplied
dataset. The `marketplace` repo itself has no credit/ledger for pre-funded
access — that half comes from Lago/OpenMeter.

---

## 6. Companion document

This document covers the **consumer-pays + provider-gets-paid** money engine and
the prepaid-credit/usage-metering half. The **data-bounty / provider-compensation
direction** (businesses paying suppliers to supply data, verification, and fair
distribution among many contributors) is covered in the companion document:

- [`data-bounty-provider-compensation.md`](data-bounty-provider-compensation.md)
  — Ocean Market pricing, Vana verified-contribution rewards, Streamr Data
  Unions weighted distribution, and how to port them onto the `marketplace`
  engine.

Together the two documents form the complete reference for a two-sided data
market: this one for the money rails and credits, the companion for the supply/
bounty direction.

## 7. Sources (local, verified)

- `~/codebases/marketplace/CLAUDE.md` — design doctrine and non-negotiables
- `~/codebases/marketplace/src/marketplace/models.py` — domain enums + views
- `~/codebases/marketplace/src/marketplace/entities.py` — persisted schema
- `~/codebases/marketplace/src/marketplace/pricing.py` — adjuster pipelines
- `~/codebases/marketplace/src/marketplace/matching.py` — payout + margin floor
- `~/codebases/marketplace/src/marketplace/api.py` — lifecycle, webhooks, disputes
- `~/codebases/marketplace/src/marketplace/idempotency.py` — client idempotency
- `~/codebases/marketplace/src/marketplace/payments/{port,fake,stripe_provider}.py`
- `~/codebases/marketplace/docs/superpowers/plans/2026-07-12-payments-stripe-connect.md`
- `~/codebases/marketplace/docs/tryout-findings-2026-07-16.md` — F1/F2 finding history
- `~/codebases/lago/api/app/services/wallets/` and `app/models/wallet*.rb`
- `~/codebases/openmeter/openmeter/{meter,entitlement,credit}/`
- `~/codebases/market/src/{pages/publish,pages/asset,@utils/order.ts}`