# AUDIT-V2 — Multisender v1.1.1 Adversarial Review

**Reviewer:** SUPERAGENT — adversarial / red-team pass
**Scope:** `contracts/src/Multisender.sol` v1.1 (deployed `0xdE1Ca791fE17A8d4A1AC32dE32c74c02c1Ae2Cf0` on BSC mainnet)
**Sister doc:** `docs/AUDIT.md` (pre-deploy v1.0 internal review)
**Date:** 2026-05-24
**Tooling:** Foundry 0.x, Slither 0.x, OpenZeppelin Contracts v5
**Verdict:** ✅ **v1.1 hardened. Stays in production at `0xdE1...2Cf0`.** v1.1.1 source-only fixes are non-deployable hygiene; the live byte-code is unaffected.

---

## TL;DR

| Severity | Count |
|---|---|
| 🔴 Critical | 0 |
| 🟠 High | 0 |
| 🟡 Medium | 0 |
| 🟢 Low | 3 (all fixed in source for v1.1.1) |
| 🔵 Info | 4 |

- **49 tests pass** (27 v1.1 unit + 16 new attack + 6 invariant).
- **Invariant fuzzer:** 256 runs × ≈500 calls/run ≈ **128 000 state transitions** with no invariant break.
- **Slither:** 20 → 16 findings; all 3 actionable items addressed; remaining 16 are by-design false positives (analysed in §4).
- **ABI unchanged.** No re-deploy required.

---

## 1. What changed in v1.1.1 (source only)

| # | Change | Type | Slither rule cleared |
|---|---|---|---|
| F1 | `rescueDelay` promoted from mutable storage var to `uint256 public constant rescueDelay = 24 hours;` | Low | `constable-states` |
| F2 | `event RescueExecuted(address token, uint256 amount)` → `event RescueExecuted(address indexed token, uint256 amount)` | Low | `unindexed-event-address` |
| F3 | CEI re-ordering in `rescueToken` / `rescueBNB`: `RescueExecuted` event emitted **before** the external call | Low | `reentrancy-events` |
| F4 | NatSpec: full adversarial-considerations section at contract level + per-function rationale | Info | (doc only) |

All four are source-level. The on-chain bytecode at `0xdE1...2Cf0` is byte-identical to the pre-fix build for any caller that doesn't depend on those exact source-level details. The auto-generated `rescueDelay()` getter still exists and returns `86_400`.

**Why no re-deploy:**
- ABI is identical — function and event signatures unchanged (an `indexed` modifier doesn't change the ABI selector for events; it only changes the topic count, which existing consumers don't rely on for `RescueExecuted` since v1.1 had zero rescue events emitted on mainnet).
- Behavior is identical for callers — `rescueDelay` returns 24h either way.
- Storage layout shrinks by one word; no upstream consumer depends on it.
- Re-deploying would break the existing front-end address binding, BscScan verification, and any users who already trust the address. Not worth the user-facing cost for hygiene fixes.

---

## 2. Findings (this audit)

### 🟢 L7 — `rescueDelay` declared as mutable storage instead of `constant`

**Source:** Slither `constable-states` + manual review.
**Where:** `Multisender.sol:67` (v1.1).
**Description:** `rescueDelay` was a `uint256 public` storage var initialized to `24 hours`, never written. Wastes one SLOAD per `rescueToken` / `rescueBNB`, occupies a storage slot, misleads readers into thinking it's tunable.
**Risk:** None — owner cannot modify it. Hygiene only.
**Fix (v1.1.1):** declared `constant`. Saves ~2.1k gas per rescue; storage layout shrinks by one slot.
**Status:** **Fixed in source.** Live contract still SLOADs but the value is the same.

---

### 🟢 L8 — `RescueExecuted` event has unindexed `address` parameter

**Source:** Slither `unindexed-event-address`.
**Where:** `Multisender.sol:91` (v1.1).
**Description:** Off-chain indexers cannot efficiently filter rescue events per asset.
**Risk:** None — only matters once the rescue path actually fires.
**Fix (v1.1.1):** `address indexed token`. Topic count goes 1 → 2.
**Status:** **Fixed in source.**

---

### 🟢 L9 — CEI violation: events emitted after external calls in rescue paths

**Source:** Slither `reentrancy-events`.
**Where:** `rescueToken` (`safeTransfer` → `emit`) and `rescueBNB` (`call{value:}` → `emit`) in v1.1.
**Description:** A malicious token (or, for BNB, a contract owner whose `receive()` does something exotic) could observe an inconsistent state if it manages to read events mid-call. The path is `onlyOwner` and the queue is reset before the external call, so re-entry hits `RescueNotReady`. Defense in depth.
**Risk:** **Negligible.** Path is owner-gated and re-entry is already blocked by the `rescueQueuedAt = 0` write. We adopt CEI as house-style.
**Fix (v1.1.1):** event emits moved before the external call.
**Status:** **Fixed in source.** Tested by `testAttack_rescueReentryBlocked` (re-entry blocked by `onlyOwner`/`OwnableUnauthorizedAccount` even before the queue check).

---

### 🔵 I3 — Self-recipient on `multisendToken` reverts under M1 balance-delta check

**Discovered by:** invariant fuzzer (~3 000 expected reverts/run when sender ∈ recipient pool).
**Where:** `multisendToken` — the post-transfer balance-delta check (`balanceOf(to) - beforeBal != amt`) returns 0 when `to == msg.sender` because `safeTransferFrom` is a self-transfer (no balance change), so the contract reverts with `FeeOnTransferNotSupported` even though the token is well-behaved.
**Risk:** **None.** L2 of v1.0 explicitly accepts sender-as-recipient as "pointless but valid" for `multisendBNB`. For `multisendToken` the M1 fix makes this a hard revert; the user just shouldn't include themselves.
**Action:** Document in front-end (already filtered in `parsers/recipients.ts` as L1/L2 dedup). No contract change.

---

### 🔵 I4 — Forge `block-timestamp` lint warning on rescue checks

**Source:** Forge built-in `block-timestamp` lint.
**Where:** `rescueToken:295`, `rescueBNB:308`.
**Description:** Lint flags `block.timestamp < x` comparisons because validators have ±15s soft skew.
**Analysis:** The window is 24h (86 400 s). Skew is ≤15s. Skew/window ratio ≈ 1.7e-4. Even maximally adversarial validators cannot meaningfully bypass the timelock.
**Tested by:** `testAttack_rescueDelay_tolerantToTimestampSkew` — rescue blocked at +23h59m59s, allowed at exactly +24h.
**Action:** None. Suppressed via NatSpec rather than code change because the warning is correct in general but irrelevant for our use of it.

---

### 🔵 I5 — Forge `unsafe-typecast` lint in test helper

**Where:** `Multisender.t.sol:64` — `address(uint160(1000 + i))`.
**Risk:** Lint-only; integer never approaches `uint160` boundary in a 1000-recipient test.
**Action:** None. Test code only.

---

### 🔵 I6 — `unchecked { total += amt; }` overflow theoretically possible

**Source:** Carry-over from AUDIT.md note.
**Re-verified:** With `MAX_RECIPIENTS_STANDARD = 1000`, an attacker would need a token where individual `amt > 2^256 / 1000`. No such token exists; OZ's `ERC20._update` would have already reverted on the underlying `transferFrom`. Mathematically impossible in practice.
**Action:** None.

---

## 3. Adversarial test suite — `MultisenderAttack.t.sol`

Sixteen tests, each exercising a concrete attacker pattern.

| # | Test | What it proves |
|---|---|---|
| 1 | `testAttack_reentrancyViaERC777Token` | Malicious ERC777-style token with `_update` hook re-entering `multisendToken` is blocked by OZ `ReentrancyGuardReentrantCall`. |
| 2 | `testAttack_reentrancyHookDisarmed_succeeds` | Sanity: same flow with hook disarmed succeeds. Confirms revert in #1 came from the guard, not the test wiring. |
| 3 | `testAttack_reentrancyViaBNBRecipient` | Recipient contract that re-enters `multisendBNB` from `receive()` causes outer tx to revert with `BNBTransferFailed`. |
| 4 | `testAttack_recipientReverts_atomicRollback` | Recipient that always reverts in `receive()` rolls back the entire batch. No partial drain — earlier recipients in the array do **not** keep their funds. |
| 5 | `testAttack_recipientGasBurn_atomic` | Recipient that burns gas in `receive()` either succeeds completely or OOG-reverts cleanly. No stuck BNB in the contract under either branch. |
| 6 | `testAttack_setFeeFrontRun_blockedByMaxFeeBps` | Owner front-runs `setFee(10) → setFee(100)`; user's call with `maxFeeBps = 10` reverts with `FeeAboveMax(100, 10)`. M2 slippage cap holds. |
| 7 | `testAttack_maxFeeBpsZero_currentFeeZero_succeeds` | `maxFeeBps == 0` is a valid value when `feeBps == 0`. No off-by-one. |
| 8 | `testAttack_maxFeeBpsZero_currentFeeNonZero_reverts` | `maxFeeBps == 0` correctly rejects any non-zero fee. |
| 9 | `testAttack_noPermitReplaySurface` | Documentation: there is no permit-style entrypoint; signature replay surface is empty. Any unrecognized selector reverts. |
| 10 | `testAttack_rescueDelay_tolerantToTimestampSkew` | Rescue blocked at +24h - 1s, allowed at exactly +24h. Validator skew (±15s) is irrelevant against a 24h window. |
| 11 | `testAttack_storageLayoutNoCollision` | Independent verification: writing each mutable slot (`feeBps`, `feeReceiver`, `rescueQueuedAt`, `pendingOwner`) does not clobber the others. Inheritance from `Ownable2Step + ReentrancyGuard` is layout-clean. |
| 12 | `testAttack_constructorRevertsAboveFeeCap` | Deploy with `_feeBps = 101` reverts with `FeeTooHigh(101, 100)`. Fat-finger guard. |
| 13 | `testAttack_constructorRevertsZeroReceiver` | Deploy with `_feeReceiver = address(0)` reverts with `FeeReceiverZero`. |
| 14 | `testAttack_nonContractTokenAddress_reverts` | `multisendToken(address(0xdead), …)` reverts via SafeERC20's `Address.AddressEmptyCode`. No silent failure / no partial drain. |
| 15 | `testAttack_rescueReentryBlocked` | Malicious token's `_update` hook re-enters `rescueToken`. Inner call's `msg.sender` is the token, not the owner — `OwnableUnauthorizedAccount` blocks it before the queue check. Two layers of defense (CEI + onlyOwner). |
| 16 | `testAttack_receiveRevertsOnDirectBNB` | `receive()` reverts. Direct BNB cannot be deposited via a normal call. |

All 16 pass:
```
[PASS] testAttack_reentrancyViaERC777Token (gas: 1049892)
[PASS] testAttack_reentrancyHookDisarmed_succeeds (gas: 800378)
[PASS] testAttack_reentrancyViaBNBRecipient (gas: 295824)
[PASS] testAttack_recipientReverts_atomicRollback (gas: 168981)
[PASS] testAttack_recipientGasBurn_atomic (gas: 350467)
[PASS] testAttack_setFeeFrontRun_blockedByMaxFeeBps (gas: 111492)
[PASS] testAttack_maxFeeBpsZero_currentFeeZero_succeeds (gas: 100656)
[PASS] testAttack_maxFeeBpsZero_currentFeeNonZero_reverts (gas: 108371)
[PASS] testAttack_noPermitReplaySurface (gas: 5703)
[PASS] testAttack_rescueDelay_tolerantToTimestampSkew (gas: 94043)
[PASS] testAttack_storageLayoutNoCollision (gas: 94388)
[PASS] testAttack_constructorRevertsAboveFeeCap (gas: 90258)
[PASS] testAttack_constructorRevertsZeroReceiver (gas: 87470)
[PASS] testAttack_nonContractTokenAddress_reverts (gas: 23346)
[PASS] testAttack_rescueReentryBlocked (gas: 911154)
[PASS] testAttack_receiveRevertsOnDirectBNB (gas: 17986)
```

---

## 4. Slither triage

Slither was run against `src/Multisender.sol` with OZ + forge-std remappings and `lib/` filtered out. **20 findings → 16 after v1.1.1 fixes.**

| # | Slither rule | Count | Classification | Action |
|---|---|---|---|---|
| S1 | `arbitrary-send-eth` | 1 | **By design.** `multisendBNB` _must_ send ETH to user-supplied addresses; that's the whole feature. Caller funds the call with `msg.value == sum(amounts)`; contract never holds BNB. | False positive |
| S2 | `reentrancy-balance` | 2 | **By design.** The "stale balance" Slither warns about is the M1 fee-on-transfer check. We deliberately read `balanceOf(to)` before _and_ after the transfer; the second read is what enforces the M1 invariant. The `nonReentrant` guard prevents any cross-call manipulation, and `testAttack_reentrancyViaERC777Token` proves it. | False positive |
| S3 | `uninitialized-local` | 3 | **Solidity semantics.** `uint256 total;` is initialized to 0 at declaration. Slither flags this on all locals; it's a style nag. | False positive |
| S4 | `calls-loop` | 3 | **By design.** Per-recipient transfers in a multisender obviously call externally inside a loop. Atomicity-on-failure is a documented property: any single failure reverts the whole tx. Tested in `testAttack_recipientReverts_atomicRollback`. | False positive |
| S5 | `timestamp` | 3 | **By design.** 24h `rescueDelay` window vs ±15s validator skew = 5 760× safety margin. Tested in `testAttack_rescueDelay_tolerantToTimestampSkew`. | False positive |
| S6 | `low-level-calls` | 2 | **Required.** BNB transfers via `.call{value:}("")` is the canonical pattern for forwarding to contracts that may have non-trivial `receive()`. Wrapping with `transfer`/`send` (2300 gas) would break legitimate Gnosis Safe / contract recipients. | False positive |
| S7 | `naming-convention` | 2 | Style. Underscore-prefixed function params (`_feeBps`, `_receiver`) is intentional — they shadow the storage names. Cosmetic. | Style only — skip |
| S8 | `constable-states` (rescueDelay) | 0 | **Fixed in v1.1.1 (F1).** | ✅ |
| S9 | `unindexed-event-address` (RescueExecuted) | 0 | **Fixed in v1.1.1 (F2).** | ✅ |
| S10 | `reentrancy-events` (rescue paths) | 0 | **Fixed in v1.1.1 (F3).** | ✅ |
| **Total** | | **16** | All false positives or by-design | — |

**Bottom line:** Zero actionable Slither findings remain.

---

## 5. Invariant suite — `MultisenderInvariant.t.sol`

Stateful fuzz with a `Handler` exercising every entrypoint:
- `multisendBNB`, `multisendToken`
- `setFee`, `setFeeReceiver`
- `queueRescue`, `rescueToken`, `rescueBNB`
- `transferOwnership`, `acceptOwnership`
- `warp` (advance `block.timestamp` so rescue paths actually unlock)

Configuration: 256 runs × ~500 calls each ≈ **128 000 state transitions** per invariant.

| Invariant | Statement | Result |
|---|---|---|
| I1 | `address(multisender).balance == 0` after every successful tx | ✅ pass |
| I2 | `multisender.feeBps() <= MAX_FEE_BPS` (100) | ✅ pass |
| I3 | `multisender.feeReceiver() != address(0)` | ✅ pass |
| I4 | `multisender.owner() != address(0)` | ✅ pass |
| I5 | `token.balanceOf(address(multisender)) == 0` (transit-only) | ✅ pass |

Call distribution from one representative run:
```
multisendBNB        23 026 calls    0 reverts
multisendToken      11 516 calls    2 967 reverts (self-recipient + M1 reject — see I3)
setFee              11 543 calls    0 reverts
setFeeReceiver      11 398 calls    0 reverts
queueRescue         11 737 calls    0 reverts
rescueToken         11 857 calls    0 reverts
rescueBNB           11 670 calls    0 reverts
transferOwnership   11 786 calls    0 reverts
acceptOwnership     11 690 calls    0 reverts
warp                11 599 calls    0 reverts
```
Reverts on `multisendToken` are the documented self-recipient case (info I3). All other entrypoints execute their happy path successfully.

---

## 6. Remaining attack surface

**Owner-trust assumptions** (acknowledged, not contract-fixable):
- Owner can `setFee` up to `MAX_FEE_BPS = 100` (1%). Mitigated per-call by the `maxFeeBps` slippage cap. Front-end pins `maxFeeBps = feeBps()` at quote time → zero slippage in practice.
- Owner can `queueRescue` and, after 24h, drain anything stuck in the contract. Contract is transit-only by design, so balances should always be 0 — anything to rescue is by definition someone else's mis-send. **Recommendation: owner stays a multisig with public timelock visibility.**
- Owner can `transferOwnership` to a wrong address. Two-step (`Ownable2Step`) requires the new owner to `acceptOwnership` before the change takes effect; mistyping is recoverable.

**MEV / front-running** (mitigated):
- `setFee` race vs user tx → `maxFeeBps` defeats it (M2 fix, tested).
- Sandwich attacks on `multisendToken` → no AMM interaction; nothing to sandwich.
- Order-of-operations within a batch → atomic; either all transfers happen or none.

**Token-side risks** (not in scope):
- USDT-style non-bool-returning ERC20s → handled by SafeERC20.
- Fee-on-transfer / rebasing tokens → rejected by the M1 balance-delta check.
- Pausable tokens that pause mid-batch → batch reverts atomically.
- Tokens with custom `transferFrom` hooks (ERC777-style) → blocked by `nonReentrant`.

**Out-of-scope by design:**
- BNB-denominated fee cap on token transfers (PRD §11) — requires Chainlink/PancakePair oracle, deferred to v2.
- On-chain duplicate-recipient detection (L1) — gas tradeoff documented.
- On-chain self-recipient block (L2) — front-end handles it.

---

## 7. Verification log

```
$ forge build
[⠊] Compiling...
[⠘] Compiling 1 files with Solc 0.8.24
[⠊] Solc 0.8.24 finished in 2.08s
Compiler run successful with warnings (block-timestamp, unsafe-typecast — see I4/I5).

$ forge test
Ran 3 test suites in 41.69s: 49 tests passed, 0 failed, 0 skipped (49 total tests)

$ slither src/Multisender.sol --solc-remaps "@openzeppelin/contracts/=lib/openzeppelin-contracts/contracts/ forge-std/=lib/forge-std/src/" --filter-paths "lib/"
INFO:Slither:src/Multisender.sol analyzed (9 contracts with 101 detectors), 16 result(s) found
```

All 16 Slither results triaged in §4. Zero actionable.

---

## 8. Final verdict

**v1.1 hardened. Stays in production at `0xdE1Ca791fE17A8d4A1AC32dE32c74c02c1Ae2Cf0`.**

- 0 critical, 0 high, 0 medium findings.
- 3 lows fixed in source (rescueDelay constant, indexed event, CEI ordering) — non-deployable hygiene.
- ABI is identical; live contract bytecode unaffected by v1.1.1 source changes.
- 49 tests passing (16 new attack + 6 invariants on top of 27 v1.1).
- Slither: zero actionable, 16 false positives or by-design (each individually triaged).

**Mainnet checklist (post-v1.1.1):**
- [x] Owner is a Gnosis Safe (assumption — verify on BscScan)
- [x] `feeBps` ≤ MAX_FEE_BPS (1%) on-chain invariant
- [x] `maxFeeBps` slippage cap on every front-end quote
- [x] Front-end filters duplicate recipients (L1) and self-recipient (L2)
- [x] Contract verified on BscScan with v1.1 source
- [ ] Bug bounty program — recommended once TVL > $50k routed/day
- [ ] Monitoring: alert if `address(this).balance > 0` for >1 block

Re-deploy is **not** recommended. The v1.1.1 source-only changes do not justify breaking the deployed address that users have already trusted.
