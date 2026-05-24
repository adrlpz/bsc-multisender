# ARCHITECTURE — BSC Multi-Sender

---

## High-level diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                         User Browser                            │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │ Next.js 14 App (App Router)                              │   │
│  │  ├─ Pages: / (landing), /app (main), /history, /docs     │   │
│  │  ├─ Components: WalletConnect, TokenSelect, Recipients,  │   │
│  │  │              Preview, Approve, Send, History          │   │
│  │  └─ State: Zustand store + localStorage                  │   │
│  └──────────────────────────────────────────────────────────┘   │
│         │              │                                        │
│         │              │                                        │
│  ┌──────▼─────┐  ┌─────▼──────┐                                 │
│  │ Wagmi v2   │  │ Papa Parse │                                 │
│  │ + Viem     │  │ (CSV)      │                                 │
│  │ + RainbowKt│  └────────────┘                                 │
│  └──────┬─────┘                                                 │
└─────────┼───────────────────────────────────────────────────────┘
          │
          │ JSON-RPC
          ▼
┌─────────────────────────────────────────────────────────────────┐
│              BSC Mainnet (chainId 56)                           │
│                                                                 │
│  RPC: https://bsc-dataseed.binance.org (+ Ankr fallback)        │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │ Multisender.sol (deployed contract)                      │   │
│  │  ├─ multisendBNB(recipients[], amounts[])                │   │
│  │  ├─ multisendToken(token, recipients[], amounts[])       │   │
│  │  ├─ setFee / setFeeReceiver / rescueToken (admin)        │   │
│  │  └─ Events: MultisendBNB, MultisendToken                 │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │ Existing BEP-20 tokens (USDT, USDC, BUSD, custom...)     │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

---

## Component breakdown

### Frontend modules

```
src/
├── app/
│   ├── page.tsx                    # Landing
│   ├── app/page.tsx                # Main multisender UI
│   ├── history/page.tsx            # Past batches
│   └── docs/page.tsx               # How-to-use
├── components/
│   ├── wallet/
│   │   ├── WalletConnect.tsx
│   │   └── NetworkSwitcher.tsx
│   ├── token/
│   │   ├── TokenSelector.tsx
│   │   └── TokenBalance.tsx
│   ├── recipients/
│   │   ├── PasteInput.tsx
│   │   ├── CsvUpload.tsx
│   │   ├── EqualSplit.tsx
│   │   └── RecipientsTable.tsx
│   ├── flow/
│   │   ├── PreviewSummary.tsx
│   │   ├── ApproveButton.tsx
│   │   ├── SendButton.tsx
│   │   └── SuccessReceipt.tsx
│   └── ui/                          # shadcn/ui primitives
├── lib/
│   ├── wagmi-config.ts
│   ├── contracts/
│   │   ├── multisender-abi.ts
│   │   └── erc20-abi.ts
│   ├── parsers/
│   │   ├── csv-parser.ts
│   │   └── address-validator.ts
│   ├── hooks/
│   │   ├── useTokenInfo.ts
│   │   ├── useAllowance.ts
│   │   ├── useMultisend.ts
│   │   └── useGasEstimate.ts
│   └── store/
│       └── batch-store.ts          # Zustand
└── styles/
    └── globals.css
```

### Smart contract

```
contracts/
├── src/
│   └── Multisender.sol
├── test/
│   ├── Multisender.t.sol            # Unit tests
│   ├── MultisenderFuzz.t.sol        # Fuzz tests
│   └── MultisenderInvariant.t.sol   # Invariant tests
├── script/
│   ├── Deploy.s.sol
│   └── Verify.sh
└── foundry.toml
```

---

## Data flow — Send batch (BEP-20)

```
1. User → paste recipients (CSV)
2. Frontend → parse + validate (Papa Parse + Zod)
3. Frontend → fetch token decimals + symbol via viem (multicall)
4. Frontend → check user balance + allowance (multicall)
5. If allowance < total → show Approve button
6. User clicks Approve → wagmi `writeContract` → token.approve(multisender, MAX)
7. Wait for receipt → reload allowance
8. User clicks Send → wagmi `writeContract` →
   multisender.multisendToken(token, recipients[], amounts[])
9. Wait for receipt → emit MultisendToken event
10. Frontend → save batch ke localStorage + show success
```

---

## Security considerations

### Smart contract
- ✅ Reentrancy guard (OpenZeppelin `ReentrancyGuard` atau check-effects-interaction)
- ✅ Integer overflow (Solidity 0.8+ default)
- ✅ Length match (`recipients.length == amounts.length`)
- ✅ Sum check (msg.value == sum(amounts) untuk BNB)
- ✅ Access control (Ownable untuk admin functions)
- ✅ Rescue function emergency only, dengan timelock di v1.1
- ❌ **TIDAK** ada token holding di kontrak (transit only)
- ❌ **TIDAK** ada user fund storage

### Frontend
- ✅ Address checksum (EIP-55)
- ✅ Amount precision (BigInt, no float)
- ✅ Total ≤ balance check pre-send
- ✅ Confirm dialog untuk send >$1000 equivalent
- ✅ HTTPS only, CSP headers
- ✅ No backend storage of user data (everything client-side + on-chain)

---

## Performance targets

| Operation | Target |
|---|---|
| Landing page load | <2s LCP |
| Wallet connect | <3s |
| Parse 1000-row CSV | <500ms |
| Validate 1000 addresses | <300ms |
| Multicall fetch (balance + allowance + decimals) | <1s |
| Tx broadcast → confirmation | 5-15s (BSC default) |

---

## Deployment

### Frontend (Vercel)
```bash
vercel --prod
```
Env vars:
- `NEXT_PUBLIC_MULTISENDER_ADDRESS`
- `NEXT_PUBLIC_BSC_RPC`
- `NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID`

### Contract (Foundry)
```bash
forge script script/Deploy.s.sol --rpc-url $BSC_RPC --broadcast --verify
```

---

## Monitoring

- **On-chain:** event listener (optional backend) untuk track total volume
- **Frontend:** Plausible (page views, conversion funnel) + Sentry (errors)
- **Alerting:** Telegram bot ping kalau contract balance >0 (anomaly, harusnya transit)
