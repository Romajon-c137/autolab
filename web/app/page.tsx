"use client";

import { FormEvent, useEffect, useMemo, useState } from "react";
import {
  ChartColumn,
  ExternalLink,
  ListChecks,
  LogOut,
  Menu,
  PanelLeftClose,
  PanelLeftOpen,
} from "lucide-react";

const API_URL = process.env.NEXT_PUBLIC_API_URL ?? "";

type Role = "operator" | "manager" | "admin";
type Section = "inspections" | "reports";

type User = {
  id: number;
  login: string;
  role: Role;
  branch: null | { id: number; name: string };
};

type BranchOption = {
  id: number;
  name: string;
};

type Inspection = {
  id: number;
  title: string;
  plate_number: string;
  brand: string;
  vehicle_category: string;
  vin: string;
  created_at: string;
  branch: null | { id: number; name: string };
  created_by: null | { id: number; login: string };
  photos: Record<string, string>;
  document_pdf?: string;
  photo_taken_at?: Record<string, string>;
};

type ReportSummary = {
  period: { date_from: string; date_to: string };
  totals: { period: number; today: number; week: number; month: number };
  branches: Array<{ id: number | null; name: string; inspections_count: number }>;
};

const photoLabels: Record<string, string> = {
  front_photo: "Спереди",
  rear_photo: "Сзади",
  left_photo: "Слева",
  right_photo: "Справа",
  mileage_photo: "Пробег",
  vin_photo: "VIN",
};

export default function Page() {
  const [serverUrl, setServerUrl] = useState(API_URL);
  const [sessionKey, setSessionKey] = useState("");
  const [user, setUser] = useState<User | null>(null);
  const [section, setSection] = useState<Section>("inspections");
  const [error, setError] = useState("");
  const [sidebarCollapsed, setSidebarCollapsed] = useState(false);
  const [mobileMenuOpen, setMobileMenuOpen] = useState(false);
  const [branches, setBranches] = useState<BranchOption[]>([]);

  useEffect(() => {
    setSessionKey(localStorage.getItem("session_key") ?? "");
    setServerUrl(localStorage.getItem("server_url") ?? API_URL);
  }, []);

  useEffect(() => {
    if (!sessionKey) return;
    apiFetch<{ user: User }>(serverUrl, sessionKey, "/api/auth/me/")
      .then((data) => setUser(data.user))
      .catch(() => {
        localStorage.removeItem("session_key");
        setSessionKey("");
        setUser(null);
      });
  }, [serverUrl, sessionKey]);

  useEffect(() => {
    if (!sessionKey || !canViewReports(user)) return;
    apiFetch<{ branches: BranchOption[] }>(serverUrl, sessionKey, "/api/branches/")
      .then((data) => setBranches(data.branches))
      .catch(() => setBranches([]));
  }, [serverUrl, sessionKey, user]);

  if (!sessionKey || !user) {
    return (
      <LoginPage
        serverUrl={serverUrl}
        onServerUrl={setServerUrl}
        onLogin={(nextSession, nextUser) => {
          localStorage.setItem("server_url", serverUrl);
          localStorage.setItem("session_key", nextSession);
          setSessionKey(nextSession);
          setUser(nextUser);
        }}
        onError={setError}
        error={error}
      />
    );
  }

  const canReports = user.role === "manager" || user.role === "admin";

  function goToSection(nextSection: Section) {
    setSection(nextSection);
    setMobileMenuOpen(false);
  }

  return (
    <div className={sidebarCollapsed ? "app-shell sidebar-collapsed" : "app-shell"}>
      <div className="mobile-appbar">
        <button
          className="mobile-menu-button"
          onClick={() => setMobileMenuOpen(true)}
          title="Открыть меню"
          aria-label="Открыть меню"
        >
          <Menu className="nav-item-icon" aria-hidden="true" />
        </button>
        <div>
          <strong>Авто лаборатория</strong>
          <span>{user.login}</span>
        </div>
      </div>
      {mobileMenuOpen && (
        <button
          className="mobile-scrim"
          onClick={() => setMobileMenuOpen(false)}
          aria-label="Закрыть меню"
        />
      )}
      <aside className={mobileMenuOpen ? "sidebar mobile-open" : "sidebar"}>
        <button
          className="menu-toggle"
          onClick={() => setSidebarCollapsed((value) => !value)}
          title={sidebarCollapsed ? "Открыть меню" : "Скрыть меню"}
        >
          {sidebarCollapsed ? (
            <PanelLeftOpen className="nav-item-icon" aria-hidden="true" />
          ) : (
            <PanelLeftClose className="nav-item-icon" aria-hidden="true" />
          )}
        </button>
        <div className="sidebar-content">
          <div className="brand">Авто лаборатория</div>
          <div className="user-box">
            {user.login} · {roleLabel(user.role)}
            <br />
            {user.branch?.name ?? "Все филиалы"}
          </div>
        </div>
        <nav className="nav">
          <button
            className={section === "inspections" ? "active" : ""}
            onClick={() => goToSection("inspections")}
            title="Осмотры и печать"
          >
            <ListChecks className="nav-item-icon" aria-hidden="true" />
            <span className="nav-label">Осмотры и печать</span>
          </button>
          {canReports && (
            <details className="nav-dropdown">
              <summary
                className={section === "reports" ? "active" : ""}
                onClick={(event) => {
                  if (sidebarCollapsed) {
                    event.preventDefault();
                  }
                }}
                title="Отчеты"
              >
                <ChartColumn className="nav-item-icon" aria-hidden="true" />
                <span className="nav-label">Отчеты</span>
              </summary>
              <div className="submenu">
                {branches.length === 0 ? (
                  <span>Филиалы не найдены</span>
                ) : (
                  branches.map((branch) => (
                    <button
                      key={branch.id}
                      onClick={() => goToSection("reports")}
                      title={branch.name}
                    >
                      {branch.name}
                    </button>
                  ))
                )}
              </div>
            </details>
          )}
        </nav>
        <button
          className="logout-button"
          title="Выйти"
          aria-label="Выйти"
          onClick={async () => {
            await apiFetch(serverUrl, sessionKey, "/api/auth/logout/", {
              method: "POST",
            }).catch(() => null);
            localStorage.removeItem("session_key");
            setSessionKey("");
            setUser(null);
          }}
        >
          <LogOut className="nav-item-icon" aria-hidden="true" />
          <span className="nav-label">Выйти</span>
        </button>
      </aside>
      <main className="main">
        {section === "reports" && canReports ? (
          <ReportsPage serverUrl={serverUrl} sessionKey={sessionKey} />
        ) : (
          <InspectionsPage serverUrl={serverUrl} sessionKey={sessionKey} />
        )}
      </main>
    </div>
  );
}

function LoginPage({
  serverUrl,
  onServerUrl,
  onLogin,
  onError,
  error,
}: {
  serverUrl: string;
  onServerUrl: (value: string) => void;
  onLogin: (sessionKey: string, user: User) => void;
  onError: (value: string) => void;
  error: string;
}) {
  const [login, setLogin] = useState("");
  const [password, setPassword] = useState("");
  const [loading, setLoading] = useState(false);

  async function submit(event: FormEvent) {
    event.preventDefault();
    setLoading(true);
    onError("");
    try {
      const data = await apiFetch<{ session_key: string; user: User }>(
        serverUrl,
        "",
        "/api/auth/login/",
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ login, password }),
        }
      );
      onLogin(data.session_key, data.user);
    } catch (err) {
      onError(humanError(err));
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="login-page">
      <form className="login-panel" onSubmit={submit} autoComplete="off">
        <h1>Вход</h1>
        <p>Реестр осмотров, печать и отчеты</p>
        <label className="field">
          <span>Сервер</span>
          <input
            value={serverUrl}
            onChange={(e) => onServerUrl(e.target.value)}
            autoComplete="off"
          />
        </label>
        <label className="field">
          <span>Логин</span>
          <input
            value={login}
            onChange={(e) => setLogin(e.target.value)}
            autoComplete="off"
          />
        </label>
        <label className="field">
          <span>Пароль</span>
          <input
            type="password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            autoComplete="off"
          />
        </label>
        <div style={{ marginTop: 16 }}>
          <button className="btn" disabled={loading}>
            {loading ? "Вход..." : "Войти"}
          </button>
        </div>
        {error && <div className="error">{error}</div>}
      </form>
    </div>
  );
}

function InspectionsPage({
  serverUrl,
  sessionKey,
}: {
  serverUrl: string;
  sessionKey: string;
}) {
  const today = isoDate(new Date());
  const [dateFrom, setDateFrom] = useState(today);
  const [dateTo, setDateTo] = useState(today);
  const [items, setItems] = useState<Inspection[]>([]);
  const [selected, setSelected] = useState<Inspection | null>(null);
  const [error, setError] = useState("");

  async function load() {
    setError("");
    try {
      const params = new URLSearchParams({
        date_from: dateFrom,
        date_to: dateTo,
      });
      const data = await apiFetch<{ inspections: Inspection[] }>(
        serverUrl,
        sessionKey,
        `/api/inspections/?${params}`
      );
      setItems(data.inspections);
      if (selected) {
        const fresh = data.inspections.find((item) => item.id === selected.id);
        setSelected(fresh ?? null);
      }
    } catch (err) {
      setError(humanError(err));
    }
  }

  useEffect(() => {
    load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  return (
    <>
      <div className="topbar">
        <div className="page-title">
          <h1>Осмотры</h1>
          <p>Поиск авто и печать листа с фотографиями</p>
        </div>
      </div>
      {selected ? (
        <div className="detail-actions-line no-print">
          <button className="btn secondary" onClick={() => setSelected(null)}>
            Назад
          </button>
          <button className="btn" onClick={() => window.print()}>
            Печать
          </button>
        </div>
      ) : (
        <div className="filters no-print">
          <input type="date" value={dateFrom} onChange={(e) => setDateFrom(e.target.value)} />
          <input type="date" value={dateTo} onChange={(e) => setDateTo(e.target.value)} />
          <button className="btn" onClick={load}>
            Найти
          </button>
        </div>
      )}
      {error && <div className="error">{error}</div>}
      {selected ? (
        <InspectionDetail inspection={selected} />
      ) : (
        <div className="inspection-list">
          {items.length === 0 ? (
            <div className="card empty">Осмотры не найдены</div>
          ) : (
            <>
              <div className="inspection-header" aria-hidden="true">
                <span>Марка / модель</span>
                <span>VIN</span>
                <span>Дата</span>
                <span>Оператор</span>
                <span />
              </div>
              {items.map((item) => (
                <InspectionCard
                  key={item.id}
                  inspection={item}
                  onOpen={() => setSelected(item)}
                />
              ))}
            </>
          )}
        </div>
      )}
    </>
  );
}

function InspectionCard({
  inspection,
  onOpen,
}: {
  inspection: Inspection;
  onOpen: () => void;
}) {
  return (
    <article className="inspection-row">
      <div className="inspection-cell">
        <span>Марка / модель</span>
        <strong>{inspection.brand || "-"}</strong>
      </div>
      <div className="inspection-cell vin-cell">
        <span>VIN</span>
        <strong>{inspection.vin || "-"}</strong>
      </div>
      <div className="inspection-cell">
        <span>Дата</span>
        <strong>{formatDate(inspection.created_at)}</strong>
      </div>
      <div className="inspection-cell">
        <span>Оператор</span>
        <strong>{inspection.created_by?.login ?? "-"}</strong>
      </div>
      <div className="actions">
        <button className="btn secondary" onClick={onOpen}>
          Открыть
        </button>
      </div>
    </article>
  );
}

function InspectionDetail({
  inspection,
}: {
  inspection: Inspection;
}) {
  const [activePhoto, setActivePhoto] = useState<null | { src: string; label: string }>(null);
  const pdfName = pdfFileName(inspection);

  return (
    <section className="detail-grid">
      <div className="detail-sidebar">
        <table className="detail-table">
          <tbody>
            <tr>
              <th>Название</th>
              <td>{inspection.title || "-"}</td>
            </tr>
            <tr>
              <th>Марка / модель</th>
              <td>{inspection.brand || "-"}</td>
            </tr>
            <tr>
              <th>Категория</th>
              <td>{inspection.vehicle_category || "M1"}</td>
            </tr>
            <tr>
              <th>VIN</th>
              <td>{inspection.vin || "-"}</td>
            </tr>
            <tr>
              <th>Дата</th>
              <td>{formatDate(inspection.created_at)}</td>
            </tr>
            <tr>
              <th>Оператор</th>
              <td>{inspection.created_by?.login ?? "-"}</td>
            </tr>
          </tbody>
        </table>
        {inspection.document_pdf ? (
          <section className="document-panel">
            <div className="document-panel-header">
              <h3>Документ</h3>
              <div className="document-actions">
                <a href={inspection.document_pdf} target="_blank" rel="noreferrer">
                  Предпросмотр
                </a>
                <a href={inspection.document_pdf} download={pdfName}>
                  Скачать PDF
                </a>
              </div>
            </div>
            <div className="document-preview-card">
              <div className="document-preview-page">
                <div className="document-preview-lines">
                  <span />
                  <span />
                  <span />
                  <span />
                  <span />
                </div>
                <div className="document-preview-table">
                  <span />
                  <span />
                  <span />
                  <span />
                  <span />
                  <span />
                </div>
              </div>
              <div>
                <strong>PDF документ готов</strong>
                <p>Файл сохранен вместе с осмотром.</p>
              </div>
            </div>
          </section>
        ) : null}
      </div>
      <div className="photo-grid">
        {Object.entries(photoLabels).map(([key, label]) => (
          <div className="photo-card" key={key}>
            {inspection.photos[key] ? (
              <button
                className="photo-open-button"
                type="button"
                onClick={() => setActivePhoto({ src: inspection.photos[key], label })}
              >
                <img src={inspection.photos[key]} alt={label} />
              </button>
            ) : (
              <div style={{ aspectRatio: "4 / 3" }} />
            )}
            <span>
              <strong>{label}</strong>
              {formatPhotoDate(inspection, key)}
            </span>
          </div>
        ))}
      </div>
      {activePhoto ? (
        <div className="photo-modal" role="dialog" aria-modal="true" onClick={() => setActivePhoto(null)}>
          <div className="photo-modal-content" onClick={(event) => event.stopPropagation()}>
            <button className="photo-modal-close" type="button" onClick={() => setActivePhoto(null)}>
              Закрыть
            </button>
            <img src={activePhoto.src} alt={activePhoto.label} />
            <span>{activePhoto.label}</span>
          </div>
        </div>
      ) : null}
    </section>
  );
}

function ReportsPage({
  serverUrl,
  sessionKey,
}: {
  serverUrl: string;
  sessionKey: string;
}) {
  const today = isoDate(new Date());
  const [dateFrom, setDateFrom] = useState(today);
  const [dateTo, setDateTo] = useState(today);
  const [summary, setSummary] = useState<ReportSummary | null>(null);
  const [inspections, setInspections] = useState<Inspection[]>([]);
  const [selected, setSelected] = useState<Inspection | null>(null);
  const [error, setError] = useState("");

  async function load() {
    setError("");
    try {
      const params = new URLSearchParams({ date_from: dateFrom, date_to: dateTo });
      const [summaryData, inspectionsData] = await Promise.all([
        apiFetch<ReportSummary>(serverUrl, sessionKey, `/api/reports/summary/?${params}`),
        apiFetch<{ inspections: Inspection[] }>(serverUrl, sessionKey, `/api/inspections/?${params}`),
      ]);
      setSummary(summaryData);
      setInspections(inspectionsData.inspections);
    } catch (err) {
      setError(humanError(err));
    }
  }

  useEffect(() => {
    load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const totals = summary?.totals;
  const isTodayPeriod = dateFrom === today && dateTo === today;
  const periodLabel = dateFrom === dateTo
    ? formatDateOnly(dateFrom)
    : `${formatDateOnly(dateFrom)} - ${formatDateOnly(dateTo)}`;

  return (
    <>
      <div className="topbar">
        <div className="page-title">
          <h1>Отчеты</h1>
          <p>Статистика техосмотров по филиалам</p>
        </div>
      </div>
      {selected ? (
        <div className="detail-actions-line no-print">
          <button className="btn secondary" onClick={() => setSelected(null)}>
            Назад
          </button>
          <button className="btn" onClick={() => window.print()}>
            Печать
          </button>
        </div>
      ) : (
        <div className="filters">
          <input type="date" value={dateFrom} onChange={(e) => setDateFrom(e.target.value)} />
          <input type="date" value={dateTo} onChange={(e) => setDateTo(e.target.value)} />
          <button className="btn" onClick={load}>
            Найти
          </button>
        </div>
      )}
      {error && <div className="error">{error}</div>}
      {selected ? (
        <InspectionDetail inspection={selected} />
      ) : summary && (
        <>
          <div className="report-totals">
            <div className="primary-total">
              <span>{isTodayPeriod ? "Сегодня" : "За выбранный период"}</span>
              <strong>{totals?.period ?? 0}</strong>
              <small>{periodLabel}</small>
            </div>
            <div>
              <span>Сегодня</span>
              <strong>{totals?.today ?? 0}</strong>
              <small>{formatDateOnly(today)}</small>
            </div>
          </div>
          <div className="inspection-list report-inspection-list">
            {inspections.length === 0 ? (
              <div className="card empty">Осмотры за период не найдены</div>
            ) : (
              <>
                <div className="inspection-header" aria-hidden="true">
                  <span>Марка / модель</span>
                  <span>VIN</span>
                  <span>Дата</span>
                  <span>Оператор</span>
                  <span />
                </div>
                {inspections.map((inspection) => (
                  <article className="inspection-row" key={inspection.id}>
                    <div className="inspection-cell">
                      <span>Марка / модель</span>
                      <strong>{inspection.brand || "-"}</strong>
                    </div>
                    <div className="inspection-cell vin-cell">
                      <span>VIN</span>
                      <strong>{inspection.vin || "-"}</strong>
                    </div>
                    <div className="inspection-cell">
                      <span>Дата</span>
                      <strong>{formatDate(inspection.created_at)}</strong>
                    </div>
                    <div className="inspection-cell">
                      <span>Оператор</span>
                      <strong>{inspection.created_by?.login ?? "-"}</strong>
                    </div>
                    <div className="actions">
                      <button
                        className="icon-button"
                        onClick={() => setSelected(inspection)}
                        title="Открыть осмотр"
                        aria-label="Открыть осмотр"
                      >
                        <ExternalLink aria-hidden="true" />
                      </button>
                    </div>
                  </article>
                ))}
              </>
            )}
          </div>
        </>
      )}
    </>
  );
}

async function apiFetch<T>(
  serverUrl: string,
  sessionKey: string,
  path: string,
  init: RequestInit = {}
): Promise<T> {
  const headers = new Headers(init.headers);
  if (sessionKey) headers.set("X-Session-Key", sessionKey);
  const response = await fetch(`${serverUrl}${path}`, {
    ...init,
    headers,
  });
  const url = `${serverUrl}${path}`;
  const text = await response.text();
  const data = text ? JSON.parse(text) : {};
  if (!response.ok || data.ok === false) {
    const message = data.error ?? (text || response.statusText || "Unknown error");
    throw new Error(`HTTP ${response.status}: ${message}\nURL: ${url}`);
  }
  return data;
}

function roleLabel(role: Role) {
  if (role === "admin") return "Администратор";
  if (role === "manager") return "Руководитель";
  return "Оператор";
}

function canViewReports(user: User | null) {
  return user?.role === "manager" || user?.role === "admin";
}

function isoDate(date: Date) {
  return date.toISOString().slice(0, 10);
}

function formatDate(value: string) {
  return new Intl.DateTimeFormat("ru-RU", {
    dateStyle: "short",
    timeStyle: "short",
  }).format(new Date(value));
}

function formatDateOnly(value: string) {
  return new Intl.DateTimeFormat("ru-RU", {
    dateStyle: "short",
  }).format(new Date(`${value}T00:00:00`));
}

function formatPhotoDate(inspection: Inspection, photoKey: string) {
  return formatDate(inspection.photo_taken_at?.[photoKey] || inspection.created_at);
}

function pdfFileName(inspection: Inspection) {
  const brand = sanitizeFilePart(inspection.brand) || "auto";
  const vin = sanitizeFilePart(inspection.vin) || `inspection-${inspection.id}`;
  return `${brand}-${vin}.pdf`;
}

function sanitizeFilePart(value: string) {
  return value
    .trim()
    .replace(/\s+/g, "_")
    .replace(/[\\/:*?"<>|]/g, "")
    .slice(0, 80);
}

function humanError(error: unknown) {
  return error instanceof Error ? error.message : String(error);
}
