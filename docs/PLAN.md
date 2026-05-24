# PLAN — BSC Multi-Sender

**Timeline target:** 2-3 minggu MVP → live mainnet
**Mode:** Solo dev (Fizz) + SUPERAGENT pair-programming

---

## Milestones

### M0 — Setup (Day 1) ✅ in progress
- [x] PRD + Plan + Architecture docs
- [x] Repo init (lokal git)
- [ ] Push ke GitHub remote (butuh URL + token dari Fizz)
- [ ] Foundry project scaffold
- [ ] Next.js app scaffold

### M1 — Smart Contract (Day 2-4)
- [ ] `Multisender.sol` core: `multisendBNB`, `multisendToken`
- [ ] Foundry tests: unit + fuzz + invariant
- [ ] Gas optimization pass (target <50k gas overhead per recipient)
- [ ] Deploy script untuk testnet (BSC chapel) + mainnet
- [ ] Deploy ke BSC testnet → verify di testnet.bscscan
- [ ] Internal audit checklist (reentrancy, integer overflow, access control)

### M2 — Frontend Core (Day 5-9)
- [ ] Next.js 14 + App Router + Tailwind + shadcn/ui setup
- [ ] RainbowKit + Wagmi + Viem config (BSC mainnet + testnet)
- [ ] Landing page (hero + features + CTA)
- [ ] Connect wallet flow + network switcher
- [ ] Token selector (native + custom contract)
- [ ] Recipients input (3 modes: paste / CSV / equal split)
- [ ] Validator + preview tabel
- [ ] Approval + send flow
- [ ] Success page + history (localStorage)

### M3 — Polish & Test (Day 10-13)
- [ ] Mobile responsive pass
- [ ] Dark mode default
- [ ] i18n EN + ID
- [ ] Error states + edge cases (insufficient balance, invalid CSV, RPC fail)
- [ ] E2E test flow di testnet (manual + Playwright optional)
- [ ] Performance: 1000-row CSV parse <500ms

### M4 — Launch (Day 14-17)
- [ ] Deploy contract ke BSC mainnet
- [ ] Verify di BscScan + publish source
- [ ] Frontend deploy ke Vercel + custom domain (multisender.404nf.xyz atau standalone)
- [ ] Analytics setup (Plausible)
- [ ] Sentry error tracking
- [ ] OG image + meta tags + sitemap
- [ ] How-to-use docs page
- [ ] Twitter thread + Telegram launch post
- [ ] First 10 beta users (manual outreach komunitas BSC)

### M5 — Iterate (Week 3+)
- [ ] Permit2 integration (gasless approve)
- [ ] EIP-7702 batched delegate (gasless approve)
- [ ] Gnosis Safe support
- [ ] Address book + ENS resolver
- [ ] Holder snapshot tool (fetch from token contract)

---

## Daily Breakdown (estimate)

| Day | Focus | Output |
|---|---|---|
| 1 | Docs + scaffold | PRD ✓, repo ✓, Foundry init, Next.js init |
| 2 | Contract design | `Multisender.sol` v1, basic tests |
| 3 | Contract testing | Fuzz + invariant tests, gas optimization |
| 4 | Contract deploy | BSC testnet deployed + verified |
| 5 | FE base | Wallet connect, network switch, layout |
| 6 | FE input | Token select, recipients paste mode |
| 7 | FE input | CSV upload + equal split mode |
| 8 | FE flow | Approve + send + success page |
| 9 | FE history | localStorage + re-send |
| 10 | Polish | Mobile, dark mode, error states |
| 11 | i18n | EN + ID |
| 12 | E2E test | Testnet full flow validation |
| 13 | Buffer | Bug fix + UX tuning |
| 14 | Mainnet deploy | Contract live + verified |
| 15 | FE deploy | Vercel live |
| 16 | Launch | Twitter + Telegram + docs |
| 17 | Beta users | First 10 manual outreach |

---

## Resource Requirements

### Tools / Services
- **Foundry** (free) — already installed di server
- **Node.js 20** (free)
- **Vercel** (free tier OK untuk MVP)
- **BSC RPC:** public free + Ankr free tier
- **BscScan API key** (free)
- **Domain** ($10/year, optional pakai subdomain dulu)
- **GitHub repo** (free)

### Capital
- Deploy gas: ~0.05 BNB ($30 USD estimate)
- Buffer: 0.1 BNB ($60)
- **Total: ~$100 init**

### Manpower
- Solo dev (Fizz) full focus 2-3 minggu
- Optional: 1 designer pass utk landing (kalau perlu)

---

## Dependencies & Blockers

- **GitHub repo:** Fizz harus kasih URL + PAT (atau username untuk gue setup remote)
- **Domain:** decide subdomain (multisender.404nf.xyz?) atau standalone (sendmany.xyz?)
- **Branding:** logo + nama final (BSC Multisender? SendMany? BulkSend BSC?)
- **Audit:** internal cukup utk MVP, eksternal ($2-5k) optional setelah TVL >$100k

---

## Success Criteria (MVP)

✅ MVP dianggap sukses kalau dalam 2 minggu post-launch:
- 50+ unique wallets pake
- 100+ batches sent
- $50k+ total value distributed
- Zero custodial incident / loss of funds
- <5% tx fail rate
