import { NextRequest, NextResponse } from "next/server";
import { existsSync, readFileSync } from "node:fs";
import { isIP } from "node:net";
import { chromium } from "playwright";
import { ApplicationFormState, buildApplicationDocument } from "../../../application-document";
import { acquirePdfRenderSlot, consumeRateLimit, contentLengthExceeds } from "../../security";

export const runtime = "nodejs";

const backendUrl = (process.env.BACKEND_URL || process.env.NEXT_PUBLIC_BACKEND_URL || "http://127.0.0.1:8000").replace(/\/+$/, "");
const vinPattern = /^[A-HJ-NPR-Z0-9]{17}$/;
let cachedCaveatFont = "";

type SubmitBody = {
  form?: Partial<ApplicationFormState>;
  signatureData?: string;
};

export async function POST(request: NextRequest) {
  if (!consumeRateLimit(request, "application-submit", 5, 60_000)) {
    return NextResponse.json({ ok: false, error: "Too many requests" }, { status: 429 });
  }
  if (contentLengthExceeds(request, 3 * 1024 * 1024)) {
    return NextResponse.json({ ok: false, error: "Request is too large" }, { status: 413 });
  }

  let body: SubmitBody;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ ok: false, error: "Invalid JSON body" }, { status: 400 });
  }

  const form = normalizeForm(body.form);
  const signatureData = typeof body.signatureData === "string" ? body.signatureData : "";
  const formError = validateForm(form);
  if (formError) {
    return NextResponse.json({ ok: false, error: formError }, { status: 400 });
  }
  if (!vinPattern.test(form.vin)) {
    return NextResponse.json({ ok: false, error: "VIN должен состоять из 17 допустимых символов" }, { status: 400 });
  }

  if (!signatureData.startsWith("data:image/png;base64,")) {
    return NextResponse.json({ ok: false, error: "Подпись обязательна" }, { status: 400 });
  }
  if (signatureData.length > 2 * 1024 * 1024) {
    return NextResponse.json({ ok: false, error: "Signature is too large" }, { status: 413 });
  }

  const releaseRenderSlot = acquirePdfRenderSlot();
  if (!releaseRenderSlot) {
    return NextResponse.json({ ok: false, error: "PDF service is busy" }, { status: 503 });
  }

  let pdf: Buffer;
  try {
    pdf = await renderApplicationPdf(form, signatureData);
  } catch (error) {
    console.error("Application PDF rendering failed", error);
    return NextResponse.json({ ok: false, error: "Не удалось подготовить документ. Повторите позже." }, { status: 500 });
  } finally {
    releaseRenderSlot();
  }

  const data = new FormData();
  data.append("vin", form.vin);
  data.append("applicant_name", form.applicant);
  data.append("inn", form.inn);
  data.append("phone", form.phone);
  data.append("vehicle_name", form.vehicleName);
  data.append("plate_number", form.plateNumber);
  data.append("year", form.year);
  data.append("application_pdf", new Blob([new Uint8Array(pdf)], { type: "application/pdf" }), applicationPdfName(form));

  const response = await fetch(`${backendUrl}/api/client-applications/`, {
    method: "POST",
    headers: {
      "X-Client-Application-Key": process.env.CLIENT_APPLICATION_API_KEY || "",
      "X-Forwarded-For": trustedClientIp(request),
    },
    body: data,
  });
  const result = await response.json().catch(() => null);

  if (!response.ok || !result?.ok) {
    return NextResponse.json(
      {
        ok: false,
        error: result?.error || `Backend HTTP ${response.status}`,
        backend_status: response.status,
      },
      { status: response.status || 502 }
    );
  }

  return NextResponse.json({
    ok: true,
    inspection: result.inspection,
  });
}

function trustedClientIp(request: NextRequest) {
  const realIp = request.headers.get("x-real-ip")?.trim() || "";
  return isIP(realIp) ? realIp : "unknown";
}

function normalizeForm(form: SubmitBody["form"]): ApplicationFormState {
  return {
    applicant: clean(form?.applicant),
    inn: clean(form?.inn).replace(/\D/g, "").slice(0, 14),
    phone: clean(form?.phone),
    vehicleName: clean(form?.vehicleName),
    plateNumber: clean(form?.plateNumber).toUpperCase(),
    year: clean(form?.year),
    vin: clean(form?.vin).toUpperCase().replace(/[^A-Z0-9]/g, "").slice(0, 17),
  };
}

function clean(value: unknown) {
  return typeof value === "string" ? value.trim() : "";
}

function validateForm(form: ApplicationFormState) {
  if (form.applicant.length < 2 || form.applicant.length > 200) return "Проверьте ФИО";
  if (!/^\d{14}$/.test(form.inn)) return "ИНН должен состоять из 14 цифр";
  if (!/^\+996\s?\d{3}\s?\d{3}\s?\d{3}$/.test(form.phone)) return "Проверьте номер телефона";
  if (!form.vehicleName || form.vehicleName.length > 120) return "Проверьте марку авто";
  if (!form.plateNumber || form.plateNumber.length > 20) return "Проверьте номер авто";
  if (!/^\d{4}$/.test(form.year)) return "Проверьте год выпуска";
  return "";
}

async function renderApplicationPdf(form: ApplicationFormState, signatureData: string) {
  const executablePath = process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH || defaultChromiumExecutable();
  const browser = await chromium.launch({
    headless: true,
    executablePath,
  });
  try {
    const page = await browser.newPage({
      viewport: { width: 794, height: 1123 },
      deviceScaleFactor: 1,
    });
    await page.setContent(buildApplicationDocument(form, signatureData, caveatFontBase64()), { waitUntil: "networkidle" });
    await page.evaluate(() => document.fonts.ready);
    await page.emulateMedia({ media: "print" });

    return await page.pdf({
      format: "A4",
      printBackground: true,
      margin: { top: "0mm", right: "0mm", bottom: "0mm", left: "0mm" },
      preferCSSPageSize: true,
    });
  } finally {
    await browser.close();
  }
}

function caveatFontBase64() {
  if (!cachedCaveatFont) {
    cachedCaveatFont = readFileSync(caveatFontPath()).toString("base64");
  }
  return cachedCaveatFont;
}

function caveatFontPath() {
  return `${process.cwd()}/node_modules/@fontsource/caveat/files/caveat-cyrillic-400-normal.woff2`;
}

function applicationPdfName(form: ApplicationFormState) {
  const brand = form.vehicleName.replace(/[^A-Za-zА-Яа-я0-9]+/g, "-").replace(/^-|-$/g, "") || "application";
  return `${brand}-${form.vin}.pdf`;
}

function defaultChromiumExecutable() {
  const candidates = [
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    "/Applications/Chromium.app/Contents/MacOS/Chromium",
    "/usr/bin/google-chrome",
    "/usr/bin/google-chrome-stable",
    "/usr/bin/chromium",
    "/usr/bin/chromium-browser",
  ];

  return candidates.find((path) => existsSync(path));
}
