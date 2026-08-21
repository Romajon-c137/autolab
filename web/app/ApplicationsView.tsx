"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { Application, Inspection, apiFetch, humanError, isoDate, useSession } from "./lib";
import { InspectionDetail } from "./InspectionDetail";
import { Spinner } from "./Spinner";

export function ApplicationsView() {
  const { serverUrl, sessionKey, canApplications } = useSession();
  const router = useRouter();

  useEffect(() => {
    if (!canApplications) router.replace("/inspections");
  }, [canApplications, router]);

  if (!canApplications) return null;

  return <ApplicationsContent serverUrl={serverUrl} sessionKey={sessionKey} />;
}

function ApplicationsContent({ serverUrl, sessionKey }: { serverUrl: string; sessionKey: string }) {
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
  const [editing, setEditing] = useState<Application | null>(null);
  const [editVin, setEditVin] = useState("");
  const [editError, setEditError] = useState("");
  const [rebuilding, setRebuilding] = useState(false);

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

  function openEditor(application: Application) {
    setEditing(application);
    setEditVin(application.vin);
    setEditError("");
  }

  async function rebuildApplication() {
    if (!editing) return;
    const vin = editVin.toUpperCase().replace(/[^A-Z0-9]/g, "").slice(0, 17);
    if (!/^[A-HJ-NPR-Z0-9]{17}$/.test(vin)) {
      setEditError("VIN должен состоять из 17 символов без I, O и Q");
      return;
    }
    setRebuilding(true);
    setEditError("");
    try {
      const data = await apiFetch<{ application: Application; matched: boolean }>(
        serverUrl,
        sessionKey,
        `/api/client-applications/${editing.id}/rebuild/`,
        { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ vin }) }
      );
      setItems((current) => current.map((item) => (item.id === data.application.id ? data.application : item)));
      setEditing(null);
    } catch (err) {
      setEditError(humanError(err));
    } finally {
      setRebuilding(false);
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
                <span>Статус</span>
                <span />
              </div>
              {items.map((item) => (
                <ApplicationCard
                  key={item.id}
                  application={item}
                  opening={openingId === item.id}
                  onOpen={() => openInspection(item)}
                  onEdit={() => openEditor(item)}
                />
              ))}
            </>
          )}
        </div>
      )}
      {editing && (
        <div className="application-modal" role="dialog" aria-modal="true" aria-labelledby="application-edit-title">
          <div className="application-modal-card">
            <div>
              <h2 id="application-edit-title">Изменить VIN</h2>
              <p>Заявка #{editing.id} · {editing.applicant_name || "Без имени"}</p>
            </div>
            <label className="application-vin-field">
              <span>Новый VIN</span>
              <input
                autoFocus
                value={editVin}
                maxLength={17}
                onChange={(event) => setEditVin(event.target.value.toUpperCase().replace(/[^A-Z0-9]/g, ""))}
                onKeyDown={(event) => {
                  if (event.key === "Enter" && !rebuilding) rebuildApplication();
                  if (event.key === "Escape" && !rebuilding) setEditing(null);
                }}
              />
              <small>{editVin.length}/17 символов</small>
            </label>
            <div className="application-rebuild-note">
              PDF будет создан заново. Система снимет старую привязку, повторит поиск и привяжет заявку при точном совпадении.
            </div>
            {!editing.can_rebuild && (
              <div className="application-modal-warning">Эта заявка создана до введения хранения подписей, поэтому её PDF нельзя пересобрать.</div>
            )}
            {editError && <div className="error">{editError}</div>}
            <div className="application-modal-actions">
              <button className="btn secondary" onClick={() => setEditing(null)} disabled={rebuilding}>Отмена</button>
              <button className="btn" onClick={rebuildApplication} disabled={rebuilding || !editing.can_rebuild}>
                {rebuilding ? "Пересобираем..." : "Пересобрать PDF"}
              </button>
            </div>
          </div>
        </div>
      )}
    </>
  );
}

function ApplicationCard({
  application,
  opening,
  onOpen,
  onEdit,
}: {
  application: Application;
  opening: boolean;
  onOpen: () => void;
  onEdit: () => void;
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
      <div className="inspection-cell">
        <span>Статус</span>
        <strong className={application.inspection_id ? "application-status linked" : "application-status unlinked"}>
          {application.inspection_id ? "Привязана" : "Не привязана"}
        </strong>
      </div>
      <div className="actions">
        <button className="btn secondary" onClick={onEdit}>Изменить</button>
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
