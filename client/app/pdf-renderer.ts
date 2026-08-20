import { existsSync, readFileSync } from "node:fs";
import { chromium } from "playwright";
import { ApplicationFormState, buildApplicationDocument } from "./application-document";

let cachedCaveatFont = "";

export async function renderApplicationPdf(form: ApplicationFormState, signatureData: string) {
  const executablePath = process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH || defaultChromiumExecutable();
  const browser = await chromium.launch({ headless: true, executablePath });
  try {
    const page = await browser.newPage({ viewport: { width: 794, height: 1123 }, deviceScaleFactor: 1 });
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

export function applicationPdfName(form: ApplicationFormState) {
  const brand = form.vehicleName.replace(/[^A-Za-zА-Яа-я0-9]+/g, "-").replace(/^-|-$/g, "") || "application";
  return `${brand}-${form.vin}.pdf`;
}

function caveatFontBase64() {
  if (!cachedCaveatFont) {
    const path = `${process.cwd()}/node_modules/@fontsource/caveat/files/caveat-cyrillic-400-normal.woff2`;
    cachedCaveatFont = readFileSync(path).toString("base64");
  }
  return cachedCaveatFont;
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
