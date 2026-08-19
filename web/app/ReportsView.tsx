"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { ExternalLink } from "lucide-react";
import {
  Inspection,
  REPORT_TYPE_OPTIONS,
  ReportSummary,
  apiFetch,
  categoryClassName,
  formatDate,
  formatDateOnly,
  formatMoney,
  humanError,
  isoDate,
  operationLabel,
  operatorName,
  useSession,
  vehicleCategories,
} from "./lib";
import { InspectionDetail } from "./InspectionDetail";
import { Spinner } from "./Spinner";

export function ReportsView() {
  const { serverUrl, sessionKey, canReports } = useSession();
  const router = useRouter();

  useEffect(() => {
    if (!canReports) router.replace("/inspections");
  }, [canReports, router]);

  if (!canReports) return null;

  return <ReportsContent serverUrl={serverUrl} sessionKey={sessionKey} />;
}

function ReportsContent({ serverUrl, sessionKey }: { serverUrl: string; sessionKey: string }) {
  const today = isoDate(new Date());
  const [dateFrom, setDateFrom] = useState(today);
  const [dateTo, setDateTo] = useState(today);
  const [summary, setSummary] = useState<ReportSummary | null>(null);
  const [inspections, setInspections] = useState<Inspection[]>([]);
  const [selected, setSelected] = useState<Inspection | null>(null);
  const [typeFilter, setTypeFilter] = useState("all");
  const [sbgtsCategoryFilter, setSbgtsCategoryFilter] = useState("all");
  const [vinQuery, setVinQuery] = useState("");
  const [vinResults, setVinResults] = useState<Inspection[]>([]);
  const [vinSearchActive, setVinSearchActive] = useState(false);
  const [vinSearching, setVinSearching] = useState(false);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");

  async function load() {
    setLoading(true);
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
    } finally {
      setLoading(false);
    }
  }

  async function searchByVin() {
    const value = vinQuery.trim().toUpperCase();
    if (!value) {
      setVinSearchActive(false);
      setVinResults([]);
      return;
    }

    setError("");
    setVinSearching(true);
    try {
      const params = new URLSearchParams({ vin: value });
      const data = await apiFetch<{ inspections: Inspection[] }>(
        serverUrl,
        sessionKey,
        `/api/inspections/?${params}`
      );
      setVinResults(data.inspections);
      setVinSearchActive(true);
    } catch (err) {
      setError(humanError(err));
    } finally {
      setVinSearching(false);
    }
  }

  function resetVinSearch() {
    setVinQuery("");
    setVinResults([]);
    setVinSearchActive(false);
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
  const filteredByType = typeFilter === "all"
    ? inspections
    : inspections.filter((item) => (item.operation_type ?? "") === typeFilter);
  const filteredInspections =
    typeFilter === "sbgts" && sbgtsCategoryFilter !== "all"
      ? filteredByType.filter((item) => item.vehicle_category === sbgtsCategoryFilter)
      : filteredByType;
  const visibleInspections = vinSearchActive ? vinResults : filteredInspections;
  const typeLabel = REPORT_TYPE_OPTIONS.find((option) => option.value === typeFilter)?.label ?? "Все";
  const filterLabel =
    typeFilter === "sbgts" && sbgtsCategoryFilter !== "all"
      ? `${typeLabel} / ${sbgtsCategoryFilter}`
      : typeLabel;

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
          <div className="vin-global-search">
            <input
              value={vinQuery}
              onChange={(e) => setVinQuery(e.target.value.toUpperCase())}
              onKeyDown={(event) => {
                if (event.key === "Enter") searchByVin();
              }}
              placeholder="Поиск VIN по всей базе"
            />
            <button className="btn secondary" onClick={searchByVin} disabled={vinSearching}>
              {vinSearching ? "Ищу..." : "VIN"}
            </button>
            {vinSearchActive && (
              <button className="btn ghost" onClick={resetVinSearch}>
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
          <Spinner label="Загрузка отчета..." />
        </div>
      ) : summary && (
        <>
          <div className="report-totals">
            <div className="primary-total">
              <span>{isTodayPeriod ? "Сегодня" : "За выбранный период"}</span>
              <strong>{totals?.period ?? 0}</strong>
              <small>{periodLabel}</small>
            </div>
            <div className="report-type-filter">
              <span>Тип осмотра</span>
              <div className="report-radio-group">
                {REPORT_TYPE_OPTIONS.map((option) => (
                  <label className="report-radio" key={option.value}>
                    <input
                      type="radio"
                      name="report-type-filter"
                      value={option.value}
                      checked={typeFilter === option.value}
                      onChange={() => {
                        setTypeFilter(option.value);
                        if (option.value !== "sbgts") {
                          setSbgtsCategoryFilter("all");
                        }
                      }}
                    />
                    <span>{option.label}</span>
                  </label>
                ))}
              </div>
              {typeFilter === "sbgts" && (
                <div className="report-radio-group category-filter-group">
                  <label className="report-radio">
                    <input
                      type="radio"
                      name="report-sbgts-category-filter"
                      value="all"
                      checked={sbgtsCategoryFilter === "all"}
                      onChange={() => setSbgtsCategoryFilter("all")}
                    />
                    <span>Все категории</span>
                  </label>
                  {vehicleCategories.map((category) => (
                    <label className="report-radio" key={category}>
                      <input
                        type="radio"
                        name="report-sbgts-category-filter"
                        value={category}
                        checked={sbgtsCategoryFilter === category}
                        onChange={() => setSbgtsCategoryFilter(category)}
                      />
                      <span>{category}</span>
                    </label>
                  ))}
                </div>
              )}
            </div>
            <div className="primary-total report-filter-sum">
              <span>{vinSearchActive ? "Найдено по VIN" : "Итого"}</span>
              <strong>{visibleInspections.length}</strong>
              <small>{vinSearchActive ? "Вся база" : filterLabel}</small>
            </div>
          </div>
          <div className="inspection-list report-inspection-list">
            {visibleInspections.length === 0 ? (
              <div className="card empty">
                {vinSearchActive ? "По VIN ничего не найдено" : "Осмотры за период не найдены"}
              </div>
            ) : (
              <>
                <div className="inspection-header" aria-hidden="true">
                  <span>Марка / модель</span>
                  <span>Тип операции</span>
                  <span>VIN</span>
                  <span>Дата</span>
                  <span>Оператор</span>
                  <span>Сумма</span>
                  <span />
                </div>
                {visibleInspections.map((inspection) => (
                  <article className="inspection-row" key={inspection.id}>
                    <div className="inspection-cell">
                      <span>Марка / модель</span>
                      <strong>{inspection.brand || "-"}</strong>
                    </div>
                    <div className="inspection-cell">
                      <span>Тип операции</span>
                      <strong className="operation-with-category">
                        <b>{operationLabel(inspection)}</b>
                        {inspection.operation_type === "sbgts" && (
                          <b className={categoryClassName(inspection.vehicle_category)}>
                            {inspection.vehicle_category || "-"}
                          </b>
                        )}
                      </strong>
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
                      <strong>{operatorName(inspection.created_by)}</strong>
                    </div>
                    <div className="inspection-cell">
                      <span>Сумма</span>
                      <strong>{formatMoney(inspection.amount)}</strong>
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
