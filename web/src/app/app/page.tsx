"use client";

import { useState, useMemo } from "react";
import { ConnectButton } from "@rainbow-me/rainbowkit";
import Link from "next/link";
import { useAccount } from "wagmi";
import { formatUnits } from "viem";
import { parseRecipients, equalSplit } from "@/lib/parsers/recipients";

type Mode = "paste" | "equal";

export default function AppPage() {
  const { isConnected } = useAccount();
  const [mode, setMode] = useState<Mode>("paste");
  const [pasteInput, setPasteInput] = useState("");
  const [equalAddrs, setEqualAddrs] = useState("");
  const [equalTotal, setEqualTotal] = useState("");
  const [decimals] = useState(18); // TODO: derive from selected token

  const parsed = useMemo(() => {
    if (mode === "paste") {
      return parseRecipients(pasteInput, decimals);
    }
    return equalSplit(
      equalAddrs.split(/\r?\n/),
      equalTotal || "0",
      decimals
    );
  }, [mode, pasteInput, equalAddrs, equalTotal, decimals]);

  return (
    <div className="flex flex-1 flex-col">
      <header className="flex items-center justify-between px-6 py-4 border-b border-zinc-900 sm:px-12">
        <Link href="/" className="flex items-center gap-2 font-semibold">
          <span className="inline-block size-2 rounded-full bg-yellow-400" />
          BSC Multi-Sender
        </Link>
        <ConnectButton showBalance={false} chainStatus="icon" />
      </header>

      <main className="flex-1 px-6 py-10 sm:px-12">
        <div className="max-w-4xl mx-auto">
          <h1 className="text-2xl font-semibold tracking-tight">Send batch</h1>
          <p className="mt-1 text-sm text-zinc-400">
            Connect wallet, pilih token, paste atau upload recipients, sign.
          </p>

          {!isConnected ? (
            <div className="mt-12 rounded-2xl border border-zinc-900 p-8 text-center">
              <p className="text-zinc-400">Connect wallet dulu buat mulai.</p>
              <div className="mt-4 flex justify-center">
                <ConnectButton />
              </div>
            </div>
          ) : (
            <div className="mt-8 space-y-6">
              <section className="rounded-2xl border border-zinc-900 p-6">
                <div className="flex items-center justify-between">
                  <h2 className="font-medium">1. Token</h2>
                  <span className="text-xs text-zinc-500">
                    BNB native (default)
                  </span>
                </div>
                <p className="mt-2 text-sm text-zinc-500">
                  Token selector + balance fetch akan ada di iterasi berikutnya.
                </p>
              </section>

              <section className="rounded-2xl border border-zinc-900 p-6">
                <div className="flex items-center justify-between">
                  <h2 className="font-medium">2. Recipients</h2>
                  <div className="flex gap-2 text-xs">
                    <button
                      onClick={() => setMode("paste")}
                      className={`px-3 py-1 rounded-full border ${
                        mode === "paste"
                          ? "border-yellow-400 text-yellow-400"
                          : "border-zinc-800 text-zinc-400"
                      }`}
                    >
                      Paste
                    </button>
                    <button
                      onClick={() => setMode("equal")}
                      className={`px-3 py-1 rounded-full border ${
                        mode === "equal"
                          ? "border-yellow-400 text-yellow-400"
                          : "border-zinc-800 text-zinc-400"
                      }`}
                    >
                      Equal split
                    </button>
                  </div>
                </div>

                {mode === "paste" ? (
                  <div className="mt-4">
                    <textarea
                      value={pasteInput}
                      onChange={(e) => setPasteInput(e.target.value)}
                      rows={8}
                      placeholder={`0xabc...,1.5\n0xdef... 0.25\n# comment baris di-skip`}
                      className="w-full rounded-xl bg-zinc-950 border border-zinc-900 p-4 font-mono text-sm focus:border-yellow-400 focus:outline-none"
                    />
                    <p className="mt-2 text-xs text-zinc-500">
                      Format per line: <code>address amount</code> (separator
                      koma / spasi / tab).
                    </p>
                  </div>
                ) : (
                  <div className="mt-4 space-y-3">
                    <textarea
                      value={equalAddrs}
                      onChange={(e) => setEqualAddrs(e.target.value)}
                      rows={6}
                      placeholder={`0xabc...\n0xdef...\n0x123...`}
                      className="w-full rounded-xl bg-zinc-950 border border-zinc-900 p-4 font-mono text-sm focus:border-yellow-400 focus:outline-none"
                    />
                    <input
                      type="text"
                      inputMode="decimal"
                      value={equalTotal}
                      onChange={(e) => setEqualTotal(e.target.value)}
                      placeholder="Total amount (mis. 10)"
                      className="w-full rounded-xl bg-zinc-950 border border-zinc-900 p-3 text-sm focus:border-yellow-400 focus:outline-none"
                    />
                  </div>
                )}

                {parsed.rows.length > 0 && (
                  <div className="mt-4 rounded-xl border border-zinc-900 overflow-hidden">
                    <div className="grid grid-cols-3 gap-2 bg-zinc-950 px-4 py-2 text-xs text-zinc-500 border-b border-zinc-900">
                      <span>Address</span>
                      <span>Amount</span>
                      <span>Status</span>
                    </div>
                    <div className="max-h-64 overflow-auto">
                      {parsed.rows.slice(0, 50).map((r) => (
                        <div
                          key={r.index}
                          className="grid grid-cols-3 gap-2 px-4 py-2 text-xs border-b border-zinc-900/60"
                        >
                          <span className="font-mono truncate text-zinc-300">
                            {r.address ?? r.raw}
                          </span>
                          <span className="font-mono text-zinc-400">
                            {r.amount !== undefined
                              ? formatUnits(r.amount, decimals)
                              : "—"}
                          </span>
                          <span
                            className={
                              r.error ? "text-red-400" : "text-emerald-400"
                            }
                          >
                            {r.error ?? "ok"}
                          </span>
                        </div>
                      ))}
                    </div>
                  </div>
                )}
              </section>

              <section className="rounded-2xl border border-zinc-900 p-6">
                <h2 className="font-medium">3. Preview</h2>
                <div className="mt-3 grid grid-cols-2 sm:grid-cols-4 gap-3 text-sm">
                  <Stat label="Valid" value={String(parsed.validCount)} />
                  <Stat
                    label="Total"
                    value={formatUnits(parsed.totalAmount, decimals)}
                    suffix="BNB"
                  />
                  <Stat
                    label="Duplicates"
                    value={String(parsed.duplicates.length)}
                    danger={parsed.duplicates.length > 0}
                  />
                  <Stat
                    label="Tier"
                    value={parsed.validCount <= 50 ? "Free" : "Standard"}
                  />
                </div>
                <button
                  disabled={parsed.validCount === 0}
                  className="mt-6 w-full sm:w-auto inline-flex h-11 items-center justify-center rounded-full bg-yellow-400 px-6 font-medium text-black transition hover:bg-yellow-300 disabled:opacity-30 disabled:cursor-not-allowed"
                >
                  Send batch (placeholder)
                </button>
                <p className="mt-2 text-xs text-zinc-500">
                  Tx flow nyambung ke kontrak setelah deploy. Sekarang masih
                  preview-only.
                </p>
              </section>
            </div>
          )}
        </div>
      </main>
    </div>
  );
}

function Stat({
  label,
  value,
  suffix,
  danger,
}: {
  label: string;
  value: string;
  suffix?: string;
  danger?: boolean;
}) {
  return (
    <div className="rounded-xl border border-zinc-900 p-3">
      <div className="text-xs text-zinc-500">{label}</div>
      <div
        className={`mt-1 font-mono ${danger ? "text-red-400" : "text-zinc-100"}`}
      >
        {value}
        {suffix && <span className="ml-1 text-xs text-zinc-500">{suffix}</span>}
      </div>
    </div>
  );
}
