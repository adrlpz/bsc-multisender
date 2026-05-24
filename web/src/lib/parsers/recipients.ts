import { isAddress, getAddress, parseUnits } from "viem";

export type ParsedRow = {
  index: number;
  raw: string;
  address?: `0x${string}`;
  amount?: bigint;
  error?: string;
};

export type ParseResult = {
  rows: ParsedRow[];
  validCount: number;
  totalAmount: bigint;
  duplicates: string[];
};

/**
 * Parse multi-line input where each line is `address<sep>amount`.
 * Separators accepted: comma, space, tab, semicolon.
 * Decimals: human-readable (e.g. "1.5" with decimals=18 → 1.5e18).
 */
export function parseRecipients(input: string, decimals: number): ParseResult {
  const lines = input
    .split(/\r?\n/)
    .map((l) => l.trim())
    .filter((l) => l.length > 0 && !l.startsWith("#"));

  const seen = new Map<string, number>();
  const duplicates: string[] = [];

  const rows: ParsedRow[] = lines.map((raw, i) => {
    const parts = raw.split(/[\s,;\t]+/).filter(Boolean);
    if (parts.length < 2) {
      return { index: i, raw, error: "format: address amount" };
    }

    const [addrStr, amountStr] = parts;

    if (!isAddress(addrStr)) {
      return { index: i, raw, error: "invalid address" };
    }

    const address = getAddress(addrStr);

    let amount: bigint;
    try {
      amount = parseUnits(amountStr, decimals);
    } catch {
      return { index: i, raw, address, error: "invalid amount" };
    }

    if (amount === 0n) {
      return { index: i, raw, address, error: "amount must be > 0" };
    }

    const prev = seen.get(address.toLowerCase());
    if (prev !== undefined) {
      duplicates.push(address);
    } else {
      seen.set(address.toLowerCase(), i);
    }

    return { index: i, raw, address, amount };
  });

  const validCount = rows.filter((r) => !r.error).length;
  const totalAmount = rows
    .filter((r) => !r.error && r.amount !== undefined)
    .reduce((acc, r) => acc + (r.amount ?? 0n), 0n);

  return { rows, validCount, totalAmount, duplicates };
}

/**
 * Equal split: list of addresses + total amount → each gets total/N (with remainder to first).
 */
export function equalSplit(
  addresses: string[],
  totalHuman: string,
  decimals: number
): ParseResult {
  const total = parseUnits(totalHuman, decimals);
  const validAddresses = addresses
    .map((a) => a.trim())
    .filter((a) => a.length > 0 && !a.startsWith("#"));

  const n = BigInt(validAddresses.length);
  if (n === 0n) {
    return { rows: [], validCount: 0, totalAmount: 0n, duplicates: [] };
  }

  const base = total / n;
  const remainder = total - base * n;

  const seen = new Map<string, number>();
  const duplicates: string[] = [];

  const rows: ParsedRow[] = validAddresses.map((addrStr, i) => {
    if (!isAddress(addrStr)) {
      return { index: i, raw: addrStr, error: "invalid address" };
    }
    const address = getAddress(addrStr);
    const prev = seen.get(address.toLowerCase());
    if (prev !== undefined) duplicates.push(address);
    else seen.set(address.toLowerCase(), i);

    const amount = i === 0 ? base + remainder : base;
    return { index: i, raw: addrStr, address, amount };
  });

  const validCount = rows.filter((r) => !r.error).length;
  const totalAmount = rows
    .filter((r) => !r.error && r.amount !== undefined)
    .reduce((acc, r) => acc + (r.amount ?? 0n), 0n);

  return { rows, validCount, totalAmount, duplicates };
}
