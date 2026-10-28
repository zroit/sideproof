import type { Metadata, Viewport } from "next";
import localFont from "next/font/local";
import { Instrument_Sans } from "next/font/google";
import "./globals.css";

const display = localFont({ src: "./fonts/BricolageGrotesque.ttf", variable: "--font-display", weight: "200 800" });
const body = Instrument_Sans({ subsets: ["latin"], variable: "--font-body" });

export const metadata: Metadata = {
  title: "SideProof",
  description: "Test a skincare product on half your face. YouCam Skin AI measures both halves, so whatever differs is the product.",
  icons: { icon: "/favicon.png", apple: "/icon-192.png" },
};

export const viewport: Viewport = {
  themeColor: [
    { media: "(prefers-color-scheme: light)", color: "#F2F4F3" },
    { media: "(prefers-color-scheme: dark)", color: "#0F171B" },
  ],
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en" className={`${display.variable} ${body.variable}`}>
      <body>{children}</body>
    </html>
  );
}
