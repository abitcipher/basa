import { useCallback, useEffect, useRef, useState } from "react";
import * as echarts from "echarts/core";
import { BarChart, LineChart } from "echarts/charts";
import { GridComponent, LegendComponent, TooltipComponent } from "echarts/components";
import { CanvasRenderer } from "echarts/renderers";
import type { EChartsCoreOption } from "echarts/core";
import { buildCSRFHeaders, lessorStats } from "./ash_rpc";
import { brand, useDark } from "./theme";
import type { Live } from "./live";

echarts.use([BarChart, LineChart, GridComponent, LegendComponent, TooltipComponent, CanvasRenderer]);

type Props = {
  locale: string;
  from: string;
  to: string;
  labels: {
    occupancy: string;
    perWeek: string;
    earnings: string;
    bookings: string;
    error: string;
    retry: string;
    empty: string;
  };
  live: Live<"LessorStats">;
};

type Stats = {
  currency: string;
  offers: { lotId: string; title: string; occupancy: number; bookedHours: number; openHours: number }[];
  weeks: { week: string; bookings: number; earnings: string }[];
};

export function LessorStats({ locale, from, to, labels, live }: Props) {
  const [stats, setStats] = useState<Stats | null>(null);
  const [failed, setFailed] = useState(false);
  const dark = useDark();

  const load = useCallback(async () => {
    const result = await lessorStats({
      input: { from, to },
      fields: [
        "currency",
        { offers: ["lotId", "title", "occupancy", "bookedHours", "openHours"] },
        { weeks: ["week", "bookings", "earnings"] },
      ],
      headers: buildCSRFHeaders(),
    });
    if (result.success) {
      const loaded: Stats = result.data;
      setStats(loaded);
      setFailed(false);
    } else {
      setFailed(true);
    }
  }, [from, to]);

  useEffect(() => {
    load();
    return live.on("bookings.changed", () => load());
  }, [load, live]);

  if (failed) {
    return (
      <div className="rounded-xl border border-rose-200 p-4 text-sm dark:border-rose-900">
        {labels.error}{" "}
        <button type="button" className="underline" onClick={() => load()}>
          {labels.retry}
        </button>
      </div>
    );
  }

  if (!stats) return <div className="h-80 animate-pulse rounded-xl bg-zinc-100 dark:bg-zinc-800" />;
  if (stats.offers.length === 0) return <p className="text-sm opacity-70">{labels.empty}</p>;

  const text = dark ? "#e4e4e7" : "#27272a";
  const grid = dark ? "#3f3f46" : "#e4e4e7";
  const money = new Intl.NumberFormat(locale, { style: "currency", currency: stats.currency === "USDT" || stats.currency === "GRAM" ? "USD" : stats.currency, maximumFractionDigits: 0 });
  const week = new Intl.DateTimeFormat(locale, { day: "numeric", month: "short", timeZone: "UTC" });
  const seen = new Map<string, number>();
  const titles = stats.offers.map((o) => {
    const n = (seen.get(o.title) ?? 0) + 1;
    seen.set(o.title, n);
    return n > 1 ? `${o.title} (${n})` : o.title;
  });

  const occupancy: EChartsCoreOption = {
    textStyle: { color: text },
    grid: { left: 8, right: 40, top: 8, bottom: 8, containLabel: true },
    tooltip: {
      trigger: "item",
      formatter: (p: any) => {
        const o = stats.offers[p.dataIndex];
        return `${titles[p.dataIndex]}<br/>${o.occupancy}% · ${o.bookedHours} / ${o.openHours} h`;
      },
    },
    xAxis: { type: "value", max: 100, axisLabel: { formatter: "{value}%", color: text }, splitLine: { lineStyle: { color: grid } } },
    yAxis: { type: "category", data: titles, inverse: true, axisLabel: { color: text, width: 160, overflow: "truncate" } },
    series: [
      {
        type: "bar",
        data: stats.offers.map((o) => o.occupancy),
        itemStyle: { color: brand.green, borderRadius: [0, 4, 4, 0] },
        label: { show: true, position: "right", formatter: "{c}%", color: text },
        barMaxWidth: 28,
      },
    ],
  };

  const weekly: EChartsCoreOption = {
    textStyle: { color: text },
    grid: { left: 8, right: 8, top: 36, bottom: 8, containLabel: true },
    legend: { top: 0, data: [labels.earnings, labels.bookings], textStyle: { color: text } },
    tooltip: { trigger: "axis" },
    xAxis: { type: "category", data: stats.weeks.map((w) => week.format(new Date(`${w.week}T00:00:00Z`))), axisLabel: { color: text } },
    yAxis: [
      { type: "value", axisLabel: { formatter: (v: number) => money.format(v), color: text }, splitLine: { lineStyle: { color: grid } } },
      { type: "value", minInterval: 1, axisLabel: { color: text }, splitLine: { show: false } },
    ],
    series: [
      {
        name: labels.earnings,
        type: "bar",
        data: stats.weeks.map((w) => Number(w.earnings)),
        itemStyle: { color: dark ? brand.cyan : brand.cyanDeep, borderRadius: [4, 4, 0, 0] },
        tooltip: { valueFormatter: (v: any) => money.format(Number(v)) },
      },
      {
        name: labels.bookings,
        type: "line",
        yAxisIndex: 1,
        data: stats.weeks.map((w) => w.bookings),
        itemStyle: { color: brand.orange },
      },
    ],
  };

  return (
    <div className="grid items-start gap-4 lg:grid-cols-2">
      <section className="rounded-xl border border-zinc-200 p-3 dark:border-zinc-800">
        <h2 className="mb-2 font-semibold">{labels.occupancy}</h2>
        <Chart option={occupancy} height={Math.max(160, stats.offers.length * 44 + 40)} />
      </section>
      <section className="rounded-xl border border-zinc-200 p-3 dark:border-zinc-800">
        <h2 className="mb-2 font-semibold">{labels.perWeek}</h2>
        <Chart option={weekly} height={280} />
      </section>
    </div>
  );
}

function Chart({ option, height }: { option: EChartsCoreOption; height: number }) {
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!ref.current) return;
    const chart = echarts.init(ref.current, undefined, { renderer: "canvas" });
    const resize = new ResizeObserver(() => chart.resize());
    resize.observe(ref.current);
    return () => {
      resize.disconnect();
      chart.dispose();
    };
  }, []);

  useEffect(() => {
    if (ref.current) echarts.getInstanceByDom(ref.current)?.setOption(option, true);
  }, [option]);

  return <div ref={ref} style={{ height }} />;
}
