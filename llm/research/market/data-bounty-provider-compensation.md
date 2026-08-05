---
title: "Data Bounty & Provider Compensation — Reference Mapping"
date: "2026-08-05"
depth: "deep-dive"
request: "marketplace payment research"
companion: "two-sided-marketplace-payment-architecture.md"
---

## Executive Summary

This is the companion to
`two-sided-marketplace-payment-architecture.md`, which covered the
**consumer-pays + provider-gets-paid** money engine (`5x5x5x5/marketplace`) and
the **prepaid-credit/usage-metering** half (Lago, OpenMeter). This document
covers the **data-bounty / provider-compensation direction**: the mechanisms by
which a platform pays suppliers to contribute data, and how that compensation
is metered, verified, and distributed.

The three open-source references for this direction are all **blockchain-bound**
(the trust and money live in `.sol` Solidity contracts):

| Repo | Path on disk | License | Contribution model |
|---|---|---|---|
| oceanprotocol/market | `~/codebases/market` | Apache-2.0 | Publishers list data for sale; consumers pay via datatoken orders |
| vana-com/vana-smart-contracts | `~/codebases/vana-smart-contracts` | MIT | Contributors deposit data into a DataDAO; TEE-verified fingerprints earn token rewards |
| dataunions/dataunions (Streamr) | `~/codebases/dataunions` | (see repo) | Individuals join a Data Union; aggregated data sold; weighted earnings distributed per member |

Because none of these is a clean non-crypto reference, the practical conclusion
is: **reuse the `marketplace` engine for the money rails and model a "data
request/bounty" as a service-type, then take the *verification* and *weighted
distribution* ideas from these three**. The three blockchain repos are best read
for their incentive/verification design, not for their payment plumbing.

---

## 1. What "data bounty" means, and the two distinct money flows

A two-sided data market has two symmetric money directions:

1. **Consumer→platform→provider (access):** the buyer pays to consume data; the
   provider is compensated on sale. Covered in the companion doc.
2. **Requester→provider (supply bounty):** a business *requests* a dataset and
   pays suppliers who deliver compliant data. This is the "data bounty"
   direction.

The three references below are really answering different sub-questions of
direction 2: **how do you verify a contribution** (Vana), **how do you distribute
aggregate revenue fairly among many small contributors** (Streamr), and **how do
you price a data asset for sale** (Ocean).

---

## 2. Ocean Market — the data-commodity pricing surface

### 2.1 Provider-side pricing (`~/codebases/market/src/components/Publish/Pricing/`)

A publisher prices an asset in the publish wizard. Two pricing modes
(`Pricing/index.tsx`):

- **Fixed** — publisher sets a price; buyers pay via a **FixedRateExchange**
  (on-chain AMM) for the asset's **datatoken**.
- **Free** — access via a **Dispenser** (datatokens are dispensed for free, gated
  by the consumer's on-chain identity).

The platform margin in Ocean is explicit and small: a **market fee** set in
`app.config.cjs` (`consumeMarketOrderFee`, `consumeMarketFixedSwapFee`) and a
**market-fee address** that receives it. The provider's sale proceeds are the
datatoken price minus the market fee; the contract (not the UI) enforces the
split.

### 2.2 The purchase flow (`~/codebases/market/src/@utils/order.ts`)

`order()` is the consumer's buy path. It composes three fee legs into one
transaction:

```ts
_consumeMarketFee: { consumeMarketFeeAddress, consumeMarketFeeAmount, ... }  // platform cut
swapMarketFee / FixedRateExchange                                    // provider proceeds
_providerFee (from ProviderInstance.initialize)                      // compute/access fee
```

The `orderPriceAndFees.price` is the total the buyer pays; the datatoken
ownership is the access credential. Because the exchange and fees are on-chain,
the provider's payout is automatic and non-custodial — the platform never holds
the funds.

### 2.3 What to take from Ocean

- **Data has a price curve, not just a fixed price** — Fixed vs. Free modes, with
  the platform fee as an explicit, configurable leg.
- **Payout is protocol-enforced, not bookkept** — money moves at the moment of
  sale; there is no settlement ledger to reconcile.
- **Access control = token ownership** — owning the datatoken is the access
  credential. This is a clean pattern for "consumer paid → gets access."

---

## 3. Vana — verifying contributions and rewarding data providers

Vana (`vana-smart-contracts`, MIT) is the most complete open-source reference
for the **data-bounty / provider-compensation** direction. Its model:
contributors deposit data into a **DataDAO / Data Liquidity Pool (DLP)**; a
Trusted Execution Environment (TEE) attests the data's quality; contributors are
rewarded with tokens proportional to the attested quality.

### 3.1 The contribution + reward contract
(`contracts/dlpTemplates/dlp/DataLiquidityPoolImplementation.sol`)

The core function is `requestReward(fileId, proofIndex)` (line 331). It is the
whole verification-and-pay loop in one place:

```
1. Load the file's TEE-signed proof from the DataRegistry (fileProofs).
2. Verify the proof's instruction matches the DLP's configured proofInstruction.
3. Reject if the file already claimed a reward (FileAlreadyAdded).
4. Reject if the TEE-attested score is 0 or > 1e18 (InvalidScore).
5. Recover the signer of the proof hash and require it is a registered TEE
   (isTee) — otherwise InvalidAttestator.
6. Compute: rewardAmount = fileRewardFactor * score / 1e18
7. safeTransfer DAT tokens to the file's ownerAddress (the contributor).
8. Decrement the pool's totalContributorsRewardAmount; register the contributor.
```

The pool is funded by `addRewardsForContributors(contributorsRewardAmount)`
(line 391) — a sponsor (or the platform) tops up the reward pool.

**The key idea: compensation is gated on a hardware-verified quality score, not
on the platform's word.** The TEE attestation is the anti-abuse mechanism for
data bounties — it prevents paying for garbage or duplicated data.

### 3.2 Epoch-based reward distribution
(`contracts/dlpRewards/dlpRewardDeployer/DLPRewardDeployerImplementation.sol`)

DLPs don't get paid per-file from the treasury; they get paid per **epoch**
(period). `distributeRewards(epochId, dlpIds)` (line 176):

- Requires the epoch to be **finalized** (`EpochNotFinalized`).
- Distributes each DLP's share in **tranches** over time
  (`_distributeDlpNextTranche`, line 246) — a remediation window and
  per-tranche block spacing slow-roll the payout so a bad DLP can be penalized
  before it's fully paid (`_checkTrancheStartBlock`, line 221).
- Penalties (`withdrawEpochDlpPenaltyAmount`, line 198) claw back from the
  per-DLP reward.

The reward is computed as `rewardAmount + bonusAmount - penaltyAmount` (line
251), then split into a token reward (via `dlpRewardSwap`) and paid to the DLP's
treasury (`dlp.treasuryAddress`).

### 3.3 What to take from Vana

- **Verified contribution before payment.** The TEE score is the gate — a
  concrete, architecture-level answer to "how do we know a supplied dataset is
  real and good enough to pay for?"
- **Pooled rewards + per-unit scoring.** A reward pool is funded; each verified
  contribution draws a fraction proportional to its quality score
  (`rewardAmount = factor * score`).
- **Time-released, penalizable payouts.** Tranches + remediation window + penalty
  withdraw mean a bad actor can be clawed back before fully paid. This is the
  on-chain analog of the `marketplace` repo's append-only `Adjustment`/clawback.
- **Reward caps and slashing** are first-class (penalties reduce the pool).

---

## 4. Streamr Data Unions — fair distribution among many small contributors

Data Unions (`dataunions/dataunions`) tackle the opposite end of the bounty
problem: **many small data contributors pool their data, the aggregate is sold,
and each contributor is paid a fair share of the proceeds.** This is the
"crowdselling" model.

### 4.1 The weighted-earnings contract
(`packages/contracts/contracts/DataUnionTemplate.sol`)

The core is `refreshRevenue()` (line 176) — the revenue-distribution function:

```solidity
uint earningsPerUnitWeightScaled = newEarnings * 1 ether / totalWeight;
lifetimeMemberEarnings += earningsPerUnitWeightScaled;   // running "per-unit-weight" total
```

This is the **classic weighted pro-rata earnings model**:

- Revenue arrives (via `onTokenTransfer`/`onPurchase`).
- **Fees are taken first**: `adminFee` (the DU operator) and `protocolFee`
  (platform), capped so the two never exceed 100% (line 189).
- The remainder (`newEarnings`) is divided by `totalWeight` to get
  "earnings per unit weight".
- Each member's claim = `(lifetimeEarnings − earningsAtJoin) × memberWeight`
  (`getEarnings`, line 258). A member who joins mid-stream is only entitled to
  earnings accrued *after* join (`lmeAtJoin` snapshot).
- Weight per member is settable (`setMemberWeight`, line 407) — so contribution
  quality can be encoded as weight.

Members **withdraw** their accumulated earnings (`withdraw`, line 534), gated by
an optional `withdrawModule` that can impose limits (`getWithdrawableEarnings`,
line 275).

### 4.2 The join gate
(`packages/join-server/README.md`)

Joining a Data Union is controlled by a **join server** — an HTTP gatekeeper
that validates a prospective contributor (app secret, CAPTCHA, domain check) and
then calls the contract to add them. The base server only does signature
validation; the **default join server** additionally grants the new member
publish rights to the Data Union's data streams. This is the "requirement
gate" for who may contribute and get paid.

### 4.3 What to take from Streamr

- **Pro-rata weighted distribution** — allocate aggregate revenue by
  per-member weight, with a join-time earnings snapshot so latecomers don't
  claim earlier revenue. This is the fairest and most audit-friendly way to pay
  many small contributors from one pool.
- **Fees split at the top** — admin + protocol fees are carved out before
  distribution, keeping the platform's take explicit and auditable.
- **Withdrawal with limits** — contributors don't get a backdoor money stream;
  a module can cap/lock withdrawals.
- **A real join gate** — who is allowed to contribute (and be paid) is a
  separate, pluggable server, not hardcoded.

---

## 5. Synthesis: applying these to a non-crypto two-sided data market

The three references are on-chain, but their *design ideas* port cleanly to the
off-chain `marketplace` engine from the companion doc. The mapping:

| Data-bounty concern | Reference idea | Port to `marketplace` engine |
|---|---|---|
| Price a data asset | Ocean fixed/free + explicit market fee | A `ServiceType` with `buyer_price`; platform takes a configurable fee leg |
| Verify a contribution | Vana TEE-attested score | A `verification` step before `COMPLETED`; score gates payout (a `Completed` precondition) |
| Pool & score rewards | Vana `factor × score` from a funded pool | Prefund a wallet (Lago/OpenMeter) and draw per accepted unit |
| Fair split many→many | Streamr weighted pro-rata + join snapshot | Compute per-contributor payout by weight; snapshot at join |
| Time-released, clawable | Vana tranches + penalty | Time-gated payout + admin `clawback` adjustment (already in `marketplace`) |
| Who may contribute | Streamr join server | A gated `Availability`/onboarding step before a provider can match |
| Take rate | Streamr admin+protocol fee; Ocean market fee | `PlatformConfig.fee_pct/fixed` + `Transaction.margin` (already in `marketplace`) |

### 5.1 A concrete buildable shape

Model a **data request** as a `ServiceType` where "completion" means "the
supplier delivered a dataset that passed verification." Then:

1. **Requester** creates a quoted job (buyer pipeline) — this is the bounty.
2. **Suppliers** bid/match via the existing offer machinery; the winning supplier
   is the one whose `seller_payout` clears the margin floor.
3. **Verification** (from Vana) becomes a required transition before
   `COMPLETED`: a verifier (or TEE attestation, or automated checks) attests the
   dataset, and the payout is only computed from the attested quality score.
4. **Distribution** (from Streamr) matters when one bounty is split among many
   suppliers: compute each supplier's share by weight, snapshot at join.
5. **Payout** uses the existing escrow + `Payout` + admin `retry_payout`, and
   disputes produce append-only `Adjustment` rows (refund/clawback) exactly as
   the `marketplace` repo does.

The one genuinely hard, unsolved-in-OSS piece is **verification of arbitrary
data quality** — Vana's TEE attestation is the only open reference that treats
it as a first-class money gate. Everything else (pricing, matching, escrow,
fair distribution, clawback) is already solved by the off-chain `marketplace`
engine plus the weighted-distribution idea from Streamr.

---

## 6. Companion document

This document covers the **data-bounty / provider-compensation direction**. The
other half of the reference — the **consumer-pays + provider-gets-paid** money
engine (`5x5x5x5/marketplace`) and the **prepaid-credit/usage-metering** systems
(Lago, OpenMeter) — is covered in the companion document:

- [`two-sided-marketplace-payment-architecture.md`](two-sided-marketplace-payment-architecture.md)

Together the two documents form the complete reference for a two-sided data
market: this one for the supply/bounty direction, the companion for the money
rails and credits.

## 7. Sources (local, verified)

- `~/codebases/market/src/components/Publish/Pricing/{index,Fixed,Free}.tsx`
- `~/codebases/market/src/@utils/order.ts`
- `~/codebases/market/app.config.cjs` (market fee addresses/amounts)
- `~/codebases/vana-smart-contracts/CLAUDE.md`
- `~/codebases/vana-smart-contracts/contracts/dlpTemplates/dlp/DataLiquidityPoolImplementation.sol` (requestReward, addRewardsForContributors)
- `~/codebases/vana-smart-contracts/contracts/dlpRewards/dlpRewardDeployer/DLPRewardDeployerImplementation.sol` (distributeRewards, tranches, penalties)
- `~/codebases/vana-smart-contracts/contracts/dlpRewards/dlpRegistry/DLPRegistryImplementation.sol`
- `~/codebases/dataunions/README.md`
- `~/codebases/dataunions/packages/contracts/contracts/DataUnionTemplate.sol` (refreshRevenue, getEarnings, withdraw)
- `~/codebases/dataunions/packages/join-server/README.md`

## 7. References

- Vana: `github.com/vana-com/vana-smart-contracts` (MIT)
- Streamr Data Unions: `github.com/dataunions/dataunions`
- Ocean Market: `github.com/oceanprotocol/market` (Apache-2.0)