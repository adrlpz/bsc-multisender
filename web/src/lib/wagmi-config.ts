"use client";

import { getDefaultConfig } from "@rainbow-me/rainbowkit";
import { bsc, bscTestnet } from "wagmi/chains";
import { http } from "wagmi";

export const wagmiConfig = getDefaultConfig({
  appName: "BSC Multi-Sender",
  projectId:
    process.env.NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID ?? "00000000000000000000000000000000",
  chains: [bsc, bscTestnet],
  transports: {
    [bsc.id]: http(
      process.env.NEXT_PUBLIC_BSC_RPC ?? "https://bsc-dataseed.binance.org"
    ),
    [bscTestnet.id]: http(
      process.env.NEXT_PUBLIC_BSC_TESTNET_RPC ??
        "https://data-seed-prebsc-1-s1.binance.org:8545"
    ),
  },
  ssr: true,
});

export const MULTISENDER_ADDRESS = (process.env.NEXT_PUBLIC_MULTISENDER_ADDRESS ??
  "0x0000000000000000000000000000000000000000") as `0x${string}`;
