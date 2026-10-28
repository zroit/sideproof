import type { NextConfig } from "next";

// A static export: FastAPI serves the files from web-dist/ next to the API, so the app talks
// to its own origin. trailingSlash gives /trial/index.html, which a static server finds.
const nextConfig: NextConfig = {
  output: "export",
  trailingSlash: true,
  images: { unoptimized: true },
};

export default nextConfig;
