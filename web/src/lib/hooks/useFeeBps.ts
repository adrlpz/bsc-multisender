"use client";

import { useReadContract } from "wagmi";
import { multisenderAbi } from "@/lib/abis";
import { MULTISENDER_ADDRESS } from "@/lib/wagmi-config";

/**
 * Read current protocol fee from the deployed Multisender.
 * Used as the default `maxFeeBps` slippage value in send tx (zero slippage).
 */
export function useFeeBps() {
  const { data, isLoading, error, refetch } = useReadContract({
    address: MULTISENDER_ADDRESS,
    abi: multisenderAbi,
    functionName: "feeBps",
    query: {
      enabled:
        MULTISENDER_ADDRESS !== "0x0000000000000000000000000000000000000000",
      staleTime: 60_000,
    },
  });

  return {
    feeBps: typeof data === "number" ? data : Number(data ?? 0),
    isLoading,
    error,
    refetch,
  };
}
