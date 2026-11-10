import { useCallback, useEffect, useMemo, useState } from "react";
import { Calendar } from "@svar-ui/react-core";
import { buildCSRFHeaders, lotAvailability } from "./ash_rpc";
import { Svar } from "./svar";
import type { Live } from "./live";
import { loadView, saveView } from "./view_state";

type Slot = { startsAt: string; endsAt: string; free: boolean };
type Day = { date: string; free: number; total: number; slots: Slot[] };

type Props = {
  lotId: string;
  today: string;
  timezone: string;
  locale: string;
  days?: number;
  wholeDay?: boolean;
  readOnly?: boolean;
  labels: {
    closed: string;
    full: string;
    wholeDay: string;
    legendFree: string;
    legendFew: string;
    legendFull: string;
    error: string;
    retry: string;
  };
  live: Live<"AvailabilityCalendar">;
};

export function AvailabilityCalendar({
  lotId,
  today,
  timezone,
  locale,
  days = 56,
  wholeDay = false,
  readOnly = false,
  labels,
  live,
}: Props) {
  const [data, setData] = useState<Day[] | null>(null);
  const [failed, setFailed] = useState(false);
  const viewKey = `availability:${lotId}`;
  const [picked, setPicked] = useState<string | null>(() => loadView<{ day: string }>(viewKey)?.day ?? null);
  useEffect(() => {
    if (picked) saveView(viewKey, { day: picked });
  }, [viewKey, picked]);

  const load = useCallback(async () => {
    const result = await lotAvailability({
      input: { lotId, from: today, days },
      fields: ["date", "free", "total", { slots: ["startsAt", "endsAt", "free"] }],
      headers: buildCSRFHeaders(),
    });
    if (result.success) {
      const loaded: Day[] = result.data;
      setData(loaded);
      setFailed(false);
    } else {
      setFailed(true);
    }
  }, [lotId, today, days]);

  useEffect(() => {
    load();
    return live.on("availability.changed", () => load());
  }, [load, live]);

  const byDate = useMemo(() => new Map((data ?? []).map((d) => [d.date, d])), [data]);
  const selected = picked && (data === null || byDate.has(picked)) ? picked : today;
  const day = byDate.get(selected);
  const time = useMemo(
    () => new Intl.DateTimeFormat(locale, { hour: "2-digit", minute: "2-digit", timeZone: timezone }),
    [locale, timezone],
  );
  const title = useMemo(
    () => new Intl.DateTimeFormat(locale, { weekday: "long", day: "numeric", month: "long", timeZone: "UTC" }),
    [locale],
  );

  const markers = useCallback(
    (date: Date) => {
      const d = byDate.get(isoDate(date));
      if (!d) return "basa-out";
      if (d.total === 0) return "basa-closed";
      if (d.free === 0) return "basa-full";
      return d.free / d.total > 0.5 ? "basa-free" : "basa-few";
    },
    [byDate],
  );

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

  return (
    <div className="grid gap-4 md:grid-cols-[auto_1fr]">
      <div className="basa-availability mx-auto w-fit rounded-xl border border-zinc-200 p-2 md:mx-0 dark:border-zinc-800">
        <Svar locale={locale}>
          <Calendar
            value={localDate(selected)}
            current={localDate(selected)}
            markers={markers}
            buttons={false}
            onChange={({ value }) => {
              if (value && byDate.has(isoDate(value))) setPicked(isoDate(value));
            }}
          />
        </Svar>
        <div className="mt-2 flex flex-wrap gap-3 px-2 pb-1 text-xs opacity-70">
          <span className="flex items-center gap-1"><i className="basa-dot basa-dot-free" />{labels.legendFree}</span>
          <span className="flex items-center gap-1"><i className="basa-dot basa-dot-few" />{labels.legendFew}</span>
          <span className="flex items-center gap-1"><i className="basa-dot basa-dot-full" />{labels.legendFull}</span>
        </div>
      </div>

      <div>
        <p className="mb-2 font-semibold first-letter:uppercase">{title.format(new Date(`${selected}T00:00:00Z`))}</p>
        {!data && <div className="h-24 animate-pulse rounded-xl bg-zinc-100 dark:bg-zinc-800" />}
        {data && (!day || day.total === 0) && <p className="text-sm opacity-70">{labels.closed}</p>}
        {day && day.total > 0 && day.free === 0 && <p className="mb-2 text-sm opacity-70">{labels.full}</p>}
        {day && day.total > 0 && (
          <div id="slots" className="grid grid-cols-3 gap-2 sm:grid-cols-4 lg:grid-cols-5">
            {day.slots.map((s) => (
              <button
                key={s.startsAt}
                type="button"
                disabled={!s.free || readOnly}
                onClick={() => live.send("slot.picked", { startsAt: s.startsAt })}
                className={[
                  "rounded-lg border px-2 py-2 text-sm transition",
                  s.free
                    ? "border-emerald-300 hover:bg-emerald-50 dark:border-emerald-800 dark:hover:bg-emerald-950"
                    : "border-zinc-200 line-through opacity-50 dark:border-zinc-800",
                  readOnly ? "cursor-default" : "",
                ].join(" ")}
              >
                {wholeDay ? labels.wholeDay : time.format(new Date(s.startsAt))}
              </button>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}

function isoDate(d: Date): string {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
}

function localDate(iso: string): Date {
  const [y, m, d] = iso.split("-").map(Number);
  return new Date(y, m - 1, d);
}
