"use client";

import { useState, useMemo, useEffect } from "react";
import { ConnectButton } from "@rainbow-me/rainbowkit";
import Link from "next/link";
import { useAccount, useBalance, useChainId } from "wagmi";
import { formatUnits, isAddress, getAddress, maxUint256 } from "viem";
import { bsc, bscTestnet } from "wagmi/chains";

import { parseRecipients, equalSplit } from "@/lib/parsers/recipients";
import { useTokenInfo } from "@/lib/hooks/useTokenInfo";
import { useFeeBps } from "@/lib/hooks/useFeeBps";
import { useApprove, useMultisend } from "@/lib/hooks/useMultisend";
import { MULTISENDER_ADDRESS } from "@/lib/wagmi-config";

type Mode = "paste" | "equal";
type Asset = "BNB" | "TOKEN";

const NATIVE_DECIMALS = 18;
const NATIVE_SYMBOL = "BNB";

export default function AppPage() {
  const { address, isConnected } = useAccount();
  const chainId = useChainId();
  const isBsc = chainId === bsc.id || chainId === bscTestnet.id;
  const explorerUrl = chainId === bsc.id ? "https://bscscan.com" : "https://testnet.bscscan.com";

  const [asset, setAsset] = useState<Asset>("BNB");
  const [tokenAddr, setTokenAddr] = useState("");
  const [mode, setMode] = useState<Mode>("paste");
  const [pasteInput, setPasteInput] = useState("");
  const [equalAddrs, setEqualAddrs] = useState("");
  const [equalTotal, setEqualTotal] = useState("");

  // ---- on-chain state ----
  const native = useBalance({ address, query: { enabled: !!address } });
  const { feeBps } = useFeeBps();
  const tokenValid = asset === "TOKEN" && isAddress(tokenAddr);
  const { info: tokenInfo, isLoading: tokenLoading, refetch: refetchToken } = useTokenInfo({
    token: tokenValid ? getAddress(tokenAddr) : undefined,
    user: address,
    spender: MULTISENDER_ADDRESS,
    enabled: tokenValid,
  });

  const decimals = asset === "BNB" ? NATIVE_DECIMALS : tokenInfo?.decimals ?? 18;
  const symbol = asset === "BNB" ? NATIVE_SYMBOL : tokenInfo?.symbol ?? "TOKEN";
  const userBalance =
    asset === "BNB" ? native.data?.value ?? 0n : tokenInfo?.balance ?? 0n;
  const allowance = asset === "TOKEN" ? tokenInfo?.allowance ?? 0n : maxUint256;

  const parsed = useMemo(() => {
    if (mode === "paste") return parseRecipients(pasteInput, decimals);
    return equalSplit(equalAddrs.split(/\r?\n/), equalTotal || "0", decimals);
  }, [mode, pasteInput, equalAddrs, equalTotal, decimals]);

  // ---- tier / validation ----
  const limit = asset === "BNB" ? 50 : 1000;
  const tier = asset === "BNB" ? "Free" : "Standard";
  const overLimit = parsed.validCount > limit;
  const fee = asset === "TOKEN" ? (parsed.totalAmount * BigInt(feeBps)) / 10_000n : 0n;
  const requiredAllowance = parsed.totalAmount + fee;
  const insufficientBalance = userBalance < requiredAllowance;
  const needsApprove = asset === "TOKEN" && allowance < requiredAllowance;

  // ---- write hooks ----
  const approve = useApprove();
  const multisend = useMultisend();

  // After approve confirmed → refetch allowance
  useEffect(() => {
    if (approve.isSuccess) {
      refetchToken();
      approve.reset();
    }
  }, [approve.isSuccess, refetchToken, approve]);

  function handleSend() {
    const validRows = parsed.rows.filter((r) => !r.error);
    const recipients = validRows.map((r) => r.address!) as `0x${string}`[];
    const amounts = validRows.map((r) => r.amount!);

    if (asset === "BNB") {
      multisend.sendBNB(recipients, amounts, parsed.totalAmount);
    } else {
      multisend.sendToken(
        getAddress(tokenAddr) as `0x${string}`,
        recipients,
        amounts,
        feeBps
      );
    }
  }

  function handleApprove() {
    if (!tokenValid) return;
    approve.approve(getAddress(tokenAddr) as `0x${string}`, maxUint256);
  }

  const contractDeployed =
    MULTISENDER_ADDRESS !== "0x0000000000000000000000000000000000000000";

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
            Pilih asset, paste recipients, sign. Tx atomic — semua atau tidak sama sekali.
          </p>

          {!contractDeployed && (
            <Banner color="amber">
              Contract belum di-deploy ke chain ini. Set{" "}
              <code className="font-mono text-xs">NEXT_PUBLIC_MULTISENDER_ADDRESS</code>{" "}
              di env. Preview tetep jalan, send akan revert.
            </Banner>
          )}

          {isConnected && !isBsc && (
            <Banner color="red">
              Wrong network. Switch wallet ke BSC mainnet (56) atau testnet (97).
            </Banner>
          )}

          {!isConnected ? (
            <div className="mt-12 rounded-2xl border border-zinc-900 p-8 text-center">
              <p className="text-zinc-400">Connect wallet dulu buat mulai.</p>
              <div className="mt-4 flex justify-center">
                <ConnectButton />
              </div>
            </div>
          ) : (
            <div className="mt-8 space-y-6">
              {/* ---------- 1. Asset ---------- */}
              <Section title="1. Asset">
                <div className="flex gap-2 text-xs">
                  <Pill active={asset === "BNB"} onClick={() => setAsset("BNB")}>
                    BNB (Free tier)
                  </Pill>
                  <Pill active={asset === "TOKEN"} onClick={() => setAsset("TOKEN")}>
                    BEP-20 (Standard)
                  </Pill>
                </div>

                {asset === "TOKEN" && (
                  <div className="mt-4 space-y-2">
                    <input
                      type="text"
                      placeholder="0x... token contract address"
                      value={tokenAddr}
                      onChange={(e) => setTokenAddr(e.target.value)}
                      className="w-full rounded-xl bg-zinc-950 border border-zinc-900 p-3 font-mono text-sm focus:border-yellow-400 focus:outline-none"
                    />
                    {tokenValid && tokenLoading && (
                      <p className="text-xs text-zinc-500">Fetching token info…</p>
                    )}
                    {tokenInfo && (
                      <p className="text-xs text-zinc-400">
                        <span className="text-zinc-100">{tokenInfo.symbol}</span> ·{" "}
                        {tokenInfo.name} · decimals {tokenInfo.decimals} · balance{" "}
                        <span className="font-mono">
                          {formatUnits(tokenInfo.balance, tokenInfo.decimals)}
                        </span>
                      </p>
                    )}
                  </div>
                )}

                <div className="mt-3 text-xs text-zinc-500">
                  Tier <span className="text-yellow-400">{tier}</span> · max{" "}
                  {limit} recipients ·{" "}
                  {asset === "TOKEN"
                    ? `fee ${feeBps / 100}% (charged in same token)`
                    : "no protocol fee"}
                </div>
              </Section>

              {/* ---------- 2. Recipients ---------- */}
              <Section
                title="2. Recipients"
                right={
                  <div className="flex gap-2 text-xs">
                    <Pill active={mode === "paste"} onClick={() => setMode("paste")}>
                      Paste
                    </Pill>
                    <Pill active={mode === "equal"} onClick={() => setMode("equal")}>
                      Equal split
                    </Pill>
                  </div>
                }
              >
                {mode === "paste" ? (
                  <textarea
                    value={pasteInput}
                    onChange={(e) => setPasteInput(e.target.value)}
                    rows={8}
                    placeholder={`0xabc...,1.5\n0xdef... 0.25\n# baris dengan # di-skip`}
                    className="w-full rounded-xl bg-zinc-950 border border-zinc-900 p-4 font-mono text-sm focus:border-yellow-400 focus:outline-none"
                  />
                ) : (
                  <div className="space-y-3">
                    <textarea
                      value={equalAddrs}
                      onChange={(e) => setEqualAddrs(e.target.value)}
                      rows={6}
                      placeholder={`0xabc...\n0xdef...`}
                      className="w-full rounded-xl bg-zinc-950 border border-zinc-900 p-4 font-mono text-sm focus:border-yellow-400 focus:outline-none"
                    />
                    <input
                      type="text"
                      inputMode="decimal"
                      value={equalTotal}
                      onChange={(e) => setEqualTotal(e.target.value)}
                      placeholder={`Total amount (mis. 10 ${symbol})`}
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
                      {parsed.rows.slice(0, 200).map((r) => (
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
                          <span className={r.error ? "text-red-400" : "text-emerald-400"}>
                            {r.error ?? "ok"}
                          </span>
                        </div>
                      ))}
                    </div>
                  </div>
                )}

                {parsed.duplicates.length > 0 && (
                  <p className="mt-2 text-xs text-amber-400">
                    ⚠️ {parsed.duplicates.length} duplicate address — bakal dianggap
                    valid, total tetep dijumlah ke address yang sama.
                  </p>
                )}
              </Section>

              {/* ---------- 3. Preview ---------- */}
              <Section title="3. Preview & Send">
                <div className="grid grid-cols-2 sm:grid-cols-4 gap-3 text-sm">
                  <Stat label="Valid" value={String(parsed.validCount)} />
                  <Stat
                    label="Total"
                    value={formatUnits(parsed.totalAmount, decimals)}
                    suffix={symbol}
                  />
                  <Stat
                    label="Fee"
                    value={formatUnits(fee, decimals)}
                    suffix={symbol}
                  />
                  <Stat
                    label="Required"
                    value={formatUnits(requiredAllowance, decimals)}
                    suffix={symbol}
                    danger={insufficientBalance}
                  />
                </div>

                <div className="mt-3 grid grid-cols-2 sm:grid-cols-4 gap-3 text-xs text-zinc-500">
                  <Pair label="Your balance" value={`${formatUnits(userBalance, decimals)} ${symbol}`} />
                  <Pair label="Tier" value={tier} />
                  <Pair label="Max recipients" value={String(limit)} />
                  <Pair label="Duplicates" value={String(parsed.duplicates.length)} />
                </div>

                {/* validation warnings */}
                {overLimit && (
                  <p className="mt-3 text-xs text-red-400">
                    ⚠️ {parsed.validCount} recipients &gt; tier limit {limit}.{" "}
                    {asset === "BNB"
                      ? "Switch ke Standard (BEP-20) buat batch lebih besar."
                      : "Split jadi beberapa batch."}
                  </p>
                )}
                {insufficientBalance && (
                  <p className="mt-2 text-xs text-red-400">
                    ⚠️ Balance kurang. Butuh{" "}
                    {formatUnits(requiredAllowance - userBalance, decimals)} {symbol} lagi.
                  </p>
                )}

                {/* approve / send buttons */}
                <div className="mt-6 flex flex-wrap gap-3">
                  {needsApprove && tokenValid && (
                    <button
                      onClick={handleApprove}
                      disabled={approve.isPending}
                      className="inline-flex h-11 items-center justify-center rounded-full border border-yellow-400/40 bg-yellow-400/10 px-6 text-sm font-medium text-yellow-300 transition hover:bg-yellow-400/20 disabled:opacity-30"
                    >
                      {approve.isPending ? "Approving…" : `Approve ${symbol}`}
                    </button>
                  )}

                  <button
                    onClick={handleSend}
                    disabled={
                      multisend.isPending ||
                      parsed.validCount === 0 ||
                      overLimit ||
                      insufficientBalance ||
                      needsApprove ||
                      !contractDeployed ||
                      !isBsc
                    }
                    className="inline-flex h-11 items-center justify-center rounded-full bg-yellow-400 px-6 text-sm font-medium text-black transition hover:bg-yellow-300 disabled:opacity-30 disabled:cursor-not-allowed"
                  >
                    {multisend.isPending
                      ? "Sending…"
                      : `Send ${parsed.validCount} recipients`}
                  </button>
                </div>

                {/* tx state */}
                {(approve.hash || multisend.hash) && (
                  <div className="mt-4 rounded-xl border border-zinc-900 bg-zinc-950 p-4 text-xs">
                    {approve.hash && (
                      <TxRow
                        label="Approve"
                        hash={approve.hash}
                        success={approve.isSuccess}
                        explorer={explorerUrl}
                      />
                    )}
                    {multisend.hash && (
                      <TxRow
                        label="Multisend"
                        hash={multisend.hash}
                        success={multisend.isSuccess}
                        explorer={explorerUrl}
                      />
                    )}
                  </div>
                )}

                {(approve.error || multisend.error) && (
                  <p className="mt-3 text-xs text-red-400 break-all">
                    {(approve.error?.message || multisend.error?.message)?.slice(0, 240)}
                  </p>
                )}
              </Section>
            </div>
          )}
        </div>
      </main>
    </div>
  );
}

// ---------- UI bits ----------

function Section({
  title,
  right,
  children,
}: {
  title: string;
  right?: React.ReactNode;
  children: React.ReactNode;
}) {
  return (
    <section className="rounded-2xl border border-zinc-900 p-6">
      <div className="flex items-center justify-between">
        <h2 className="font-medium">{title}</h2>
        {right}
      </div>
      <div className="mt-4">{children}</div>
    </section>
  );
}

function Pill({
  active,
  children,
  onClick,
}: {
  active: boolean;
  children: React.ReactNode;
  onClick: () => void;
}) {
  return (
    <button
      onClick={onClick}
      className={`px-3 py-1 rounded-full border ${
        active
          ? "border-yellow-400 text-yellow-400"
          : "border-zinc-800 text-zinc-400 hover:border-zinc-700"
      }`}
    >
      {children}
    </button>
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
      <div className={`mt-1 font-mono ${danger ? "text-red-400" : "text-zinc-100"}`}>
        {value}
        {suffix && <span className="ml-1 text-xs text-zinc-500">{suffix}</span>}
      </div>
    </div>
  );
}

function Pair({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <div className="text-zinc-500">{label}</div>
      <div className="font-mono text-zinc-300">{value}</div>
    </div>
  );
}

function TxRow({
  label,
  hash,
  success,
  explorer,
}: {
  label: string;
  hash: `0x${string}`;
  success: boolean;
  explorer: string;
}) {
  return (
    <div className="flex items-center justify-between gap-3 py-1">
      <span className="text-zinc-400">{label}</span>
      <a
        href={`${explorer}/tx/${hash}`}
        target="_blank"
        rel="noopener noreferrer"
        className="font-mono text-zinc-300 hover:text-yellow-400 truncate max-w-[60%]"
      >
        {hash.slice(0, 10)}…{hash.slice(-8)}
      </a>
      <span className={success ? "text-emerald-400" : "text-zinc-500"}>
        {success ? "confirmed" : "pending"}
      </span>
    </div>
  );
}

function Banner({
  color,
  children,
}: {
  color: "amber" | "red";
  children: React.ReactNode;
}) {
  const cls =
    color === "red"
      ? "border-red-500/30 bg-red-500/5 text-red-300"
      : "border-amber-500/30 bg-amber-500/5 text-amber-300";
  return (
    <div className={`mt-6 rounded-xl border ${cls} p-3 text-xs`}>{children}</div>
  );
}
