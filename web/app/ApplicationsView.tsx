"use client";

import { useEffect, useRef, useState } from "react";
import { ClientApplication, apiFetch, formatDate, humanError, useSession } from "./lib";

export function ApplicationsView() {
  const { serverUrl, sessionKey } = useSession();
  const [items, setItems] = useState<ClientApplication[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const intervalRef = useRef<ReturnType<typeof setInterval> | null>(null);

  async function load(showSpinner = false) {
    if (showSpinner) setLoading(true);
    setError("");
    try {
      const data = await apiFetch<{ applications: ClientApplication[] }>(
        serverUrl,
        sessionKey,
        "/api/client-applications/"
      );
      setItems(data.applications);
    } catch (err) {
      setError(humanError(err));
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    load(true);
    intervalRef.current = setInterval(() => load(), 30_000);
    return () => {
      if (intervalRef.current) clearInterval(intervalRef.current);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  return (
    <>
      <div className="topbar">
        <div className="page-title">
          <h1>Заявки клиентов</h1>
          <p>Заявки за сегодня · обновляется каждые 30 сек</p>
        </div>
        <button className="btn" onClick={() => load(true)} disabled={loading}>
          {loading ? "Загрузка..." : "Обновить"}
        </button>
      </div>

      {error && <div className="error">{error}</div>}

      {loading && items.length === 0 && (
        <div className="card empty">Загрузка заявок...</div>
      )}

      {!loading && items.length === 0 && !error && (
        <div className="card empty">Заявок на сегодня нет</div>
      )}

      {items.length > 0 && (
        <div className="applications-table-wrap">
          <table className="applications-table">
            <thead>
              <tr>
                <th>Время</th>
                <th>ФИО</th>
                <th>ИНН</th>
                <th>Телефон</th>
                <th>Марка авто</th>
                <th>VIN</th>
                <th>Гос. номер</th>
                <th>Год</th>
                <th>PDF</th>
                <th>Осмотр</th>
              </tr>
            </thead>
            <tbody>
              {items.map((app) => (
                <tr key={app.id}>
                  <td style={{ whiteSpace: "nowrap" }}>{formatDate(app.created_at)}</td>
                  <td>{app.applicant || "—"}</td>
                  <td style={{ whiteSpace: "nowrap" }}>{app.inn || "—"}</td>
                  <td style={{ whiteSpace: "nowrap" }}>{app.phone || "—"}</td>
                  <td>{app.vehicle_name || "—"}</td>
                  <td style={{ whiteSpace: "nowrap", fontFamily: "monospace" }}>{app.vin}</td>
                  <td style={{ whiteSpace: "nowrap" }}>{app.plate_number || "—"}</td>
                  <td>{app.year || "—"}</td>
                  <td>
                    {app.application_pdf ? (
                      <a
                        href={app.application_pdf}
                        target="_blank"
                        rel="noopener noreferrer"
                        className="link-button"
                        style={{ marginTop: 0 }}
                      >
                        PDF
                      </a>
                    ) : (
                      "—"
                    )}
                  </td>
                  <td>
                    {app.inspection_id ? (
                      <span style={{ color: "var(--primary-dark)", fontWeight: 700 }}>
                        #{app.inspection_id}
                      </span>
                    ) : (
                      <span style={{ color: "var(--muted)" }}>Ожидает</span>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </>
  );
}
