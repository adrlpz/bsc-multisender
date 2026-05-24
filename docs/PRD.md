# PRD — BSC Multi-Sender

**Version:** 1.0.0
**Author:** Fizz (via SUPERAGENT)
**Date:** 2026-05-24
**Status:** Draft → Ready for build

---

## 1. Problem Statement

Distribusi token (BNB / BEP-20) ke banyak wallet di BSC saat ini bermasalah:

- **Manual N tx** = lambat, mahal (gas N×), error-prone (salah amount/address susah audit).
- **Disperse.app** = ada tapi UX-nya jadul, ga support permit2, no CSV validator, no batch >200, no whitelist.
- **Mass airdrop tools** = kebanyakan paid SaaS atau Telegram bot ga transparent (custodial risk).

User butuh tool **non-custodial, 1-klik, audit-friendly** untuk kirim token massal di BSC.

---

## 2. Target User Persona

### Persona A — Crypto Project Ops (primary)
- **Profil:** Founder / community manager project token kecil-menengah (market cap <$10M)
- **Pain:** Distribusi airdrop ke 100-1000 holder, payroll kontributor mingguan, reward giveaway
- **Frequency:** 2-10x/bulan
- **Willingness to pay:** $5-50 per batch atau 0.1-0.5% fee

### Persona B — KOL / Trader (secondary)
- **Profil:** KOL crypto yang sering host giveaway / paid promotion ke followers
- **Pain:** Send reward ke 20-100 winner dari Twitter/Telegram contest
- **Frequency:** weekly
- **Willingness to pay:** prefer gratis, mau pake kalau cepet

### Persona C — DAO / Treasury (tertiary)
- **Profil:** Multisig admin yang distro grant / contributor pay
- **Pain:** Butuh tool yang Safe-compatible (Gnosis Safe transaction builder)
- **Frequency:** 1-4x/bulan
- **Willingness to pay:** flat fee per batch oke

---

## 3. Goals & Success Metrics

### Product Goals
1. User bisa kirim token ke 500 wallet dalam **<60 detik** (connect → confirm → done)
2. Gas saving minimum **60%** vs send manual satu-satu
3. Zero custodial risk — semua tx user-signed, kontrak audit-able

### Success Metrics (3 bulan post-launch)
| Metric | Target |
|---|---|
| Unique wallet users | 1,000+ |
| Total batches sent | 5,000+ |
| Total value distributed | $500K+ |
| Protocol revenue (jika fee aktif) | $500-2,000/bulan |
| 404NF holder activation | 30%+ of users hold 404NF |

---

## 4. Functional Requirements

### 4.1 Core Features (MVP)

**FR-1: Wallet Connection**
- Support MetaMask, WalletConnect v2, Trust, OKX, Binance Web3 Wallet
- Auto-detect BSC, prompt switch network kalau wrong chain
- Show connected address + BNB balance + selected token balance

**FR-2: Token Selection**
- Default: BNB native
- Input custom BEP-20 contract address → fetch symbol + decimals + balance
- Recent token list (cache di localStorage)
- Whitelist common tokens: USDT, USDC, BUSD, CAKE, 404NF

**FR-3: Recipient Input**
- **Mode A — Manual paste:** textarea, format `address,amount` per baris (atau `address amount`, comma/space/tab separator)
- **Mode B — CSV upload:** drag-drop CSV, parse + preview tabel
- **Mode C — Equal split:** input list address (no amount) + total amount → auto-divide
- Validator: address format (EIP-55 checksum), no duplicate, amount >0, total ≤ balance

**FR-4: Preview & Confirm**
- Tabel preview: # | Address | Amount | Status (✓ valid / ✗ error)
- Summary: total recipients, total amount, estimated gas (BNB)
- Warning kalau ada duplicate address atau amount = 0

**FR-5: Approval Flow (BEP-20 only)**
- Cek allowance kontrak multisender ke user
- Kalau insufficient: prompt approve infinite atau exact amount (toggle)
- Skip approve untuk BNB native

**FR-6: Send Transaction**
- 1 klik → wallet popup → sign → broadcast
- Loading state dengan tx hash, link ke BscScan
- Auto-batch kalau >500 recipients (chunked, sequential confirm)
- Success: show summary + download receipt CSV

**FR-7: History**
- Tab "History" → list batch sebelumnya (dari localStorage + on-chain events)
- Re-send: load batch lama jadi draft baru

### 4.2 Nice-to-have (v1.1+)

- **Permit2 / EIP-2612:** gasless approve via signature
- **EIP-7702 batching:** delegated batch tx (pakai pattern dari 404NF)
- **Gnosis Safe support:** generate Safe transaction JSON
- **Multi-chain:** Ethereum, Polygon, Arbitrum (later)
- **Saved address books:** import/export
- **Scheduled send:** cron-based (server-side, opt-in)
- **Holder snapshot:** auto-fetch holder list dari token contract

---

## 5. Non-Functional Requirements

| Aspek | Requirement |
|---|---|
| **Performance** | UI render <500ms untuk 1000 rows; tx confirmation <15s di BSC |
| **Security** | Smart contract di-audit (internal min, eksternal kalau scale), reentrancy guard, no custodial holding |
| **UX** | Mobile-responsive, dark mode default, i18n EN+ID |
| **Accessibility** | Keyboard nav, ARIA labels, contrast ratio AA |
| **Browser** | Chrome, Brave, Firefox, Edge, Safari (last 2 versions) |
| **SEO** | Landing page optimized, OG tags, sitemap |

---

## 6. Tech Stack

### Frontend
- **Framework:** Next.js 14 (App Router) + TypeScript
- **Styling:** Tailwind CSS + shadcn/ui
- **Web3:** Wagmi v2 + Viem + RainbowKit (wallet UI)
- **State:** Zustand (lightweight)
- **CSV parser:** Papa Parse
- **Validation:** Zod

### Smart Contract
- **Language:** Solidity 0.8.24
- **Framework:** Foundry (forge + cast + anvil)
- **Pattern:** Single `Multisender.sol` dengan 2 functions: `multisendBNB()` + `multisendToken()`
- **Optional:** EIP-7702 delegate version (advanced, v1.1)

### Infra
- **Host:** Vercel (frontend) atau Cloudflare Pages
- **RPC:** BSC public RPC fallback + Ankr/Quicknode premium
- **Analytics:** Plausible (privacy) atau PostHog
- **Error tracking:** Sentry

---

## 7. Smart Contract Spec (high-level)

```solidity
contract Multisender {
    address public owner;
    uint256 public feeBps; // 0-100 (0% to 1%)
    address public feeReceiver;

    event MultisendBNB(address indexed sender, uint256 totalAmount, uint256 recipientCount);
    event MultisendToken(address indexed sender, address indexed token, uint256 totalAmount, uint256 recipientCount);

    function multisendBNB(address[] calldata recipients, uint256[] calldata amounts) external payable;
    function multisendToken(address token, address[] calldata recipients, uint256[] calldata amounts) external;

    // Admin
    function setFee(uint256 _feeBps) external onlyOwner; // max 100 (1%)
    function setFeeReceiver(address _receiver) external onlyOwner;
    function rescueToken(address token, uint256 amount) external onlyOwner; // emergency only
}
```

**Gas optimization:**
- Use `unchecked` blocks for loop counters
- Batch transfer pattern (no callback)
- Skip self-transfers
- Optional: holder benefit check via 404NF balance (gasless waiver)

---

## 8. User Flow (happy path)

```
1. User landing → klik "Launch App"
2. Connect wallet (auto-prompt switch ke BSC kalau wrong chain)
3. Pilih token (default BNB) atau paste contract BEP-20
4. Input recipients (paste / CSV / equal split)
5. Click "Preview" → tabel summary + estimasi gas
6. (BEP-20 only) Click "Approve" → sign → wait 3s
7. Click "Send" → sign → wait confirmation (~5-15s)
8. Success page: tx hash + BscScan link + download receipt CSV
9. Auto-save ke history
```

**Error paths:**
- Insufficient balance → block send, show diff
- Invalid address → highlight row red, allow inline edit
- Tx revert → show reason + retry button
- Network error → retry with backup RPC

---

## 9. Out of Scope (MVP)

- ❌ Multi-chain (BSC only first)
- ❌ NFT distribution (ERC-721 / ERC-1155)
- ❌ Custodial wallet creation
- ❌ Token swap before send
- ❌ Mobile native app
- ❌ Telegram bot interface (later via brainwave-agent integration)

---

## 10. Risk & Mitigation

| Risk | Impact | Mitigation |
|---|---|---|
| Smart contract bug → loss of funds | 🔴 High | Audit internal + bug bounty $500-2000 + Foundry fuzzing |
| RPC downtime | 🟡 Med | 3 RPC fallback (BSC public, Ankr, Quicknode) |
| User send to wrong address | 🟡 Med | EIP-55 checksum validator + double-confirm UI for large amount |
| Gas spike → tx fail | 🟢 Low | Auto-bump gas, retry queue |
| Phishing / fake clone | 🟡 Med | Verified contract, official domain only, ENS/SNS link |
| Regulator concern (sanctions) | 🟢 Low | Optional Chainalysis address screening (v1.2) |

---

## 11. Pricing & Revenue Model

### Tier 1 — Free
- Up to 50 recipients per batch
- BNB only
- No protocol fee

### Tier 2 — Standard (paid via tx)
- Up to 500 recipients per batch
- All BEP-20 tokens
- 0.1% protocol fee (capped at 0.5 BNB)

### Tier 3 — 404NF Holder
- All Standard features
- **0% protocol fee** (utility hook)
- Priority RPC
- Higher batch limit (1000)

### Tier 4 — Pro (B2B, future)
- API access for project ops
- Custom domain whitelabel
- Dedicated RPC
- Pricing: $99-499/month flat

---

## 12. Launch Checklist

- [ ] Smart contract deployed + verified di BscScan
- [ ] Internal audit done
- [ ] Frontend deployed di vercel + custom domain
- [ ] Analytics + error tracking aktif
- [ ] OG image + meta tags
- [ ] Documentation page (how-to-use)
- [ ] Twitter announcement thread
- [ ] Telegram post di komunitas BSC + 404NF
- [ ] ProductHunt launch
- [ ] Submit ke BSC ecosystem directory
