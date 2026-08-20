import { NextRequest, NextResponse } from "next/server";
import { consumeRateLimit, contentLengthExceeds } from "../security";

type ScanResult = {
  vehicleName: string;
  plateNumber: string;
  year: string;
  vin: string;
};

const jsonInstruction = `You read a Kyrgyz vehicle registration certificate photo.
Return ONLY valid compact JSON with this exact shape:
{"vehicleName":"","plateNumber":"","year":"","vin":""}

Where to take values:
- plateNumber: line 4 vehicle registration plate, uppercase, no extra punctuation. Example: 02KG370AIR.
- vehicleName: line 5 make and model. Normalize slash to a space. Example: CHEVROLET / LACETTI -> Chevrolet Lacetti.
- vin: line 7, 17-character VIN/body identification number.
- year: line 15, four digit manufacture year.

VIN rules (ISO 3779): exactly 17 characters, made only of digits 0-9 and uppercase
letters A-Z excluding I, O and Q (these three letters are never used in a real VIN,
because they are visually confused with 1, 0 and 0). If a printed character looks
like I, O or Q, it is actually 1, 0 or 0 respectively — read it as that digit, do not
read it as the letter and do not drop it.

Rules:
- Do not guess if a value is not visible; use empty string.
- Read the VIN character by character across all 17 positions. Only return empty
  string for vin if fewer than 17 characters are legible at all.
- Remove labels and line numbers.
- For vin and plateNumber keep only A-Z and 0-9.
- For year keep only four digits.
- For inn keep only digits.`;

export async function POST(request: NextRequest) {
  if (!consumeRateLimit(request, "passport-scan", 10, 60_000)) {
    return NextResponse.json({ ok: false, error: "Too many requests" }, { status: 429 });
  }
  if (contentLengthExceeds(request, 16 * 1024 * 1024)) {
    return NextResponse.json({ ok: false, error: "Request is too large" }, { status: 413 });
  }
  const apiKey = process.env.OPENAI_API_KEY?.trim();
  if (!apiKey) {
    return NextResponse.json({ ok: false, error: "OPENAI_API_KEY is not configured" }, { status: 500 });
  }

  const formData = await request.formData();
  const image = formData.get("tech_passport");
  if (!(image instanceof File)) {
    return NextResponse.json({ ok: false, error: "Field 'tech_passport' is required" }, { status: 400 });
  }

  if (!image.type.startsWith("image/")) {
    return NextResponse.json({ ok: false, error: "Uploaded file must be an image" }, { status: 400 });
  }
  if (image.size > 15 * 1024 * 1024) {
    return NextResponse.json({ ok: false, error: "Image is too large" }, { status: 413 });
  }

  const bytes = Buffer.from(await image.arrayBuffer());
  const base64 = bytes.toString("base64");
  const model = process.env.OPENAI_TECH_PASSPORT_MODEL?.trim() || "gpt-4o-mini";

  const response = await fetch("https://api.openai.com/v1/responses", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model,
      input: [
        {
          role: "user",
          content: [
            { type: "input_text", text: jsonInstruction },
            {
              type: "input_image",
              image_url: `data:${image.type || "image/jpeg"};base64,${base64}`,
            },
          ],
        },
      ],
      max_output_tokens: 220,
    }),
  });

  const data = await response.json().catch(() => ({}));
  if (!response.ok) {
    const message = typeof data?.error?.message === "string" ? data.error.message : "OpenAI returned an error";
    return NextResponse.json({ ok: false, error: message }, { status: 502 });
  }

  const rawText = collectOpenAIText(data);
  const parsed = parseScanResult(rawText);
  if (!parsed) {
    return NextResponse.json({ ok: false, error: "Could not parse AI response", raw_text: rawText }, { status: 422 });
  }

  return NextResponse.json({
    ok: true,
    data: normalizeScanResult(parsed),
    raw_text: rawText,
  });
}

function collectOpenAIText(data: unknown): string {
  if (!data || typeof data !== "object") return "";
  const maybeOutputText = (data as { output_text?: unknown }).output_text;
  if (typeof maybeOutputText === "string") return maybeOutputText.trim();

  const output = (data as { output?: unknown }).output;
  if (!Array.isArray(output)) return "";

  const chunks: string[] = [];
  for (const item of output) {
    if (!item || typeof item !== "object") continue;
    const content = (item as { content?: unknown }).content;
    if (!Array.isArray(content)) continue;
    for (const part of content) {
      if (!part || typeof part !== "object") continue;
      const text = (part as { text?: unknown }).text;
      if (typeof text === "string") chunks.push(text);
    }
  }
  return chunks.join("\n").trim();
}

function parseScanResult(text: string): Partial<ScanResult> | null {
  const clean = text.replace(/^```(?:json)?/i, "").replace(/```$/i, "").trim();
  try {
    const parsed = JSON.parse(clean);
    return parsed && typeof parsed === "object" ? parsed : null;
  } catch {
    const match = clean.match(/\{[\s\S]*\}/);
    if (!match) return null;
    try {
      const parsed = JSON.parse(match[0]);
      return parsed && typeof parsed === "object" ? parsed : null;
    } catch {
      return null;
    }
  }
}

// ISO 3779: a VIN never contains I, O or Q — these are excluded specifically because
// they are visually confused with 1, 0 and 0. When OCR reports one of them it is
// almost always a misread of the digit, not a character that belongs in the VIN, so
// we correct it in place rather than stripping it (stripping shortens the VIN below
// 17 characters and makes an otherwise-readable scan look "unrecognized").
const VIN_LOOKALIKES: Record<string, string> = { I: "1", O: "0", Q: "0" };
const VIN_PATTERN = /^[A-HJ-NPR-Z0-9]{17}$/;

function correctVin(value: string): string {
  return value.replace(/[IOQ]/g, (char) => VIN_LOOKALIKES[char]);
}

function normalizeScanResult(result: Partial<ScanResult>): ScanResult {
  const vinRaw = normalizeText(result.vin).toUpperCase().replace(/[^A-Z0-9]/g, "").slice(0, 17);
  const vin = correctVin(vinRaw);
  return {
    vehicleName: normalizeVehicleName(result.vehicleName),
    plateNumber: normalizeText(result.plateNumber).toUpperCase().replace(/[^A-Z0-9]/g, ""),
    year: normalizeText(result.year).replace(/\D/g, "").slice(0, 4),
    vin: VIN_PATTERN.test(vin) ? vin : "",
  };
}

function normalizeText(value: unknown): string {
  return typeof value === "string" ? value.trim().replace(/\s+/g, " ") : "";
}

function normalizeVehicleName(value: unknown): string {
  return normalizeText(value)
    .replace(/\s*\/\s*/g, " ")
    .toLowerCase()
    .replace(/(^|\s)\S/g, (letter) => letter.toUpperCase());
}
