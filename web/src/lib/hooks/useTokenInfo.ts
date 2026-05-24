"use client";

import { useReadContracts } from "wagmi";
import { isAddress } from "viem";
import { erc20Abi } from "@/lib/abis";

export type TokenInfo = {
  address: `0x${string}`;
  name: string;
  symbol: string;
  decimals: number;
  balance: bigint;
  allowance: bigint;
};

/**
 * Fetch ERC-20 metadata (name, symbol, decimals) + user balance + allowance
 * to a spender, in a single multicall round-trip.
 */
export function useTokenInfo(opts: {
  token?: string;
  user?: `0x${string}`;
  spender?: `0x${string}`;
  enabled?: boolean;
}) {
  const { token, user, spender, enabled = true } = opts;

  const valid =
    !!token &&
    isAddress(token) &&
    !!user &&
    !!spender &&
    spender !== "0x0000000000000000000000000000000000000000";

  const { data, isLoading, error, refetch } = useReadContracts({
    allowFailure: false,
    contracts: valid
      ? [
          { address: token as `0x${string}`, abi: erc20Abi, functionName: "name" },
          { address: token as `0x${string}`, abi: erc20Abi, functionName: "symbol" },
          { address: token as `0x${string}`, abi: erc20Abi, functionName: "decimals" },
          {
            address: token as `0x${string}`,
            abi: erc20Abi,
            functionName: "balanceOf",
            args: [user!],
          },
          {
            address: token as `0x${string}`,
            abi: erc20Abi,
            functionName: "allowance",
            args: [user!, spender!],
          },
        ]
      : [],
    query: { enabled: enabled && valid, staleTime: 15_000 },
  });

  const info: TokenInfo | undefined = data
    ? {
        address: token as `0x${string}`,
        name: data[0] as string,
        symbol: data[1] as string,
        decimals: Number(data[2]),
        balance: data[3] as bigint,
        allowance: data[4] as bigint,
      }
    : undefined;

  return { info, isLoading, error, refetch };
}
