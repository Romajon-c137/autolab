"use client";

import { useEffect, useState } from "react";
import { Application, Inspection, apiFetch, humanError, isoDate, useSession } from "./lib";
import { InspectionDetail } from "./InspectionDetail";
import { Spinner } from "./Spinner";

export function ApplicationsView() {
  const { serverUrl, sessionKey } = useSession();
  const today = isoDate(new Date());
  const [dateFrom, setDateFrom] = useState(today);
  const [dateTo, setDateTo] = useState(today);
  const [items, setItems] = useState<Application[]>([]);
  const [query, setQuery] = useState("");
  const [queryActive, setQueryActive] = useState(false);
  const [selected, setSelected] = useState<Inspection | null>(null);
  const [openingId, setOpeningId] = useState<number | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");

  async function load(showSpinner = false, queryOverride?: string) {
    if (showSpinner) setLoading(true);
    setError("");
    try {
      const trimmedQuery = (queryOverride ?? query).trim();
      const params = new URLSearchParams(
        trimmedQuery ? { q: trimmedQuery } : { date_from: dateFrom, date_to: dateTo }
      );
      setQueryActive(Boolean(trimmedQuery));
      const data = await apiFetch<{ applications: Application[] }>(
        serverUrl,
        sessionKey,
        `/api/client-applications/list/?${params}`
      );
      setItems(data.applications);
    } catch (err) {
      setError(humanError(err));
    } finally {
      setLoading(false);
    }
  }

  function resetQuery() {
    setQuery("");
    setQueryActive(false);
    load(true, "");
  }

  useEffect(() => {
    load(true);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  async function openInspection(application: Application) {
    if (!application.inspection_id) return;
    setOpeningId(application.id);
    setError("");
    try {
      const data = await apiFetch<{ inspection: Inspection }>(
        serverUrl,
        sessionKey,
        `/api/inspections/${application.inspection_id}/`
      );
      setSelected(data.inspection);
    } catch (err) {
      setError(humanError(err));
    } finally {
      setOpeningId(null);
    }
  }

  return (
    <>
      <div className="topbar">
        <div className="page-title">
          <h1>Заявки</h1>
          <p>Заявки, поданные клиентами на zayavka.glasscenter.kg</p>
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
          <button className="btn" onClick={() => load(true)}>
            Найти
          </button>
          <div className="vin-global-search">
            <input
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              onKeyDown={(event) => {
                if (event.key === "Enter") load(true);
              }}
              placeholder="Поиск: имя, ИНН, телефон, VIN"
            />
            <button className="btn secondary" onClick={() => load(true)}>
              Найти
            </button>
            {queryActive && (
              <button className="btn ghost" onClick={resetQuery}>
                Сброс
              </button>
            )}
          </div>
        </div>
      )}
      {error && <div className="error">{error}</div>}
      {selected ? (
        <InspectionDetail inspection={selected} />
      ) : loading ? (
        <div className="card empty">
          <Spinner label="Загрузка заявок..." />
        </div>
      ) : (
        <div className="inspection-list application-list">
          {items.length === 0 ? (
            <div className="card empty">Заявки не найдены</div>
          ) : (
            <>
              <div className="inspection-header" aria-hidden="true">
                <span>Имя</span>
                <span>ИНН</span>
                <span>Телефон</span>
                <span>VIN</span>
                <span />
              </div>
              {items.map((item) => (
                <ApplicationCard
                  key={item.id}
                  application={item}
                  opening={openingId === item.id}
                  onOpen={() => openInspection(item)}
                />
              ))}
            </>
          )}
        </div>
      )}
    </>
  );
}

function ApplicationCard({
  application,
  opening,
  onOpen,
}: {
  application: Application;
  opening: boolean;
  onOpen: () => void;
}) {
  return (
    <article className="inspection-row">
      <div className="inspection-cell">
        <span>Имя</span>
        <strong>{application.applicant_name || "-"}</strong>
      </div>
      <div className="inspection-cell">
        <span>ИНН</span>
        <strong>{application.inn || "-"}</strong>
      </div>
      <div className="inspection-cell">
        <span>Телефон</span>
        <strong>{application.phone || "-"}</strong>
      </div>
      <div className="inspection-cell vin-cell">
        <span>VIN</span>
        <strong>{application.vin || "-"}</strong>
      </div>
      <div className="actions">
        <button
          className="btn secondary"
          onClick={onOpen}
          disabled={!application.inspection_id || opening}
          title={application.inspection_id ? "Открыть осмотр" : "Осмотр ещё не создан"}
        >
          {opening ? "Открываем..." : "Открыть"}
        </button>
        {application.pdf && (
          <button
            className="btn secondary"
            onClick={() => window.open(application.pdf, "_blank", "noopener,noreferrer")}
            title="Открыть PDF заявки"
          >
            Документ
          </button>
        )}
      </div>
    </article>
  );
}
