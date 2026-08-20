import { NextRequest } from "next/server";

type Bucket = { count: number; resetAt: number };
const buckets = new Map<string, Bucket>();
let activePdfRenders = 0;

export function consumeRateLimit(request: NextRequest, scope: string, limit: number, windowMs: number) {
  const forwarded = request.headers.get("x-forwarded-for")?.split(",", 1)[0]?.trim();
  const identity = forwarded || request.headers.get("x-real-ip") || "unknown";
  const key = `${scope}:${identity}`;
  const now = Date.now();
  const current = buckets.get(key);
  if (!current || current.resetAt <= now) {
    buckets.set(key, { count: 1, resetAt: now + windowMs });
    return true;
  }
  current.count += 1;
  return current.count <= limit;
}

export function contentLengthExceeds(request: NextRequest, limit: number) {
  const length = Number(request.headers.get("content-length") || "0");
  return Number.isFinite(length) && length > limit;
}

export function acquirePdfRenderSlot() {
  if (activePdfRenders >= 2) return null;
  activePdfRenders += 1;
  let released = false;
  return () => {
    if (!released) activePdfRenders = Math.max(0, activePdfRenders - 1);
    released = true;
  };
}
