import type { NextConfig } from "next";
import path from "path";

const allowedDevOrigins = process.env.NEXT_ALLOWED_DEV_ORIGINS
  ? process.env.NEXT_ALLOWED_DEV_ORIGINS.split(",").map((origin) => origin.trim())
  : [];

const nextConfig: NextConfig = {
  allowedDevOrigins,
  turbopack: {
    root: path.resolve(__dirname),
  },
};

export default nextConfig;
