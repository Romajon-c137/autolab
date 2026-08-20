import { timingSafeEqual } from "node:crypto";
import { NextRequest, NextResponse } from "next/server";
import { ApplicationFormState } from "../../../application-document";
import { renderApplicationPdf } from "../../../pdf-renderer";
import { acquirePdfRenderSlot, contentLengthExceeds } from "../../security";

export const runtime = "nodejs";

type RenderBody = { form?: ApplicationFormState; signatureData?: string };

export async function POST(request: NextRequest) {
  if (!validServiceKey(request.headers.get("x-client-application-key") || "")) {
    return NextResponse.json({ ok: false, error: "Authentication required" }, { status: 401 });
  }
  if (contentLengthExceeds(request, 3 * 1024 * 1024)) {
    return NextResponse.json({ ok: false, error: "Request is too large" }, { status: 413 });
  }

  const body = (await request.json().catch(() => null)) as RenderBody | null;
  const form = body?.form;
  const signatureData = body?.signatureData || "";
  if (!form || !/^[A-HJ-NPR-Z0-9]{17}$/.test(form.vin) || !signatureData.startsWith("data:image/png;base64,")) {
    return NextResponse.json({ ok: false, error: "Invalid render data" }, { status: 400 });
  }

  const release = acquirePdfRenderSlot();
  if (!release) return NextResponse.json({ ok: false, error: "PDF service is busy" }, { status: 503 });
  try {
    const pdf = await renderApplicationPdf(form, signatureData);
    return new NextResponse(new Uint8Array(pdf), {
      headers: { "Cache-Control": "no-store", "Content-Type": "application/pdf" },
    });
  } catch (error) {
    console.error("Internal application PDF rendering failed", error);
    return NextResponse.json({ ok: false, error: "PDF rendering failed" }, { status: 500 });
  } finally {
    release();
  }
}

function validServiceKey(supplied: string) {
  const expected = process.env.CLIENT_APPLICATION_API_KEY || "";
  if (!expected || supplied.length !== expected.length) return false;
  return timingSafeEqual(Buffer.from(supplied), Buffer.from(expected));
}
