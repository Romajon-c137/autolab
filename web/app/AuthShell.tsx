"use client";

import { FormEvent, ReactNode, useEffect, useState } from "react";
import {
  ChartColumn,
  FileText,
  ListChecks,
  LogOut,
  Menu,
  PanelLeftClose,
  PanelLeftOpen,
  PieChart,
} from "lucide-react";
import { usePathname, useRouter } from "next/navigation";
import {
  API_URL,
  LoginResponse,
  Section,
  SessionContext,
  User,
  apiFetch,
  humanError,
  normalizeServerUrl,
  roleLabel,
  sectionPath,
} from "./lib";
import { FullPageSpinner } from "./Spinner";
import { MilestoneCelebration } from "./MilestoneCelebration";

type MilestoneStatus = {
  total: number;
  reached: boolean;
  acknowledged: boolean;
  show: boolean;
};

export function AuthShell({ children }: { children: ReactNode }) {
  const router = useRouter();
  const pathname = usePathname();
  const [serverUrl, setServerUrl] = useState(API_URL);
  const [sessionKey, setSessionKey] = useState("");
  const [user, setUser] = useState<User | null>(null);
  const [authChecked, setAuthChecked] = useState(false);
  const [error, setError] = useState("");
  const [sidebarCollapsed, setSidebarCollapsed] = useState(false);
  const [mobileMenuOpen, setMobileMenuOpen] = useState(false);
  const [milestoneTotal, setMilestoneTotal] = useState<number | null>(null);
  const [milestoneClicks, setMilestoneClicks] = useState(0);

  useEffect(() => {
    const storedSessionKey = localStorage.getItem("session_key") ?? "";
    const storedServerUrl = normalizeServerUrl(localStorage.getItem("server_url") ?? API_URL);
    setServerUrl(storedServerUrl);

    if (!storedSessionKey) {
      setAuthChecked(true);
      return;
    }

    setSessionKey(storedSessionKey);
    apiFetch<{ user: User }>(storedServerUrl, storedSessionKey, "/api/auth/me/")
      .then((data) => setUser(data.user))
      .catch(() => {
        localStorage.removeItem("session_key");
        setSessionKey("");
        setUser(null);
      })
      .finally(() => setAuthChecked(true));
  }, []);

  useEffect(() => {
    if (!sessionKey || !user) return;

    apiFetch<MilestoneStatus>(serverUrl, sessionKey, "/api/milestones/1000/")
      .then((data) => {
        if (data.show) setMilestoneTotal(data.total);
      })
      .catch(() => null);
  }, [serverUrl, sessionKey, user]);

  async function confirmMilestone() {
    const nextClicks = milestoneClicks + 1;
    if (nextClicks < 10) {
      setMilestoneClicks(nextClicks);
      return;
    }

    try {
      await apiFetch<MilestoneStatus>(serverUrl, sessionKey, "/api/milestones/1000/", {
        method: "POST",
      });
      setMilestoneTotal(null);
      setMilestoneClicks(0);
    } catch {
      setMilestoneClicks(9);
    }
  }

  function logout() {
    apiFetch(serverUrl, sessionKey, "/api/auth/logout/", { method: "POST" }).catch(() => null);
    localStorage.removeItem("session_key");
    setSessionKey("");
    setUser(null);
  }

  if (!authChecked) {
    return <FullPageSpinner label="Проверка сессии..." />;
  }

  if (!sessionKey || !user) {
    return (
      <LoginPage
        serverUrl={serverUrl}
        onServerUrl={setServerUrl}
        onLogin={(nextSession, nextUser) => {
          localStorage.setItem("server_url", normalizeServerUrl(serverUrl));
          localStorage.setItem("session_key", nextSession);
          setSessionKey(nextSession);
          setUser(nextUser);
        }}
        onError={setError}
        error={error}
      />
    );
  }

  const canReports = true;
  const canReportTotals = user.role !== "mvd";
  const canDashboard = user.role === "admin";
  const canApplications = user.role !== "mvd";
  const canViewAmounts = user.role === "manager" || user.role === "admin";
  const section: Section = pathname.startsWith("/dashboard")
    ? "dashboard"
    : pathname.startsWith("/reports")
      ? "reports"
      : pathname.startsWith("/applications")
        ? "applications"
        : "inspections";

  function goToSection(nextSection: Section) {
    setMobileMenuOpen(false);
    router.push(sectionPath(nextSection));
  }

  return (
    <div className={sidebarCollapsed ? "app-shell sidebar-collapsed" : "app-shell"}>
      {milestoneTotal !== null && (
        <MilestoneCelebration
          clicks={milestoneClicks}
          total={milestoneTotal}
          onConfirm={confirmMilestone}
        />
      )}
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
          {canApplications && (
            <button
              className={section === "applications" ? "active" : ""}
              onClick={() => goToSection("applications")}
              title="Заявки"
            >
              <FileText className="nav-item-icon" aria-hidden="true" />
              <span className="nav-label">Заявки</span>
            </button>
          )}
          {canReports && (
            <button
              className={section === "reports" ? "active" : ""}
              onClick={() => goToSection("reports")}
              title="Статистика"
            >
              <ChartColumn className="nav-item-icon" aria-hidden="true" />
              <span className="nav-label">Статистика</span>
            </button>
          )}
          {canDashboard && (
            <button
              className={section === "dashboard" ? "active" : ""}
              onClick={() => goToSection("dashboard")}
              title="Аналитика"
            >
              <PieChart className="nav-item-icon" aria-hidden="true" />
              <span className="nav-label">Аналитика</span>
            </button>
          )}
        </nav>
        <button className="logout-button" title="Выйти" aria-label="Выйти" onClick={logout}>
          <LogOut className="nav-item-icon" aria-hidden="true" />
          <span className="nav-label">Выйти</span>
        </button>
      </aside>
      <main className="main">
        <SessionContext.Provider value={{
          serverUrl,
          sessionKey,
          user,
          canReports,
          canReportTotals,
          canDashboard,
          canApplications,
          canViewAmounts,
          logout,
        }}>
          {children}
        </SessionContext.Provider>
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
  const [code, setCode] = useState("");
  const [challenge, setChallenge] = useState<{
    id: string;
    phone: string;
    debugCode?: string;
  } | null>(null);
  const [loading, setLoading] = useState(false);

  async function submit(event: FormEvent) {
    event.preventDefault();
    setLoading(true);
    onError("");
    try {
      const normalizedServerUrl = normalizeServerUrl(serverUrl);
      onServerUrl(normalizedServerUrl);
      const data = await apiFetch<LoginResponse>(
        normalizedServerUrl,
        "",
        "/api/auth/login/",
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ login, password }),
        }
      );
      if (data.two_factor_required) {
        setChallenge({
          id: data.challenge_id,
          phone: data.phone_masked,
          debugCode: data.debug_code,
        });
        setCode("");
        return;
      }
      onLogin(data.session_key, data.user);
    } catch (err) {
      onError(humanError(err));
    } finally {
      setLoading(false);
    }
  }

  async function submitCode(event: FormEvent) {
    event.preventDefault();
    if (!challenge) return;

    setLoading(true);
    onError("");
    try {
      const normalizedServerUrl = normalizeServerUrl(serverUrl);
      const data = await apiFetch<{ session_key: string; user: User }>(
        normalizedServerUrl,
        "",
        "/api/auth/verify-2fa/",
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ challenge_id: challenge.id, code }),
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
      <form
        className="login-panel"
        onSubmit={challenge ? submitCode : submit}
        autoComplete="off"
      >
        <h1>Вход</h1>
        <p>
          {challenge
            ? `Код отправлен в WhatsApp ${challenge.phone}`
            : "Реестр осмотров, печать и отчеты"}
        </p>
        <label className="field">
          <span>Сервер</span>
          <input
            value={serverUrl}
            onChange={(e) => onServerUrl(e.target.value)}
            autoComplete="off"
            disabled={Boolean(challenge)}
          />
        </label>
        {challenge ? (
          <label className="field">
            <span>Код из WhatsApp</span>
            <input
              value={code}
              onChange={(e) => setCode(e.target.value.replace(/\D/g, "").slice(0, 4))}
              autoComplete="one-time-code"
              inputMode="numeric"
              maxLength={4}
              autoFocus
            />
          </label>
        ) : (
          <>
            <label className="field">
              <span>Логин</span>
              <input
                value={login}
                onChange={(e) => setLogin(e.target.value)}
                autoComplete="username"
              />
            </label>
            <label className="field">
              <span>Пароль</span>
              <input
                type="password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                autoComplete="current-password"
              />
            </label>
          </>
        )}
        <div style={{ marginTop: 16 }}>
          <button className="btn" disabled={loading}>
            {loading ? "Проверка..." : challenge ? "Подтвердить" : "Войти"}
          </button>
        </div>
        {challenge && (
          <button
            className="link-button"
            type="button"
            onClick={() => {
              setChallenge(null);
              setCode("");
              onError("");
            }}
          >
            Назад к логину
          </button>
        )}
        {challenge?.debugCode && <div className="error">Тестовый код: {challenge.debugCode}</div>}
        {error && <div className="error">{error}</div>}
      </form>
    </div>
  );
}
