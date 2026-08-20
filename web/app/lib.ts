import { createContext, useContext } from "react";

export const API_URL = process.env.NEXT_PUBLIC_API_URL || "https://autolab.glasscenter.kg";

export type Role = "operator" | "manager" | "admin";
export type Section = "inspections" | "reports" | "applications";

export type User = {
  id: number;
  login: string;
  role: Role;
  branch: null | { id: number; name: string };
};

export type LoginResponse =
  | {
      session_key: string;
      user: User;
      two_factor_required?: false;
    }
  | {
      two_factor_required: true;
      challenge_id: string;
      phone_masked: string;
      expires_in: number;
      debug_code?: string;
    };

export type Inspection = {
  id: number;
  title: string;
  operation_type?: string;
  operation_type_label?: string;
  plate_number: string;
  brand: string;
  vehicle_category: string;
  amount: number;
  vin: string;
  created_at: string;
  branch: null | { id: number; name: string };
  created_by: null | {
    id: number;
    login: string;
    first_name?: string;
    last_name?: string;
    full_name?: string;
  };
  photos: Record<string, string>;
  document_pdf?: string;
  application_pdf?: string;
  photo_taken_at?: Record<string, string>;
};

export type ReportSummary = {
  period: { date_from: string; date_to: string };
  totals: { period: number; today: number; week: number; month: number };
  branches: Array<{ id: number | null; name: string; inspections_count: number }>;
};

export const photoLabels: Record<string, string> = {
  front_photo: "Спереди",
  rear_photo: "Сзади",
  left_photo: "Слева",
  right_photo: "Справа",
  mileage_photo: "Пробег",
  vin_photo: "VIN",
};

export const vehicleCategories = ["M1", "M2", "M3", "N1", "N2", "N3"];
export const REPORT_TYPE_OPTIONS = [
  { value: "all", label: "Все" },
  { value: "tech_inspection", label: "Техосмотр" },
  { value: "sbgts", label: "СБКТС" },
  { value: "legalization", label: "Легализация" },
  { value: "conversion", label: "Переоборудование" },
];

export type SessionValue = {
  serverUrl: string;
  sessionKey: string;
  user: User;
  canReports: boolean;
  logout: () => void;
};

export const SessionContext = createContext<SessionValue | null>(null);

export function useSession(): SessionValue {
  const value = useContext(SessionContext);
  if (!value) throw new Error("useSession must be used within AuthShell");
  return value;
}

export async function apiFetch<T>(
  serverUrl: string,
  sessionKey: string,
  path: string,
  init: RequestInit = {}
): Promise<T> {
  const normalizedServerUrl = normalizeServerUrl(serverUrl);
  const headers = new Headers(init.headers);
  if (sessionKey) headers.set("X-Session-Key", sessionKey);
  const response = await fetch(`${normalizedServerUrl}${path}`, {
    ...init,
    headers,
  });
  const url = `${normalizedServerUrl}${path}`;
  const text = await response.text();
  const data = text ? JSON.parse(text) : {};
  if (!response.ok || data.ok === false) {
    const message = data.error ?? (text || response.statusText || "Unknown error");
    throw new Error(`HTTP ${response.status}: ${message}\nURL: ${url}`);
  }
  return data;
}

export function normalizeServerUrl(value: string) {
  const trimmed = value.trim() || API_URL;
  const withProtocol = /^https?:\/\//i.test(trimmed) ? trimmed : `https://${trimmed}`;
  try {
    return new URL(withProtocol).origin;
  } catch {
    return API_URL;
  }
}

export function roleLabel(role: Role) {
  if (role === "admin") return "Администратор";
  if (role === "manager") return "Руководитель";
  return "Оператор";
}

export function operationLabel(inspection: Inspection) {
  if (inspection.operation_type_label) return inspection.operation_type_label;
  if (inspection.operation_type === "tech_inspection") return "Техосмотр";
  if (inspection.operation_type === "legalization") return "Легализация";
  if (inspection.operation_type === "conversion") return "Переоборудование";
  return "СБКТС";
}

export function operatorName(user: Inspection["created_by"]) {
  if (!user) return "-";
  const fullName = (user.full_name ?? "").trim();
  if (fullName && fullName !== user.login) return fullName;
  const name = [user.last_name, user.first_name]
    .map((part) => (part ?? "").trim())
    .filter(Boolean)
    .join(" ");
  return name || user.login || "-";
}

export function categoryClassName(category: string) {
  if (category.startsWith("M")) return "category-mark category-mark-m";
  if (category.startsWith("N")) return "category-mark category-mark-n";
  return "category-mark";
}

export type ClientApplication = {
  id: number;
  vin: string;
  applicant: string;
  inn: string;
  phone: string;
  vehicle_name: string;
  plate_number: string;
  year: string;
  application_pdf: string;
  inspection_id: number | null;
  created_at: string;
};

export function sectionPath(section: Section) {
  if (section === "reports") return "/reports";
  if (section === "applications") return "/applications";
  return "/inspections";
}

export function isoDate(date: Date) {
  return date.toISOString().slice(0, 10);
}

export function formatDate(value: string) {
  return new Intl.DateTimeFormat("ru-RU", {
    dateStyle: "short",
    timeStyle: "short",
  }).format(new Date(value));
}

export function formatDateOnly(value: string) {
  return new Intl.DateTimeFormat("ru-RU", {
    dateStyle: "short",
  }).format(new Date(`${value}T00:00:00`));
}

export function formatMoney(value: number | null | undefined) {
  const amount = Number(value ?? 0);
  if (!Number.isFinite(amount) || amount <= 0) return "-";
  return new Intl.NumberFormat("ru-RU").format(amount);
}

export function formatPhotoDate(inspection: Inspection, photoKey: string) {
  return formatDate(inspection.photo_taken_at?.[photoKey] || inspection.created_at);
}

export function pdfFileName(inspection: Inspection) {
  const brand = sanitizeFilePart(inspection.brand) || "auto";
  const vin = sanitizeFilePart(inspection.vin) || `inspection-${inspection.id}`;
  return `${brand}-${vin}.pdf`;
}

export function sanitizeFilePart(value: string) {
  return value
    .trim()
    .replace(/\s+/g, "_")
    .replace(/[\\/:*?"<>|]/g, "")
    .slice(0, 80);
}

export function humanError(error: unknown) {
  return error instanceof Error ? error.message : String(error);
}
