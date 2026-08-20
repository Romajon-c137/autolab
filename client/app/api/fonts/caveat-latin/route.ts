import { readFile } from "node:fs/promises";
import { NextResponse } from "next/server";

export const runtime = "nodejs";

export async function GET() {
  const path = `${process.cwd()}/node_modules/@fontsource/caveat/files/caveat-latin-400-normal.woff2`;
  const font = await readFile(path);

  return new NextResponse(new Uint8Array(font), {
    headers: {
      "Cache-Control": "public, max-age=31536000, immutable",
      "Content-Type": "font/woff2",
    },
  });
}
