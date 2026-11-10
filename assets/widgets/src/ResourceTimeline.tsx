import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { buildCSRFHeaders, lessorTimeline } from "./ash_rpc";
import { addDays, isoDate, wallClock } from "./time";
import { brand } from "./theme";
import type { Live } from "./live";
import { loadView, saveView } from "./view_state";

type View = "day" | "week" | "month";
type Status = "pending" | "confirmed" | "completed";

type Props = {
  locale: string;
  timezone: string;
  labels: {
    resource: string;
    room: string;
    item: string;
    attendant: string;
    rooms: string;
    items: string;
    people: string;
    day: string;
    week: string;
    month: string;
    today: string;
    previous: string;
    next: string;
    now: string;
    legend: string;
    pending: string;
    confirmed: string;
    completed: string;
    empty: string;
    error: string;
    retry: string;
  };
  live: Live<"ResourceTimeline">;
};

type Booking = { bookingId: string; startsAt: string; endsAt: string; status: string; lotTitle: string; lessee: string | null };
type Resource = { id: string; type: "room" | "item" | "attendant"; title: string; bookings: Booking[] };

const colors: Record<Status, { bg: string; fg: string }> = {
  pending: { bg: brand.yellow, fg: "#1a1a1a" },
  confirmed: { bg: brand.cyanDeep, fg: "#ffffff" },
  completed: { bg: brand.green, fg: "#0a0a0a" },
};

const HOUR = 3_600_000;
const ROW = 44;

function startOfDay(d: Date): Date {
  return new Date(d.getFullYear(), d.getMonth(), d.getDate());
}

function period(view: View, at: Date): { start: Date; end: Date } {
  const day = startOfDay(at);
  if (view === "day") return { start: day, end: addDays(day, 1) };
  if (view === "week") {
    const start = addDays(day, -((day.getDay() + 6) % 7));
    return { start, end: addDays(start, 7) };
  }
  const start = new Date(day.getFullYear(), day.getMonth(), 1);
  return { start, end: new Date(day.getFullYear(), day.getMonth() + 1, 1) };
}

function shift(view: View, at: Date, by: number): Date {
  if (view === "day") return addDays(at, by);
  if (view === "week") return addDays(at, 7 * by);
  return new Date(at.getFullYear(), at.getMonth() + by, 1);
}

function columns(view: View, start: Date, end: Date): Date[] {
  const out: Date[] = [];
  if (view === "day") {
    for (let h = 0; h < 24; h++) out.push(new Date(start.getTime() + h * HOUR));
  } else {
    for (let d = start; d < end; d = addDays(d, 1)) out.push(d);
  }
  return out;
}

const minColumn: Record<View, number> = { day: 30, week: 96, month: 24 };

const weekend = (d: Date) => d.getDay() === 0 || d.getDay() === 6;

export function ResourceTimeline({ locale, timezone, labels, live }: Props) {
  const saved = useMemo(() => loadView<{ view: View; at: string }>("resource-timeline"), []);
  const [view, setView] = useState<View>(() => (saved && saved.view in minColumn ? saved.view : "week"));
  const [at, setAt] = useState(() => {
    const d = saved ? new Date(saved.at) : new Date();
    return Number.isNaN(d.getTime()) ? new Date() : d;
  });
  useEffect(() => saveView("resource-timeline", { view, at: at.toISOString() }), [view, at]);
  const [resources, setResources] = useState<Resource[] | null>(null);
  const [failed, setFailed] = useState(false);
  const [now, setNow] = useState(() => new Date());
  const area = useRef<HTMLDivElement>(null);
  const [width, setWidth] = useState(0);

  const { start, end } = useMemo(() => period(view, at), [view, at]);
  const cols = useMemo(() => columns(view, start, end), [view, start, end]);

  const load = useCallback(async () => {
    const result = await lessorTimeline({
      input: { from: isoDate(start), to: isoDate(end) },
      fields: ["id", "type", "title", { bookings: ["bookingId", "startsAt", "endsAt", "status", "lotTitle", "lessee"] }],
      headers: buildCSRFHeaders(),
    });
    if (result.success) {
      setResources(result.data as Resource[]);
      setFailed(false);
    } else {
      setFailed(true);
    }
  }, [start, end]);

  useEffect(() => {
    load();
    return live.on("bookings.changed", () => load());
  }, [load, live]);

  useEffect(() => {
    const timer = window.setInterval(() => setNow(new Date()), 60_000);
    return () => window.clearInterval(timer);
  }, []);

  useEffect(() => {
    if (!area.current) return;
    const observer = new ResizeObserver(([entry]) => setWidth(entry.contentRect.width));
    observer.observe(area.current);
    return () => observer.disconnect();
  }, [resources]);

  const fmt = useMemo(
    () => ({
      hour: new Intl.DateTimeFormat(locale, { hour: "2-digit", minute: "2-digit" }),
      hourOnly: new Intl.DateTimeFormat(locale, { hour: "2-digit" }),
      weekday: new Intl.DateTimeFormat(locale, { weekday: "short" }),
      dayMonth: new Intl.DateTimeFormat(locale, { day: "numeric", month: "short" }),
      long: new Intl.DateTimeFormat(locale, { weekday: "long", day: "numeric", month: "long", year: "numeric" }),
      monthYear: new Intl.DateTimeFormat(locale, { month: "long", year: "numeric" }),
      full: new Intl.DateTimeFormat(locale, { weekday: "short", day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" }),
    }),
    [locale],
  );

  const title =
    view === "day"
      ? fmt.long.format(start)
      : view === "week"
        ? `${fmt.dayMonth.format(start)} – ${fmt.dayMonth.format(addDays(end, -1))} ${end.getFullYear()}`
        : fmt.monthYear.format(start);

  const groups = useMemo(() => {
    const by = (type: Resource["type"]) => (resources ?? []).filter((r) => r.type === type);
    return [
      { key: "room", label: labels.rooms, rows: by("room") },
      { key: "item", label: labels.items, rows: by("item") },
      { key: "attendant", label: labels.people, rows: by("attendant") },
    ].filter((g) => g.rows.length > 0);
  }, [resources, labels]);

  const span = end.getTime() - start.getTime();
  const nameWidth = width < 640 ? 128 : 220;
  const chartWidth = Math.max(width - nameWidth, cols.length * minColumn[view]);
  const x = (d: Date) => ((d.getTime() - start.getTime()) / span) * chartWidth;
  const nowLocal = wallClock(now.toISOString(), timezone);
  const todayLocal = startOfDay(nowLocal);

  const nowX = nowLocal >= start && nowLocal < end ? x(nowLocal) : null;
  useEffect(() => {
    const el = area.current;
    if (!el || nowX === null || el.scrollWidth <= el.clientWidth) return;
    el.scrollLeft = Math.max(0, nowX - (el.clientWidth - nameWidth) / 3);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [view, start.getTime(), width > 0, resources !== null]);

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

  const toolbar = (
    <div className="mb-3 flex flex-wrap items-center gap-2">
      <button type="button" className="basa-round-btn flex size-8 items-center justify-center rounded-full" aria-label={labels.previous} title={labels.previous} onClick={() => setAt(shift(view, at, -1))}>
        <span className="hero-chevron-left size-4" />
      </button>
      <button type="button" className="rounded-full border px-3 py-1 text-sm" style={{ borderColor: "var(--ui-nav, currentColor)", color: "var(--ui-nav, inherit)" }} onClick={() => setAt(new Date())}>
        {labels.today}
      </button>
      <button type="button" className="basa-round-btn flex size-8 items-center justify-center rounded-full" aria-label={labels.next} title={labels.next} onClick={() => setAt(shift(view, at, 1))}>
        <span className="hero-chevron-right size-4" />
      </button>
      <h2 id="timeline-period" className="ml-1 font-semibold first-letter:uppercase">{title}</h2>

      <div className="ml-auto flex items-center gap-2">
        <div role="group" className="flex overflow-hidden rounded-full border" style={{ borderColor: "var(--ui-nav, currentColor)" }}>
          {(["day", "week", "month"] as View[]).map((v) => (
            <button
              key={v}
              type="button"
              aria-pressed={view === v}
              className="px-3 py-1 text-sm"
              style={view === v ? { background: "var(--ui-action)", color: "var(--ui-action-on)" } : { color: "var(--ui-nav, inherit)" }}
              onClick={() => setView(v)}
            >
              {labels[v]}
            </button>
          ))}
        </div>
        <Legend labels={labels} />
      </div>
    </div>
  );

  if (resources === null) {
    return (
      <div>
        {toolbar}
        <div className="h-48 animate-pulse rounded-xl bg-zinc-100 dark:bg-zinc-800" />
      </div>
    );
  }

  if (groups.length === 0) {
    return (
      <div>
        {toolbar}
        <p className="text-sm opacity-70">{labels.empty}</p>
      </div>
    );
  }

  return (
    <div>
      {toolbar}
      <div ref={area} className="overflow-x-auto rounded-xl border border-zinc-200 dark:border-zinc-800 dark:[color-scheme:dark]">
        <div style={{ width: nameWidth + chartWidth }} className="relative text-sm">
          {}
          <div className="sticky top-0 z-10 flex border-b border-zinc-200 bg-white dark:border-zinc-800 dark:bg-zinc-950">
            <div style={{ width: nameWidth }} className="sticky left-0 z-20 shrink-0 bg-white px-3 py-2 text-xs font-medium text-zinc-500 dark:bg-zinc-950 dark:text-zinc-400">
              {labels.resource}
            </div>
            <div className="relative h-10" style={{ width: chartWidth }}>
              {cols.map((c) => {
                const today = view !== "day" && c.getTime() === todayLocal.getTime();
                return (
                  <div
                    key={c.getTime()}
                    className={`absolute top-0 flex h-full flex-col items-center justify-center border-l border-zinc-100 text-xs dark:border-zinc-800 ${today ? "font-bold" : "opacity-70"}`}
                    style={{ left: x(c), width: chartWidth / cols.length, color: today ? "var(--ui-action-text)" : undefined }}
                  >
                    {view === "day" ? (
                      <span>{fmt.hourOnly.format(c)}</span>
                    ) : view === "week" ? (
                      <>
                        <span className="first-letter:uppercase">{fmt.weekday.format(c)}</span>
                        <span>{fmt.dayMonth.format(c)}</span>
                      </>
                    ) : (
                      <>
                        <span className="text-[10px] first-letter:uppercase">{fmt.weekday.format(c).slice(0, 2)}</span>
                        <span>{c.getDate()}</span>
                      </>
                    )}
                  </div>
                );
              })}
            </div>
          </div>

          {groups.map((g) => (
            <div key={g.key}>
              <div className="flex border-b border-zinc-100 bg-zinc-50 dark:border-zinc-800 dark:bg-zinc-900">
                <div style={{ width: nameWidth }} className="sticky left-0 z-[5] shrink-0 bg-zinc-50 px-3 py-1 text-xs font-semibold uppercase tracking-wide text-zinc-500 dark:bg-zinc-900 dark:text-zinc-400">
                  {g.label}
                </div>
              </div>
              {g.rows.map((r) => (
                <div key={r.id} className="flex border-b border-zinc-100 last:border-b-0 dark:border-zinc-800" style={{ height: ROW }}>
                  <div style={{ width: nameWidth }} className="sticky left-0 z-[5] flex shrink-0 items-center truncate bg-white px-3 dark:bg-zinc-950" title={r.title}>
                    <span className="truncate">{r.title}</span>
                  </div>
                  <div className="relative" style={{ width: chartWidth }}>
                    {cols.map((c) => (
                      <div
                        key={c.getTime()}
                        className={`absolute top-0 h-full border-l border-zinc-100 dark:border-zinc-800/70 ${view !== "day" && weekend(c) ? "bg-zinc-50 dark:bg-zinc-900/60" : ""}`}
                        style={{ left: x(c), width: chartWidth / cols.length }}
                      />
                    ))}
                    {r.bookings.map((b) => (
                      <Bar key={b.bookingId} booking={b} timezone={timezone} start={start} end={end} x={x} view={view} fmt={fmt} labels={labels} onOpen={() => live.send("booking.opened", { bookingId: b.bookingId })} />
                    ))}
                  </div>
                </div>
              ))}
            </div>
          ))}

          {}
          {nowLocal >= start && nowLocal < end && (
            <div
              aria-label={labels.now}
              className="pointer-events-none absolute top-0 bottom-0 z-[4] w-0.5"
              style={{ left: nameWidth + x(nowLocal), background: brand.orange }}
            />
          )}
        </div>
      </div>
    </div>
  );
}

function Bar({
  booking: b,
  timezone,
  start,
  end,
  x,
  view,
  fmt,
  labels,
  onOpen,
}: {
  booking: Booking;
  timezone: string;
  start: Date;
  end: Date;
  x: (d: Date) => number;
  view: View;
  fmt: Record<string, Intl.DateTimeFormat>;
  labels: Props["labels"];
  onOpen: () => void;
}) {
  const from = wallClock(b.startsAt, timezone);
  const to = wallClock(b.endsAt, timezone);
  if (to <= start || from >= end) return null;

  const left = x(from < start ? start : from);
  const width = Math.max(x(to > end ? end : to) - left, 6);
  const status = (b.status in colors ? b.status : "confirmed") as Status;
  const color = colors[status];
  const time = `${fmt.hour.format(from)}–${fmt.hour.format(to)}`;
  const who = b.lessee ?? "";
  const label =
    width > 150 ? [time, who].filter(Boolean).join(" · ") : width > 84 ? time : width > 40 ? fmt.hour.format(from) : "";
  const details = [b.lotTitle, `${fmt.full.format(from)} – ${fmt.hour.format(to)}`, who, labels[status]].filter(Boolean).join("\n");

  return (
    <button
      type="button"
      data-booking={b.bookingId}
      title={details}
      aria-label={details}
      onClick={onOpen}
      className="absolute top-1.5 bottom-1.5 overflow-hidden rounded-md px-1.5 text-left text-xs leading-[30px] whitespace-nowrap shadow-sm hover:brightness-110 focus-visible:outline-2"
      style={{ left, width, background: color.bg, color: color.fg }}
    >
      {label}
    </button>
  );
}

function Legend({ labels }: { labels: Props["labels"] }) {
  return (
    <span className="group/info relative inline-flex">
      <span
        role="button"
        tabIndex={0}
        aria-label={labels.legend}
        className="hero-information-circle size-5 cursor-help opacity-60 hover:opacity-100"
      />
      <span className="invisible absolute top-7 right-0 z-30 w-56 rounded-lg border border-zinc-200 bg-white p-3 text-xs opacity-0 shadow-lg transition group-focus-within/info:visible group-focus-within/info:opacity-100 group-hover/info:visible group-hover/info:opacity-100 dark:border-zinc-700 dark:bg-zinc-900">
        <span className="mb-2 block font-medium">{labels.legend}</span>
        {(["pending", "confirmed", "completed"] as Status[]).map((s) => (
          <span key={s} className="mb-1 flex items-center gap-2">
            <span className="inline-block h-3 w-6 rounded" style={{ background: colors[s].bg }} />
            {labels[s]}
          </span>
        ))}
      </span>
    </span>
  );
}
