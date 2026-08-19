import { NextRequest, NextResponse } from "next/server";
import { existsSync } from "node:fs";
import { chromium } from "playwright";
import { ApplicationFormState, buildApplicationDocument } from "../../../application-document";

export const runtime = "nodejs";

const backendUrl = (process.env.BACKEND_URL || process.env.NEXT_PUBLIC_BACKEND_URL || "http://127.0.0.1:8000").replace(/\/+$/, "");
const vinPattern = /^[A-HJ-NPR-Z0-9]{17}$/;

type SubmitBody = {
  form?: Partial<ApplicationFormState>;
  signatureData?: string;
};

export async function POST(request: NextRequest) {
  let body: SubmitBody;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ ok: false, error: "Invalid JSON body" }, { status: 400 });
  }

  const form = normalizeForm(body.form);
  const signatureData = typeof body.signatureData === "string" ? body.signatureData : "";
  if (!vinPattern.test(form.vin)) {
    return NextResponse.json({ ok: false, error: "VIN должен состоять из 17 допустимых символов" }, { status: 400 });
  }

  if (!signatureData.startsWith("data:image/png;base64,")) {
    return NextResponse.json({ ok: false, error: "Подпись обязательна" }, { status: 400 });
  }

  let pdf: Buffer;
  try {
    pdf = await renderApplicationPdf(form, signatureData);
  } catch (error) {
    return NextResponse.json(
      { ok: false, error: error instanceof Error ? error.message : "Не удалось создать PDF" },
      { status: 500 }
    );
  }

  const data = new FormData();
  data.append("vin", form.vin);
  data.append("application_pdf", new Blob([new Uint8Array(pdf)], { type: "application/pdf" }), applicationPdfName(form));

  const response = await fetch(`${backendUrl}/api/client-applications/`, {
    method: "POST",
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
    await page.setContent(buildApplicationDocument(form, signatureData), { waitUntil: "networkidle" });
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
