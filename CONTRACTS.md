# CONTRACTS.md - Multisender Contract Notes

Smart contract layer for the BSC Multi-Sender. Lives under `contracts/` and is built with Foundry.

## Layout

```
contracts/
├── src/Multisender.sol         # Main contract
├── test/Multisender.t.sol      # Unit + fuzz tests
├── script/Deploy.s.sol         # Deploy script
└── foundry.toml
```

## Build & Test

```bash
export PATH="$PATH:/root/.foundry/bin"
cd contracts
forge build
forge test -vv
```

19 tests, all passing. Fuzz `testFuzz_multisendBNB` runs 256 cases.

## Deploy

```bash
# .env: PRIVATE_KEY=..., FEE_RECEIVER=0x..., FEE_BPS=0
forge script script/Deploy.s.sol \
  --rpc-url $BSC_RPC \
  --private-key $PRIVATE_KEY \
  --broadcast --verify
```

Defaults: `feeReceiver = msg.sender`, `feeBps = 0` (launch-promo period).

## Spec compliance vs PRD §11

The PRD describes the Standard tier as "all BEP-20 tokens, 0.1% capped at 0.5 BNB". A
BNB-denominated cap on arbitrary BEP-20 tokens needs an oracle, which is out of MVP scope.
Implementation pragmatics:

| Aspect | PRD | Implementation |
|---|---|---|
| Free `multisendBNB` | ≤ 50 recipients, 0% fee | ✅ Same |
| Standard `multisendToken` | ≤ 1000 recipients, 0.1% fee, capped 0.5 BNB | ≤ 1000 recipients, 0.1% fee in same token, **no cap** |
| `FEE_CAP` constant | 0.5 BNB | Exported but **not enforced** in v1 |

Reasoning: charging fee in the source token avoids cross-asset pricing and keeps the
contract oracle-free. The 0.1% rate keeps even large batches economical
(e.g., 100k USDT batch → 100 USDT fee), and `setFee(uint16)` is owner-tunable up to
`MAX_FEE_BPS = 100` (1%).

The 0.5-BNB cap can be reintroduced for a future BNB-denominated Standard variant
(`multisendBNBStandard`) once a price oracle is wired in.

## Security

- OZ `Ownable` + `ReentrancyGuard`
- `SafeERC20` for transfers (handles non-standard returns)
- Length / sum / zero-address / zero-amount checks
- BNB sent via `.call{value: ...}` with success check
- Two-pass BNB loop: validate-then-transfer (prevents partial drain on bad input)
- `receive()` reverts to block stray BNB; `rescueBNB` / `rescueToken` for emergencies

## Events

- `MultisendBNB(sender, totalAmount, recipientCount)`
- `MultisendToken(sender, token, totalAmount, recipientCount, fee)`
- `FeeUpdated(oldFeeBps, newFeeBps)`
- `FeeReceiverUpdated(oldReceiver, newReceiver)`

## Constants

| Name | Value | Purpose |
|---|---|---|
| `MAX_RECIPIENTS_FREE` | 50 | Free-tier cap |
| `MAX_RECIPIENTS_STANDARD` | 1000 | Standard-tier cap |
| `MAX_FEE_BPS` | 100 (1%) | Owner cannot set fee above this |
| `FEE_CAP` | 0.5 ether | Reserved for future BNB Standard variant |
