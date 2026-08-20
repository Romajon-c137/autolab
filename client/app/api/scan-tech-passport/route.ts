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
- vin: line 7, 17-character VIN/body identification number. Uppercase. VIN never contains I, O, Q.
- year: line 15, four digit manufacture year.

Rules:
- Do not guess if a value is not visible; use empty string.
- If the full 17-character VIN is not readable, return empty string for vin.
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

function normalizeScanResult(result: Partial<ScanResult>): ScanResult {
  const vin = normalizeText(result.vin).toUpperCase().replace(/[^A-HJ-NPR-Z0-9]/g, "").slice(0, 17);
  return {
    vehicleName: normalizeVehicleName(result.vehicleName),
    plateNumber: normalizeText(result.plateNumber).toUpperCase().replace(/[^A-Z0-9]/g, ""),
    year: normalizeText(result.year).replace(/\D/g, "").slice(0, 4),
    vin: vin.length === 17 ? vin : "",
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
