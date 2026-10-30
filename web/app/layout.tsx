import type { Metadata, Viewport } from "next";
import { Instrument_Serif, Manrope } from "next/font/google";
import "./globals.css";

const display = Instrument_Serif({ subsets: ["latin"], weight: "400", style: ["normal", "italic"], variable: "--font-display" });
const body = Manrope({ subsets: ["latin"], variable: "--font-body" });

export const metadata: Metadata = {
  title: "SideProof",
  description: "Test a skincare product on half your face. YouCam Skin AI measures both halves, so whatever differs is the product.",
  icons: { icon: "/favicon.png?v=2", apple: "/icon-192.png?v=2" },   // ?v=2: the new mark, past cached copies of the old one
};

export const viewport: Viewport = {
  themeColor: "#FBF6F1",
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en" className={`${display.variable} ${body.variable}`}>
      <body>{children}</body>
    </html>
  );
}
