"use client";

import Link from "next/link";
import { useMemo, useState } from "react";
import styles from "./analytics.module.css";

type DayPoint = {
  day: string;
  date: string;
  value: number;
};

const weeks: DayPoint[][] = [
  [
    { day: "Пн", date: "7 сен", value: 126 },
    { day: "Вт", date: "8 сен", value: 184 },
    { day: "Ср", date: "9 сен", value: 158 },
    { day: "Чт", date: "10 сен", value: 247 },
    { day: "Пт", date: "11 сен", value: 196 },
    { day: "Сб", date: "12 сен", value: 112 },
    { day: "Вс", date: "13 сен", value: 86 },
  ],
  [
    { day: "Пн", date: "14 сен", value: 148 },
    { day: "Вт", date: "15 сен", value: 206 },
    { day: "Ср", date: "16 сен", value: 179 },
    { day: "Чт", date: "17 сен", value: 312 },
    { day: "Пт", date: "18 сен", value: 238 },
    { day: "Сб", date: "19 сен", value: 137 },
    { day: "Вс", date: "20 сен", value: 104 },
  ],
];

const weekLabels = ["7–13 сентября", "14–20 сентября"];

function ArrowIcon({ direction = "right" }: { direction?: "left" | "right" }) {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true">
      <path d={direction === "left" ? "m15 18-6-6 6-6" : "m9 18 6-6-6-6"} />
    </svg>
  );
}

function EyeIcon() {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true">
      <path d="M2.5 12s3.4-6 9.5-6 9.5 6 9.5 6-3.4 6-9.5 6-9.5-6-9.5-6Z" />
      <circle cx="12" cy="12" r="2.7" />
    </svg>
  );
}

function TrendIcon() {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true">
      <path d="m4 16 5-5 4 4 7-8" />
      <path d="M15 7h5v5" />
    </svg>
  );
}

function WeeklyChart({ data }: { data: DayPoint[] }) {
  const [activeIndex, setActiveIndex] = useState<number | null>(null);
  const width = 860;
  const height = 330;
  const padding = { top: 58, right: 30, bottom: 58, left: 52 };
  const maxValue = Math.ceil(Math.max(...data.map((item) => item.value)) / 100) * 100;
  const peakIndex = data.findIndex((item) => item.value === Math.max(...data.map((item) => item.value)));
  const plotWidth = width - padding.left - padding.right;
  const plotHeight = height - padding.top - padding.bottom;
  const points = data.map((item, index) => ({
    ...item,
    x: padding.left + (plotWidth / (data.length - 1)) * index,
    y: padding.top + plotHeight - (item.value / maxValue) * plotHeight,
  }));
  const line = points.map((point, index) => `${index === 0 ? "M" : "L"} ${point.x} ${point.y}`).join(" ");
  const area = `${line} L ${points.at(-1)?.x} ${padding.top + plotHeight} L ${points[0].x} ${padding.top + plotHeight} Z`;
  const selected = activeIndex === null ? null : points[activeIndex];

  return (
    <div className={styles.chartWrap}>
      <svg className={styles.chart} viewBox={`0 0 ${width} ${height}`} role="img" aria-labelledby="chart-title chart-description">
        <title id="chart-title">Просмотры по дням недели</title>
        <desc id="chart-description">Линейный график количества просмотров с понедельника по воскресенье</desc>
        <defs>
          <linearGradient id="chart-area" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stopColor="#5878f5" stopOpacity="0.22" />
            <stop offset="100%" stopColor="#5878f5" stopOpacity="0" />
          </linearGradient>
          <filter id="peak-glow" x="-100%" y="-100%" width="300%" height="300%">
            <feGaussianBlur stdDeviation="6" />
          </filter>
        </defs>

        {[0, 1, 2, 3, 4].map((step) => {
          const y = padding.top + (plotHeight / 4) * step;
          const label = Math.round(maxValue - (maxValue / 4) * step);
          return (
            <g key={step}>
              <line className={styles.gridLine} x1={padding.left} x2={width - padding.right} y1={y} y2={y} />
              <text className={styles.axisValue} x={padding.left - 14} y={y + 4} textAnchor="end">{label}</text>
            </g>
          );
        })}

        <path className={styles.area} d={area} />
        <path className={styles.line} d={line} />

        {points.map((point, index) => {
          const isPeak = index === peakIndex;
          const isActive = index === activeIndex;
          return (
            <g
              key={point.date}
              className={styles.pointGroup}
              tabIndex={0}
              role="button"
              aria-label={`${point.day}, ${point.date}: ${point.value} просмотров${isPeak ? ", пик недели" : ""}`}
              onMouseEnter={() => setActiveIndex(index)}
              onMouseLeave={() => setActiveIndex(null)}
              onFocus={() => setActiveIndex(index)}
              onBlur={() => setActiveIndex(null)}
            >
              <rect className={styles.hitArea} x={point.x - 42} y={padding.top - 16} width="84" height={plotHeight + 38} />
              {isPeak ? <circle className={styles.peakGlow} cx={point.x} cy={point.y} r="15" /> : null}
              <circle className={isPeak ? styles.peakPoint : styles.point} cx={point.x} cy={point.y} r={isActive || isPeak ? 6.5 : 4.5} />
              <text className={isPeak ? styles.peakValue : styles.pointValue} x={point.x} y={point.y - 16} textAnchor="middle">
                {point.value}
              </text>
              <text className={styles.dayLabel} x={point.x} y={height - 27} textAnchor="middle">{point.day}</text>
              <text className={styles.dateLabel} x={point.x} y={height - 10} textAnchor="middle">{point.date.replace(" сен", "")}</text>
            </g>
          );
        })}

        {selected ? (
          <g className={styles.tooltip} transform={`translate(${Math.min(Math.max(selected.x - 70, 8), width - 148)} ${Math.max(selected.y - 72, 4)})`}>
            <rect width="140" height="46" rx="10" />
            <text x="12" y="19">{selected.day}, {selected.date}</text>
            <text className={styles.tooltipValue} x="12" y="36">{selected.value} просмотров</text>
          </g>
        ) : null}
      </svg>
    </div>
  );
}

export default function AnalyticsPage() {
  const [weekIndex, setWeekIndex] = useState(1);
  const data = weeks[weekIndex];
  const summary = useMemo(() => {
    const total = data.reduce((sum, day) => sum + day.value, 0);
    const previousTotal = weekIndex > 0 ? weeks[weekIndex - 1].reduce((sum, day) => sum + day.value, 0) : total;
    const change = Math.round(((total - previousTotal) / previousTotal) * 100);
    const peak = data.reduce((best, day) => (day.value > best.value ? day : best));
    return { total, change, peak, average: Math.round(total / data.length) };
  }, [data, weekIndex]);

  return (
    <main className={styles.page}>
      <div className={styles.shell}>
        <header className={styles.header}>
          <div>
            <Link className={styles.backLink} href="/">← Назад к заявкам</Link>
            <p className={styles.eyebrow}>Авто лаборатория</p>
            <h1>Аналитика</h1>
            <p className={styles.subtitle}>Динамика просмотров и активность за неделю</p>
          </div>
          <div className={styles.liveBadge}><span /> Демо-данные интерфейса</div>
        </header>

        <section className={styles.stats} aria-label="Сводка за неделю">
          <article className={styles.statCard}>
            <div className={styles.iconBox}><EyeIcon /></div>
            <div><span>Всего просмотров</span><strong>{summary.total.toLocaleString("ru-RU")}</strong></div>
            <b className={styles.growth}>↑ {summary.change}%</b>
          </article>
          <article className={styles.statCard}>
            <div className={`${styles.iconBox} ${styles.iconBlue}`}><TrendIcon /></div>
            <div><span>В среднем за день</span><strong>{summary.average}</strong></div>
            <small>просмотров</small>
          </article>
          <article className={`${styles.statCard} ${styles.peakCard}`}>
            <div className={`${styles.iconBox} ${styles.iconOrange}`}>★</div>
            <div><span>Пиковый день</span><strong>{summary.peak.day}, {summary.peak.date}</strong></div>
            <b className={styles.peakCount}>{summary.peak.value}</b>
          </article>
        </section>

        <section className={styles.chartCard}>
          <div className={styles.chartHeader}>
            <div>
              <div className={styles.titleLine}>
                <h2>Просмотры по дням</h2>
                <span className={styles.legend}><i /> Просмотры</span>
              </div>
              <p>Количество осмотров страницы за каждый день недели</p>
            </div>
            <div className={styles.weekSwitch} aria-label="Выбор недели">
              <button onClick={() => setWeekIndex(0)} disabled={weekIndex === 0} aria-label="Предыдущая неделя"><ArrowIcon direction="left" /></button>
              <span><small>Неделя</small>{weekLabels[weekIndex]}</span>
              <button onClick={() => setWeekIndex(1)} disabled={weekIndex === 1} aria-label="Следующая неделя"><ArrowIcon /></button>
            </div>
          </div>

          <div className={styles.peakNotice}>
            <span>★</span>
            <p><strong>Пик недели — {summary.peak.day}, {summary.peak.date}</strong><small>{summary.peak.value} просмотров — лучший результат за выбранный период</small></p>
          </div>

          <WeeklyChart data={data} />
          <div className={styles.chartFooter}>
            <span><i className={styles.dotBlue} /> Обычный день</span>
            <span><i className={styles.dotOrange} /> Пиковый день</span>
            <small>Наведите на точку, чтобы увидеть детали</small>
          </div>
        </section>
      </div>
    </main>
  );
}
