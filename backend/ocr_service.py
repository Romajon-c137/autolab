#!/usr/bin/env python3
import base64
import json
import os
import re
import tempfile
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from paddleocr import PaddleOCR


VIN_RE = re.compile(r"^[A-HJ-NPR-Z0-9]{17}$")
MAX_BODY_SIZE = int(os.environ.get("OCR_MAX_BODY_SIZE", str(15 * 1024 * 1024)))


def clean_vin_text(text):
    return re.sub(r"[^A-Z0-9]", "", text.upper())


def find_vin_candidates(lines):
    candidates = []
    for line in lines:
        cleaned = clean_vin_text(line.get("text", ""))
        if VIN_RE.match(cleaned):
            candidates.append({
                "vin": cleaned,
                "score": line.get("score", 0),
                "raw": line.get("text", ""),
            })
    return candidates


def extract_ocr_lines(result):
    lines = []
    for page in result or []:
        for item in page or []:
            if len(item) < 2:
                continue

            text_data = item[1]
            if len(text_data) < 2:
                continue

            lines.append({
                "text": str(text_data[0]),
                "score": round(float(text_data[1]), 4),
            })
    return lines


class VinOcrService:
    def __init__(self):
        self.ocr = PaddleOCR(
            use_angle_cls=True,
            lang=os.environ.get("PADDLEOCR_LANG", "en"),
            show_log=os.environ.get("PADDLEOCR_SHOW_LOG", "0") == "1",
        )

    def recognize(self, image_bytes, suffix):
        with tempfile.NamedTemporaryFile(suffix=suffix, delete=True) as image_file:
            image_file.write(image_bytes)
            image_file.flush()
            result = self.ocr.ocr(image_file.name, cls=True)

        lines = extract_ocr_lines(result)
        candidates = find_vin_candidates(lines)
        return {
            "ok": True,
            "vin": candidates[0]["vin"] if candidates else "",
            "candidates": candidates,
            "lines": lines,
            "engine": "paddleocr",
        }


SERVICE = VinOcrService()


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/health":
            self._send_json({"ok": True, "engine": "paddleocr"})
            return

        self._send_json({"ok": False, "error": "Not found"}, status=404)

    def do_POST(self):
        if self.path != "/recognize-vin":
            self._send_json({"ok": False, "error": "Not found"}, status=404)
            return

        content_length = int(self.headers.get("Content-Length", "0") or "0")
        if content_length <= 0:
            self._send_json({"ok": False, "error": "Empty request body"}, status=400)
            return

        if content_length > MAX_BODY_SIZE:
            self._send_json({"ok": False, "error": "Request body is too large"}, status=413)
            return

        try:
            body = self.rfile.read(content_length)
            payload = json.loads(body.decode("utf-8"))
            encoded_image = payload.get("image_base64", "")
            image_bytes = base64.b64decode(encoded_image, validate=True)
            suffix = self._safe_suffix(payload.get("filename", "vin.jpg"))
            result = SERVICE.recognize(image_bytes, suffix)
        except Exception as error:
            self._send_json({
                "ok": False,
                "error": "OCR failed",
                "details": str(error),
            }, status=500)
            return

        self._send_json(result)

    def log_message(self, format, *args):
        if os.environ.get("OCR_ACCESS_LOG", "0") == "1":
            super().log_message(format, *args)

    def _safe_suffix(self, filename):
        _, extension = os.path.splitext(str(filename))
        extension = extension.lower()
        if extension in {".jpg", ".jpeg", ".png", ".webp", ".gif", ".heic", ".heif"}:
            return extension
        return ".jpg"

    def _send_json(self, data, status=200):
        body = json.dumps(data, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def main():
    host = os.environ.get("OCR_HOST", "127.0.0.1")
    port = int(os.environ.get("OCR_PORT", "8765"))
    server = ThreadingHTTPServer((host, port), Handler)
    print(f"PaddleOCR VIN service listening on {host}:{port}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
