import type { Metadata } from "next";
import { Geist, Geist_Mono } from "next/font/google";
import "./globals.css";
import { Web3Providers } from "@/lib/providers";

const geistSans = Geist({
  variable: "--font-geist-sans",
  subsets: ["latin"],
});

const geistMono = Geist_Mono({
  variable: "--font-geist-mono",
  subsets: ["latin"],
});

export const metadata: Metadata = {
  title: "BSC Multi-Sender — kirim BNB & BEP-20 ke banyak wallet, 1 klik",
  description:
    "Tool non-custodial buat kirim BNB / BEP-20 token ke ratusan wallet sekaligus di BNB Smart Chain. 1x klik, gas saving 60%+, audit-friendly.",
  openGraph: {
    title: "BSC Multi-Sender",
    description: "Kirim BNB & BEP-20 ke banyak wallet sekaligus, 1 klik.",
    type: "website",
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html
      lang="en"
      className={`${geistSans.variable} ${geistMono.variable} h-full antialiased dark`}
    >
      <body className="min-h-full flex flex-col bg-black text-zinc-100">
        <Web3Providers>{children}</Web3Providers>
      </body>
    </html>
  );
}
