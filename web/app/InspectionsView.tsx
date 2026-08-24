"use client";

import { useEffect, useRef, useState } from "react";
import { Inspection, apiFetch, formatDate, humanError, isoDate, operationLabel, useSession } from "./lib";
import { InspectionDetail } from "./InspectionDetail";
import { Spinner } from "./Spinner";

export function InspectionsView() {
  const { serverUrl, sessionKey } = useSession();
  const today = isoDate(new Date());
  const [dateFrom, setDateFrom] = useState(today);
  const [dateTo, setDateTo] = useState(today);
  const [items, setItems] = useState<Inspection[]>([]);
  const [selected, setSelected] = useState<Inspection | null>(null);
  const [openingId, setOpeningId] = useState<number | null>(null);
  const [autoSync, setAutoSync] = useState(false);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const lastSignature = useRef("");

  useEffect(() => {
    try {
      if (localStorage.getItem("autoSync") === "1") setAutoSync(true);
    } catch {
      // localStorage unavailable
    }
  }, []);

  useEffect(() => {
    try {
      localStorage.setItem("autoSync", autoSync ? "1" : "0");
    } catch {
      // localStorage unavailable
    }
  }, [autoSync]);

  function signatureOf(list: Inspection[]) {
    return list
      .map((item) => `${item.id}:${item.created_at}:${item.operation_type ?? ""}`)
      .join("|");
  }

  async function load(showSpinner = false) {
    if (showSpinner) setLoading(true);
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
      const sig = signatureOf(data.inspections);
      if (sig !== lastSignature.current) {
        lastSignature.current = sig;
        setItems(data.inspections);
      }
    } catch (err) {
      setError(humanError(err));
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    if (!autoSync) return;
    load();
    const timer = setInterval(load, 15000);
    return () => clearInterval(timer);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [autoSync, dateFrom, dateTo]);

  useEffect(() => {
    load(true);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  async function openInspection(inspection: Inspection) {
    setOpeningId(inspection.id);
    setError("");
    try {
      const data = await apiFetch<{ inspection: Inspection }>(
        serverUrl,
        sessionKey,
        `/api/inspections/${inspection.id}/`
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
          <h1>Осмотры</h1>
          <p>Поиск авто и печать листа с фотографиями</p>
        </div>
        <label className={`auto-sync-toggle${autoSync ? " active" : ""}`}>
          <input
            type="checkbox"
            checked={autoSync}
            onChange={(event) => setAutoSync(event.target.checked)}
          />
          <span>Автосинхронизация</span>
        </label>
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
        </div>
      )}
      {error && <div className="error">{error}</div>}
      {selected ? (
        <InspectionDetail inspection={selected} />
      ) : loading ? (
        <div className="card empty">
          <Spinner label="Загрузка осмотров..." />
        </div>
      ) : (
        <div className="inspection-list">
          {items.length === 0 ? (
            <div className="card empty">Осмотры не найдены</div>
          ) : (
            <>
              <div className="inspection-header" aria-hidden="true">
                <span>Марка / модель</span>
                <span>Тип операции</span>
                <span>VIN</span>
                <span>Дата</span>
                <span>Оператор</span>
                <span />
              </div>
              {items.map((item) => (
                <InspectionCard
                  key={item.id}
                  inspection={item}
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

function InspectionCard({
  inspection,
  opening,
  onOpen,
}: {
  inspection: Inspection;
  opening: boolean;
  onOpen: () => void;
}) {
  return (
    <article className="inspection-row">
      <div className="inspection-cell">
        <span>Марка / модель</span>
        <strong>{inspection.brand || "-"}</strong>
      </div>
      <div className="inspection-cell">
        <span>Тип операции</span>
        <strong>{operationLabel(inspection)}</strong>
      </div>
      <div className="inspection-cell vin-cell">
        <span>VIN</span>
        <strong>{inspection.vin || "-"}</strong>
      </div>
      <div className="inspection-cell date-cell">
        <span>Дата</span>
        <strong>{formatDate(inspection.created_at)}</strong>
      </div>
      <div className="inspection-cell">
        <span>Оператор</span>
        <strong>{inspection.created_by?.login ?? "-"}</strong>
      </div>
      <div className="actions">
        <button className="btn secondary" onClick={onOpen} disabled={opening}>
          {opening ? "Загрузка..." : "Открыть"}
        </button>
      </div>
    </article>
  );
}
