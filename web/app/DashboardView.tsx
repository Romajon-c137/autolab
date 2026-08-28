"use client";

import { ReactNode, useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { Building2, CalendarRange, PieChart, Sparkles, Users } from "lucide-react";
import {
  CHART_FALLBACK_COLOR,
  OPERATION_COLORS,
  ReportSummary,
  apiFetch,
  formatDateOnly,
  formatMoney,
  humanError,
  isoDate,
  useSession,
} from "./lib";
import { Spinner } from "./Spinner";
import { MilestoneCelebration } from "./MilestoneCelebration";

export function DashboardView() {
  const { serverUrl, sessionKey, canReportTotals, canViewAmounts } = useSession();
  const router = useRouter();

  useEffect(() => {
    if (!canReportTotals) router.replace("/inspections");
  }, [canReportTotals, router]);

  if (!canReportTotals) return null;

  return (
    <DashboardContent
      serverUrl={serverUrl}
      sessionKey={sessionKey}
      canViewAmounts={canViewAmounts}
    />
  );
}

function DashboardContent({
  serverUrl,
  sessionKey,
  canViewAmounts,
}: {
  serverUrl: string;
  sessionKey: string;
  canViewAmounts: boolean;
}) {
  const today = isoDate(new Date());
  const monthStart = `${today.slice(0, 8)}01`;
  const [dateFrom, setDateFrom] = useState(monthStart);
  const [dateTo, setDateTo] = useState(today);
  const [summary, setSummary] = useState<ReportSummary | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [milestoneClicks, setMilestoneClicks] = useState(0);
  const [milestonePreview, setMilestonePreview] = useState(false);

  async function load() {
    setLoading(true);
    setError("");
    try {
      const params = new URLSearchParams({ date_from: dateFrom, date_to: dateTo });
      const data = await apiFetch<ReportSummary>(
        serverUrl,
        sessionKey,
        `/api/reports/summary/?${params}`
      );
      setSummary(data);
    } catch (err) {
      setError(humanError(err));
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const periodLabel =
    dateFrom === dateTo
      ? formatDateOnly(dateFrom)
      : `${formatDateOnly(dateFrom)} — ${formatDateOnly(dateTo)}`;

  const daySeries = useMemo(
    () => (summary ? buildDaySeries(dateFrom, dateTo, summary.by_day) : []),
    [summary, dateFrom, dateTo]
  );

  const donutSlices = useMemo(() => {
    if (!summary) return [];
    return summary.by_operation
      .filter((row) => row.count > 0)
      .map((row) => ({
        key: row.operation_type || "unknown",
        label: row.label,
        value: row.count,
        amount: row.amount,
        color: OPERATION_COLORS[row.operation_type] ?? CHART_FALLBACK_COLOR,
      }));
  }, [summary]);
  const donutTotal = donutSlices.reduce((sum, slice) => sum + slice.value, 0);

  const branchRows = summary?.branches ?? [];
  const showBranchCard = branchRows.length > 1;

  function confirmMilestone() {
    const nextClicks = milestoneClicks + 1;
    if (nextClicks < 10) {
      setMilestoneClicks(nextClicks);
      return;
    }

    setMilestonePreview(false);
    setMilestoneClicks(0);
  }

  return (
    <>
      {milestonePreview && (
        <MilestoneCelebration
          clicks={milestoneClicks}
          total={summary?.totals.all_time ?? 1000}
          onConfirm={confirmMilestone}
        />
      )}
      <button
        className="milestone-preview-trigger"
        type="button"
        onClick={() => {
          setMilestoneClicks(0);
          setMilestonePreview(true);
        }}
        title="Предпросмотр праздника"
        aria-label="Предпросмотр поздравления"
      >
        <Sparkles aria-hidden="true" />
      </button>
      <div className="topbar">
        <div className="page-title">
          <h1>Аналитика</h1>
          <p>Осмотры, выручка и распределение по типам за период</p>
        </div>
      </div>

      <div className="filters dash-filters">
        <input type="date" value={dateFrom} onChange={(e) => setDateFrom(e.target.value)} />
        <input type="date" value={dateTo} onChange={(e) => setDateTo(e.target.value)} />
        <button className="btn" onClick={load}>
          Найти
        </button>
      </div>

      {error && <div className="error">{error}</div>}

      {loading ? (
        <div className="card empty">
          <Spinner label="Загрузка аналитики..." />
        </div>
      ) : summary ? (
        <>
          <div className="dash-kpis">
            <KpiTile
              label="Всего осмотров"
              value={`${summary.totals.all_time} / 1000`}
              sub={
                summary.totals.all_time >= 1000
                  ? "Отметка 1000 достигнута"
                  : `До отметки осталось: ${1000 - summary.totals.all_time}`
              }
              accent
            />
            <KpiTile
              label="Сегодня"
              value={summary.totals.today}
              money={canViewAmounts ? summary.totals.today_amount : null}
            />
            <KpiTile
              label="За 7 дней"
              value={summary.totals.week}
              money={canViewAmounts ? summary.totals.week_amount : null}
            />
            <KpiTile
              label="С начала месяца"
              value={summary.totals.month}
              money={canViewAmounts ? summary.totals.month_amount : null}
            />
            <KpiTile
              label="За период"
              value={summary.totals.period}
              money={canViewAmounts ? summary.totals.period_amount : null}
              sub={periodLabel}
            />
          </div>

          <div className="dash-grid">
            <DashCard icon={<PieChart aria-hidden="true" />} title="Осмотры по типу операции" hint={periodLabel}>
              {donutTotal === 0 ? (
                <div className="dash-empty">Нет осмотров за период</div>
              ) : (
                <div className="donut-block">
                  <DonutChart slices={donutSlices} />
                  <ul className="donut-legend">
                    {donutSlices.map((slice) => {
                      const percent = Math.round((slice.value / donutTotal) * 100);
                      return (
                        <li key={slice.key}>
                          <span className="legend-dot" style={{ background: slice.color }} />
                          <span className="legend-label">{slice.label}</span>
                          <span className="legend-value">
                            {slice.value} · {percent}%
                            {canViewAmounts && slice.amount
                              ? ` · ${formatMoney(slice.amount)} сом`
                              : ""}
                          </span>
                        </li>
                      );
                    })}
                  </ul>
                </div>
              )}
            </DashCard>

            {showBranchCard ? (
              <DashCard icon={<Building2 aria-hidden="true" />} title="По филиалам" hint={periodLabel}>
                <BarList
                  rows={branchRows.map((b) => ({
                    label: b.name,
                    count: b.inspections_count,
                    amount: canViewAmounts ? b.inspections_amount : null,
                  }))}
                />
              </DashCard>
            ) : (
              <DashCard icon={<PieChart aria-hidden="true" />} title="Категории ТС" hint={periodLabel}>
                {summary.by_category.length === 0 ? (
                  <div className="dash-empty">Нет данных за период</div>
                ) : (
                  <BarList
                    rows={summary.by_category.map((c) => ({
                      label: c.category,
                      count: c.count,
                      amount: canViewAmounts ? c.amount : null,
                    }))}
                  />
                )}
              </DashCard>
            )}

            <DashCard
              icon={<CalendarRange aria-hidden="true" />}
              title="Осмотры по дням"
              hint={periodLabel}
              wide
            >
              {daySeries.length === 0 ? (
                <div className="dash-empty">Нет осмотров за период</div>
              ) : (
                <DayTrend days={daySeries} />
              )}
            </DashCard>

            {summary.by_operator.length > 0 && (
              <DashCard icon={<Users aria-hidden="true" />} title="По операторам" hint={periodLabel} wide>
                <BarList
                  rows={summary.by_operator.map((o) => ({
                    label: o.name,
                    count: o.count,
                    amount: canViewAmounts ? o.amount : null,
                  }))}
                />
              </DashCard>
            )}
          </div>
        </>
      ) : null}
    </>
  );
}

function KpiTile({
  label,
  value,
  money,
  sub,
  accent,
}: {
  label: string;
  value: number | string;
  money?: number | null;
  sub?: string;
  accent?: boolean;
}) {
  return (
    <div className={accent ? "kpi-tile accent" : "kpi-tile"}>
      <span className="kpi-label">{label}</span>
      <strong className="kpi-value">{value}</strong>
      {money ? <small className="kpi-money">{formatMoney(money)} сом</small> : null}
      {sub ? <small className="kpi-sub">{sub}</small> : null}
    </div>
  );
}

function DashCard({
  icon,
  title,
  hint,
  wide,
  children,
}: {
  icon: ReactNode;
  title: string;
  hint?: string;
  wide?: boolean;
  children: ReactNode;
}) {
  return (
    <section className={wide ? "dash-card wide" : "dash-card"}>
      <header className="dash-card-head">
        <span className="dash-card-icon">{icon}</span>
        <h3>{title}</h3>
        {hint ? <span className="dash-card-hint">{hint}</span> : null}
      </header>
      <div className="dash-card-body">{children}</div>
    </section>
  );
}

function DonutChart({
  slices,
}: {
  slices: Array<{ key: string; label: string; value: number; color: string }>;
}) {
  const size = 190;
  const thickness = 30;
  const radius = (size - thickness) / 2;
  const cx = size / 2;
  const cy = size / 2;
  const circumference = 2 * Math.PI * radius;
  const total = slices.reduce((sum, slice) => sum + slice.value, 0);
  const gap = slices.length > 1 ? 2.5 : 0;

  let offset = 0;
  const arcs = slices.map((slice) => {
    const fraction = slice.value / total;
    const length = Math.max(fraction * circumference - gap, 0.001);
    const arc = (
      <circle
        key={slice.key}
        cx={cx}
        cy={cy}
        r={radius}
        fill="none"
        stroke={slice.color}
        strokeWidth={thickness}
        strokeDasharray={`${length} ${circumference - length}`}
        strokeDashoffset={-offset}
      />
    );
    offset += fraction * circumference;
    return arc;
  });

  return (
    <svg className="donut" viewBox={`0 0 ${size} ${size}`} role="img" aria-label="Круговая диаграмма">
      <g transform={`rotate(-90 ${cx} ${cy})`}>
        <circle cx={cx} cy={cy} r={radius} fill="none" stroke="var(--surface-2)" strokeWidth={thickness} />
        {arcs}
      </g>
      <text x={cx} y={cy - 2} textAnchor="middle" className="donut-total">
        {total}
      </text>
      <text x={cx} y={cy + 16} textAnchor="middle" className="donut-total-label">
        осмотров
      </text>
    </svg>
  );
}

function BarList({
  rows,
}: {
  rows: Array<{ label: string; count: number; amount: number | null }>;
}) {
  const max = Math.max(1, ...rows.map((row) => row.count));
  return (
    <div className="bar-list">
      {rows.map((row, index) => (
        <div className="bar-row" key={`${row.label}-${index}`}>
          <span className="bar-label" title={row.label}>{row.label}</span>
          <span className="bar-track">
            <i style={{ width: `${Math.max((row.count / max) * 100, 3)}%` }} />
          </span>
          <span className="bar-value">
            {row.count}
            {row.amount ? ` · ${formatMoney(row.amount)}` : ""}
          </span>
        </div>
      ))}
    </div>
  );
}

function DayTrend({ days }: { days: Array<{ date: string; count: number }> }) {
  const max = Math.max(1, ...days.map((day) => day.count));
  return (
    <div className="day-trend">
      {days.map((day) => (
        <div className="day-bar" key={day.date} title={`${formatDateOnly(day.date)}: ${day.count}`}>
          <span className="day-bar-fill" style={{ height: `${(day.count / max) * 100}%` }} />
          <span className="day-bar-label">{Number(day.date.slice(8, 10))}</span>
        </div>
      ))}
    </div>
  );
}

function buildDaySeries(
  from: string,
  to: string,
  buckets: Array<{ date: string; count: number }>
): Array<{ date: string; count: number }> {
  const known = new Map(buckets.map((bucket) => [bucket.date, bucket.count]));
  const span = daySpan(from, to);
  if (span < 1 || span > 92) {
    return buckets.map((bucket) => ({ date: bucket.date, count: bucket.count }));
  }
  const series: Array<{ date: string; count: number }> = [];
  for (let index = 0; index < span; index += 1) {
    const date = addDays(from, index);
    series.push({ date, count: known.get(date) ?? 0 });
  }
  return series;
}

function daySpan(from: string, to: string) {
  const start = Date.parse(`${from}T00:00:00Z`);
  const end = Date.parse(`${to}T00:00:00Z`);
  if (Number.isNaN(start) || Number.isNaN(end)) return 0;
  return Math.round((end - start) / 86_400_000) + 1;
}

function addDays(iso: string, days: number) {
  const [year, month, day] = iso.split("-").map(Number);
  return new Date(Date.UTC(year, month - 1, day + days)).toISOString().slice(0, 10);
}
