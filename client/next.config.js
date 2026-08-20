/** @type {import('next').NextConfig} */
const nextConfig = {
  output: "standalone",
  turbopack: {
    root: __dirname,
  },
  allowedDevOrigins: ["127.0.0.1", "localhost", "192.168.0.110"],
  devIndicators: false,
  outputFileTracingIncludes: {
    "/api/applications/submit": [
      "./node_modules/playwright-core/browsers.json",
      "./node_modules/@fontsource/caveat/files/caveat-cyrillic-400-normal.woff2",
    ],
    "/api/applications/render": [
      "./node_modules/playwright-core/browsers.json",
      "./node_modules/@fontsource/caveat/files/caveat-cyrillic-400-normal.woff2",
    ],
    "/api/fonts/caveat": ["./node_modules/@fontsource/caveat/files/caveat-cyrillic-400-normal.woff2"],
  },
};

module.exports = nextConfig;
