"use client";

import Link from "next/link";
import { ConnectButton } from "@rainbow-me/rainbowkit";

const features = [
  {
    title: "1 klik kirim",
    desc: "Paste address + amount, sign sekali, selesai. Kirim ke 1000 wallet dalam 1 transaksi.",
  },
  {
    title: "Gas hemat 60%+",
    desc: "1 tx batch vs N tx manual. Save BNB tiap distro, payroll, atau airdrop.",
  },
  {
    title: "Non-custodial",
    desc: "Token transit only. Kontrak ga pegang dana lo. Audit-friendly, open source.",
  },
  {
    title: "BNB + semua BEP-20",
    desc: "USDT, USDC, BUSD, custom token. Auto-detect symbol & decimals.",
  },
  {
    title: "CSV / paste / equal split",
    desc: "Tiga mode input. Mau airdrop random, payroll fixed, atau bagi rata? Semua kepake.",
  },
  {
    title: "History on-chain",
    desc: "Tiap batch ke-emit event. Re-send & audit kapan aja dari BscScan.",
  },
];

const tiers = [
  {
    name: "Free",
    headline: "Buat tester & komunitas kecil",
    bullets: ["≤ 50 recipients per batch", "BNB only", "0% protocol fee"],
    cta: "Coba gratis",
  },
  {
    name: "Standard",
    headline: "Buat ops, payroll, airdrop",
    bullets: [
      "≤ 1000 recipients per batch",
      "Semua BEP-20 token",
      "0.1% fee, capped 0.5 BNB",
    ],
    cta: "Pakai Standard",
    accent: true,
  },
];

export default function Home() {
  return (
    <div className="flex flex-1 flex-col">
      <header className="flex items-center justify-between px-6 py-4 border-b border-zinc-900 sm:px-12">
        <div className="flex items-center gap-2 font-semibold tracking-tight">
          <span className="inline-block size-2 rounded-full bg-yellow-400" />
          BSC Multi-Sender
        </div>
        <div className="flex items-center gap-3">
          <Link
            href="/app"
            className="text-sm text-zinc-300 hover:text-white transition"
          >
            App
          </Link>
          <Link
            href="/docs"
            className="text-sm text-zinc-300 hover:text-white transition"
          >
            Docs
          </Link>
          <ConnectButton showBalance={false} chainStatus="icon" />
        </div>
      </header>

      <main className="flex flex-1 flex-col">
        <section className="px-6 py-24 sm:px-12 sm:py-32 max-w-5xl mx-auto w-full">
          <h1 className="text-4xl sm:text-6xl font-semibold tracking-tight leading-tight">
            Kirim token ke <span className="text-yellow-400">ribuan wallet</span>
            <br />
            sekali klik. Di BSC.
          </h1>
          <p className="mt-6 max-w-2xl text-lg text-zinc-400">
            Tool non-custodial buat distro BNB / BEP-20 ke banyak address
            sekaligus. Gas hemat 60%+, audit on-chain, transparan, gampang.
          </p>
          <div className="mt-10 flex flex-col gap-3 sm:flex-row">
            <Link
              href="/app"
              className="inline-flex h-12 items-center justify-center rounded-full bg-yellow-400 px-6 font-medium text-black transition hover:bg-yellow-300"
            >
              Launch App →
            </Link>
            <Link
              href="/docs"
              className="inline-flex h-12 items-center justify-center rounded-full border border-zinc-800 px-6 font-medium text-zinc-200 transition hover:border-zinc-600"
            >
              How it works
            </Link>
          </div>
        </section>

        <section className="border-t border-zinc-900 px-6 py-20 sm:px-12">
          <div className="max-w-5xl mx-auto">
            <h2 className="text-2xl sm:text-3xl font-semibold tracking-tight">
              Kenapa pake ini
            </h2>
            <div className="mt-10 grid gap-6 sm:grid-cols-2 lg:grid-cols-3">
              {features.map((f) => (
                <div
                  key={f.title}
                  className="rounded-2xl border border-zinc-900 p-6 hover:border-zinc-700 transition"
                >
                  <h3 className="font-medium text-zinc-100">{f.title}</h3>
                  <p className="mt-2 text-sm text-zinc-400">{f.desc}</p>
                </div>
              ))}
            </div>
          </div>
        </section>

        <section className="border-t border-zinc-900 px-6 py-20 sm:px-12">
          <div className="max-w-5xl mx-auto">
            <h2 className="text-2xl sm:text-3xl font-semibold tracking-tight">
              Pricing
            </h2>
            <p className="mt-2 text-sm text-zinc-500">
              Dua tier. Transparan. Ga ada upsell trap.
            </p>
            <div className="mt-10 grid gap-6 sm:grid-cols-2">
              {tiers.map((t) => (
                <div
                  key={t.name}
                  className={`rounded-2xl border p-8 ${
                    t.accent
                      ? "border-yellow-400/40 bg-yellow-400/5"
                      : "border-zinc-900"
                  }`}
                >
                  <div className="flex items-baseline justify-between">
                    <h3 className="text-xl font-semibold">{t.name}</h3>
                    {t.accent && (
                      <span className="text-xs text-yellow-400">RECOMMENDED</span>
                    )}
                  </div>
                  <p className="mt-1 text-sm text-zinc-400">{t.headline}</p>
                  <ul className="mt-6 space-y-2 text-sm text-zinc-300">
                    {t.bullets.map((b) => (
                      <li key={b} className="flex gap-2">
                        <span className="text-yellow-400">•</span> {b}
                      </li>
                    ))}
                  </ul>
                  <Link
                    href="/app"
                    className={`mt-8 inline-flex h-10 items-center justify-center rounded-full px-5 text-sm font-medium transition ${
                      t.accent
                        ? "bg-yellow-400 text-black hover:bg-yellow-300"
                        : "border border-zinc-800 text-zinc-200 hover:border-zinc-600"
                    }`}
                  >
                    {t.cta}
                  </Link>
                </div>
              ))}
            </div>
          </div>
        </section>

        <footer className="border-t border-zinc-900 px-6 py-8 sm:px-12 text-sm text-zinc-500">
          <div className="max-w-5xl mx-auto flex flex-col sm:flex-row justify-between gap-3">
            <span>BSC Multi-Sender · Non-custodial · Open source</span>
            <span>BNB Smart Chain · chainId 56</span>
          </div>
        </footer>
      </main>
    </div>
  );
}
