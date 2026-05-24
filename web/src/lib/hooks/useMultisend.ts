"use client";

import { useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { erc20Abi, multisenderAbi } from "@/lib/abis";
import { MULTISENDER_ADDRESS } from "@/lib/wagmi-config";

/**
 * Hook for ERC-20 approve (used before multisendToken).
 */
export function useApprove() {
  const { writeContract, data: hash, isPending, error, reset } = useWriteContract();
  const wait = useWaitForTransactionReceipt({ hash });

  function approve(token: `0x${string}`, amount: bigint) {
    writeContract({
      address: token,
      abi: erc20Abi,
      functionName: "approve",
      args: [MULTISENDER_ADDRESS, amount],
    });
  }

  return {
    approve,
    hash,
    isPending: isPending || wait.isLoading,
    isSuccess: wait.isSuccess,
    error: error || wait.error,
    reset,
  };
}

/**
 * Hook for batch send (BNB or token).
 */
export function useMultisend() {
  const { writeContract, data: hash, isPending, error, reset } = useWriteContract();
  const wait = useWaitForTransactionReceipt({ hash });

  function sendBNB(recipients: `0x${string}`[], amounts: bigint[], total: bigint) {
    writeContract({
      address: MULTISENDER_ADDRESS,
      abi: multisenderAbi,
      functionName: "multisendBNB",
      args: [recipients, amounts],
      value: total,
    });
  }

  function sendToken(
    token: `0x${string}`,
    recipients: `0x${string}`[],
    amounts: bigint[],
    maxFeeBps: number
  ) {
    writeContract({
      address: MULTISENDER_ADDRESS,
      abi: multisenderAbi,
      functionName: "multisendToken",
      args: [token, recipients, amounts, maxFeeBps],
    });
  }

  return {
    sendBNB,
    sendToken,
    hash,
    isPending: isPending || wait.isLoading,
    isSuccess: wait.isSuccess,
    receipt: wait.data,
    error: error || wait.error,
    reset,
  };
}
