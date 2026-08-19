/** @type {import('next').NextConfig} */
const nextConfig = {
  output: "standalone",
  turbopack: {
    root: __dirname,
  },
  allowedDevOrigins: ["127.0.0.1", "localhost", "192.168.0.110"],
  devIndicators: false,
};

module.exports = nextConfig;
