# BSC Multi-Sender 🚀

> Tool untuk kirim BNB / BEP-20 token ke banyak wallet sekaligus di jaringan BSC dengan **1x klik**.

**Status:** Planning → MVP build
**Owner:** Fizz
**Stack:** Next.js 14 + Wagmi/Viem + Solidity (Foundry) + Tailwind

---

## Quick links

- [PRD](./docs/PRD.md) — produk, user, requirements, success metrics
- [PLAN.md](./docs/PLAN.md) — roadmap, milestone, timeline, risk
- [ARCHITECTURE.md](./docs/ARCHITECTURE.md) — tech stack & flow

---

## TL;DR

| Aspek | Detail |
|---|---|
| **Network** | BNB Smart Chain (mainnet, chainId 56) + testnet (97) |
| **Asset** | BNB native + semua BEP-20 token (USDT, USDC, BUSD, custom) |
| **Mode** | Equal split / Custom amount per wallet / CSV upload |
| **Max wallets** | 500 per tx (gas-bound), unlimited via batching |
| **UX** | 1 klik approve + 1 klik send (atau permit2 / EIP-7702 untuk gasless approve) |
| **Auth** | Wallet connect (MetaMask, WalletConnect, Trust, OKX) |
| **Fee model** | Optional 0.1% protocol fee (revenue) atau gratis untuk holder 404NF |

---

## Why ini cuan?

1. **Airdrop ops** — tim crypto bayar mahal buat distro token (Disperse.app dulu charge fee, sekarang masih dipake puluhan ribu user).
2. **Gas saving** — 1 tx vs N tx = potong gas 60-80%.
3. **Hook ke 404NF** — holder dapet diskon → driver utility token.
4. **Recurring use case** — payroll crypto, reward distro, marketing campaign.
