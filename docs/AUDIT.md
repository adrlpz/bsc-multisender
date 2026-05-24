# AUDIT — Multisender.sol Internal Review

**Reviewer:** SUPERAGENT (internal pre-mainnet pass)
**Commit:** `513cc9c`
**Scope:** `contracts/src/Multisender.sol` only (tests + deploy script not in scope)
**Date:** 2026-05-24
**Overall verdict:** ✅ **Ready for testnet deploy.** Mainnet deploy requires fixes M1-M2 (medium) below; lows are nice-to-have.

---

## Severity legend

| Level | Meaning |
|---|---|
| 🔴 Critical | Direct loss of funds, must fix before any deploy |
| 🟠 High | Loss/lock under specific conditions, fix before mainnet |
| 🟡 Medium | UX/economic edge case, fix recommended pre-mainnet |
| 🟢 Low | Defense-in-depth / hygiene, nice to have |
| 🔵 Info | Note, no action needed |

---

## Findings summary

| # | Severity | Title | Status |
|---|---|---|---|
| C1 | 🔴 | (none) | — |
| H1 | 🟠 | (none) | — |
| M1 | 🟡 | Fee-on-transfer / rebasing tokens skew accounting | open |
| M2 | 🟡 | No max-fee invariant during user tx (race vs `setFee`) | open |
| M3 | 🟡 | `rescueToken` / `rescueBNB` unbounded — admin can drain | open (design) |
| L1 | 🟢 | Duplicate recipient not detected on-chain | open |
| L2 | 🟢 | No self-recipient skip (sender = recipient still valid) | open (design) |
| L3 | 🟢 | `setFeeReceiver` can equal current value (no-op event spam) | open |
| L4 | 🟢 | No two-step ownership transfer (`Ownable2Step`) | open |
| L5 | 🟢 | Token call to non-contract address has no explicit check | open |
| L6 | 🟢 | Constructor accepts `_owner == address(0)` if OZ allows? | verified safe |
| I1 | 🔵 | Gas: 2-pass BNB loop (intentional, documented) | accept |
| I2 | 🔵 | `FEE_CAP` exported but unused in v1 (documented) | accept |

---

## Detail

### 🔴 Critical — none

No reentrancy, no overflow, no fund-lock, no privilege escalation observed.

---

### 🟠 High — none

The 4 admin functions are correctly `onlyOwner` gated. ReentrancyGuard is present on both batch entry points. SafeERC20 is used for all token movements. Length and value checks revert before any external call.

---

### 🟡 M1 — Fee-on-transfer / rebasing tokens skew accounting

**Where:** `multisendToken` lines 161-180.

**What:** `safeTransferFrom(sender, recipient, amt)` assumes the recipient receives exactly `amt`. For tokens with transfer fees (e.g. SAFEMOON-style), recipient gets `amt - tax`. The contract still emits `total = sum(amt)` and computes `fee = total * feeBps / 10000`, which **overcharges the sender** relative to what recipients actually received.

**Impact:** UX surprise + over-collected protocol fee. Not a fund loss, but reputational risk on a tool whose value prop is "you see exactly what gets sent".

**Fix options:**
1. Document explicitly: "Fee-on-transfer tokens not supported." Add allowlist check or revert if `balanceOf(recipient) delta != amt`.
2. Block known FoT tokens via owner-set blocklist.
3. (Cleanest) Pull `total + fee` upfront, send `amt` raw. Frontend warns user that tax tokens may under-deliver.

**Recommended:** Add a doc comment + a frontend warning. Not a contract change for v1.

---

### 🟡 M2 — `setFee` race against pending user tx

**Where:** `setFee` line 195 + `multisendToken` line 175.

**What:** Owner can call `setFee` while a user tx is in mempool. If `setFee(100)` lands first and user's `multisendToken` lands after, user pays 1% instead of expected 0.1%. No max-fee parameter is enforced per-call.

**Impact:** Trust issue. Owner can grief users, even if cap is 100 bps the user has no say.

**Fix:**
- Add optional `uint16 maxFeeBps` param to `multisendToken`. Revert if `feeBps > maxFeeBps`.
- OR add a timelock to `setFee` (e.g. 24h), so users can monitor.

**Recommended (v1.1):** add `maxFeeBps` param. Backward-compatible if defaulted via overload, but Solidity overloads are by signature so this would be a new entrypoint `multisendTokenWithMaxFee`. Acceptable as v1.1 addition.

**Mitigation today:** owner can publicly commit to never raising above 10 bps. Document in README.

---

### 🟡 M3 — Rescue functions are unbounded

**Where:** `rescueToken`, `rescueBNB` lines 213-224.

**What:** Owner can pull any amount of any token / any BNB sitting in the contract. By design the contract is transit-only, so balances should always be 0. But:
- If a user accidentally `transfer`s a token directly to the contract (skipping `multisendToken`), only owner can recover it — not the original sender.
- Owner is fully trusted to not abuse this.

**Impact:** Owner-trust assumption. Not a vulnerability, but a centralization point.

**Fix options:**
1. Add `Recovered` event with `to = original sender` + a registry mapping for direct transfers (heavy, not worth it).
2. Document the trust assumption clearly in README.
3. Use a multisig (Gnosis Safe) for `owner` — preferred.

**Recommended:** README disclaimer + use a Gnosis Safe as deployer/owner from day 1.

---

### 🟢 L1 — Duplicate recipient detection

**What:** `[0xA → 1, 0xA → 2]` is currently valid on-chain (sends total 3 to 0xA). Frontend already flags duplicates in `parsers/recipients.ts`, so this is defense-in-depth only.

**Recommendation:** Leave as-is. On-chain dedup costs O(n) storage or O(n²) compare per call → not worth the gas. Frontend warning is enough.

---

### 🟢 L2 — Sender-as-recipient

**What:** `recipients[i] == msg.sender` is allowed. Pointless but valid. Costs ~21k gas wasted per such entry.

**Recommendation:** Add frontend warning, not a contract change.

---

### 🟢 L3 — Idempotent `setFeeReceiver`

**What:** `setFeeReceiver(currentReceiver)` succeeds and emits a misleading `FeeReceiverUpdated(old=X, new=X)` event.

**Fix:** Add `if (_receiver == feeReceiver) revert AlreadySet();` or skip emit. Trivial.

**Recommendation:** Skip — not worth a redeploy.

---

### 🟢 L4 — No two-step ownership transfer

**What:** `Ownable.transferOwnership` is single-step. Mistyping the new owner = permanent loss of admin.

**Fix:** Switch to `Ownable2Step` (OZ provides). 1-line change in import + `Ownable(_owner)` → `Ownable2Step` style.

**Recommendation:** Apply in v1.1. For v1, ownership goes to a Gnosis Safe immediately post-deploy → mitigates the risk.

---

### 🟢 L5 — Token contract existence not checked

**What:** `multisendToken(0xDEAD..., recipients, amounts)` where `0xDEAD...` is a non-contract address: `safeTransferFrom` will revert because there's no code → safe by accident.

**Recommendation:** SafeERC20 in OZ ≥4.9 already handles this via `verifyCallResultFromTarget` which reverts if the target has no code. ✅ verified safe.

---

### 🟢 L6 — Constructor accepts `_owner == address(0)`?

**Verification:** OZ Ownable v5.0 reverts in `_transferOwnership(address(0))` via `OwnableInvalidOwner`. ✅ verified safe.

---

### 🔵 I1 — 2-pass BNB loop

`multisendBNB` validates everything in pass 1, transfers in pass 2. Intentional defensive pattern: if any `to/amt` is invalid, no partial transfer occurs. Costs ~5-8% extra gas vs single-pass. Acceptable for a non-custodial tool where atomicity matters.

---

### 🔵 I2 — `FEE_CAP` exported but unused

Documented in NatSpec and CONTRACTS.md. Reserved for future BNB-Standard variant. Storage cost: 0 (constant). No action.

---

## Other checks performed

| Check | Result |
|---|---|
| Reentrancy on `multisendBNB` (recipient is contract w/ fallback) | Protected by `nonReentrant` + state-free design |
| Reentrancy on `multisendToken` (token is malicious ERC777-style) | Protected by `nonReentrant`; SafeERC20; no cross-function state writes |
| Integer overflow on `total += amt` | Solidity 0.8+ checked arithmetic outside `unchecked`; `unchecked` block here is sum which can't overflow uint256 with sane amounts; **BUT** see note below |
| Zero-address recipient | Reverts with `ZeroAddress(i)` |
| Zero amount | Reverts with `ZeroAmount(i)` |
| Empty array | Reverts with `NoRecipients` |
| Length mismatch | Reverts with `LengthMismatch` |
| `msg.value > total` (overpay) | Reverts with `ValueMismatch` (good — prevents stuck dust) |
| Failed BNB transfer (recipient rejects) | Reverts with `BNBTransferFailed` (atomic — all or nothing) |
| Selector collision in errors | None observed |
| Function visibility | All correct (external for entrypoints, public for state vars via auto-getter) |
| Storage layout | `feeBps` (uint16) + `feeReceiver` (address) packed in 1 slot ✅ |
| Constructor reverts on bad params | `feeReceiver==0` and `feeBps>MAX_FEE_BPS` both checked |

### ⚠️ Note on `unchecked` total

```solidity
unchecked {
    total += amt;
    ++i;
}
```

Theoretical overflow: `total + amt > 2^256 - 1`. Practically impossible with real tokens (no token has > 2^256 supply). For BNB native, max BNB supply is ~150M ≈ 1.5e26 wei, far below 2^256 ≈ 1.16e77. ✅ safe.

---

## Mainnet checklist

Before deploying to BSC mainnet, complete:

- [ ] Owner set to a Gnosis Safe (3-of-5 or 2-of-3), not an EOA
- [ ] `feeBps = 0` at deploy (launch promo, flip to 10 after PMF validation)
- [ ] `feeReceiver` = same Safe or a separate revenue Safe
- [ ] Contract verified on BscScan (source + ABI public)
- [ ] README disclaimer about FoT tokens not supported (M1)
- [ ] README disclaimer about admin trust assumption (M3)
- [ ] Frontend warns on duplicate recipients + self-recipient (L1, L2)
- [ ] (v1.1) `maxFeeBps` parameter on `multisendToken` (M2)
- [ ] (v1.1) `Ownable2Step` (L4)
- [ ] Bug bounty program live ($500-2000) before any meaningful TVL
- [ ] Monitoring: alert if `address(this).balance > 0` for >1 block (anomaly)

---

## Test coverage gaps (not run as part of audit, recommended for v1.1)

- [ ] Reentrancy attempt via malicious ERC777 token
- [ ] Reentrancy attempt via recipient contract that re-enters `multisendBNB`
- [ ] Fee-on-transfer token interaction test (should currently mis-account)
- [ ] Gas snapshot test for 50, 500, 1000 recipients (regression guard)
- [ ] Invariant: `address(this).balance == 0` and `token.balanceOf(this) == 0` after every successful call

---

**Conclusion:** safe to deploy to **BSC testnet** as-is. Before mainnet, complete the checklist above. No critical/high findings.
