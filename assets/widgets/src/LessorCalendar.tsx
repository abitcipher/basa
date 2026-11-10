import { useCallback, useEffect, useMemo, useState } from "react";
import { Calendar } from "@svar-ui/react-calendar";
import { de, en, es, fr, it } from "@svar-ui/calendar-locales";
import { pl, ro, tr } from "./locales/more";
import "@svar-ui/react-calendar/all.css";
import { buildCSRFHeaders, lessorSchedule } from "./ash_rpc";
import { Svar } from "./svar";
import { addDays, isoDate, wallClock } from "./time";
import uk from "./locales/uk-calendar";
import type { Live } from "./live";
import { loadView, saveView } from "./view_state";

type Props = {
  locale: string;
  labels: { error: string; retry: string; pending: string; confirmed: string; completed: string };
  live: Live<"LessorCalendar">;
};

type Row = {
  id: string;
  lotTitle: string;
  startsAt: string;
  endsAt: string;
  status: string;
  lessee: string | null;
  timezone: string;
};

const narrow = window.matchMedia("(max-width: 639px)").matches;

type View = "day" | "week" | "month";
const views: View[] = ["day", "week", "month"];
const viewKey = "lessor-calendar";

const range = (anchor: Date) => ({ from: isoDate(addDays(anchor, -31)), to: isoDate(addDays(anchor, 61)) });
const outside = (d: Date, anchor: Date) => d < addDays(anchor, -24) || d > addDays(anchor, 50);

function EventContent({ event, time }: { event: { start: Date; end: Date; text?: string }; time: Intl.DateTimeFormat }) {
  return (
    <div className="px-1 text-xs leading-tight">
      <div className="font-semibold">
        {time.format(event.start)}–{time.format(event.end)}
      </div>
      <div>{event.text}</div>
    </div>
  );
}

export function LessorCalendar({ locale, labels, live }: Props) {
  const [rows, setRows] = useState<Row[] | null>(null);
  const [failed, setFailed] = useState(false);

  const saved = useMemo(() => loadView<{ view: View; date: string }>(viewKey), []);
  const [view, setView] = useState<View>(() =>
    saved && views.includes(saved.view) ? saved.view : narrow ? "day" : "week",
  );
  const [date, setDate] = useState<Date>(() => {
    const d = saved ? new Date(saved.date) : new Date();
    return Number.isNaN(d.getTime()) ? new Date() : d;
  });
  const [anchor, setAnchor] = useState<Date>(date);
  useEffect(() => saveView(viewKey, { view, date: date.toISOString() }), [view, date]);
  useEffect(() => {
    if (outside(date, anchor)) setAnchor(date);
  }, [date, anchor]);

  const load = useCallback(async () => {
    const result = await lessorSchedule({
      input: range(anchor),
      fields: ["id", "lotTitle", "startsAt", "endsAt", "status", "lessee", "timezone"],
      headers: buildCSRFHeaders(),
    });
    if (result.success) {
      const loaded: Row[] = result.data;
      setRows(loaded);
      setFailed(false);
    } else {
      setFailed(true);
    }
  }, [anchor]);

  useEffect(() => {
    load();
    return live.on("bookings.changed", () => load());
  }, [load, live]);

  const time = useMemo(() => new Intl.DateTimeFormat(locale, { hour: "2-digit", minute: "2-digit" }), [locale]);
  const content = useMemo(
    () =>
      function Content({ event }: { event: { start: Date; end: Date; text?: string } }) {
        return <EventContent event={event} time={time} />;
      },
    [time],
  );

  const events = useMemo(
    () =>
      (rows ?? []).map((b) => ({
        id: b.id,
        start: wallClock(b.startsAt, b.timezone),
        end: wallClock(b.endsAt, b.timezone),
        text: [b.lotTitle, b.lessee].filter(Boolean).join(" · "),
        status: b.status,
      })),
    [rows],
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
    <div className="basa-lessor-calendar">
      <div className="mb-2 flex flex-wrap gap-3 text-xs opacity-80">
        {(["pending", "confirmed", "completed"] as const).map((s) => (
          <span key={s} className="flex items-center gap-1">
            <i className={`basa-status-dot basa-ev-${s}`} />
            {labels[s]}
          </span>
        ))}
      </div>
      <div className="h-[70vh] overflow-hidden rounded-xl border border-zinc-200 dark:border-zinc-800">
        <Svar locale={locale} words={{ uk, en, de, fr, es, it, pl: pl.calendar, ro: ro.calendar, tr: tr.calendar }}>
          {rows === null ? (
            <div className="h-full animate-pulse bg-zinc-100 dark:bg-zinc-800" />
          ) : (
            <Calendar
              events={events}
              readonly
              view={view}
              views={views}
              date={date}
              init={(api) => {
                const follow = () => {
                  const { currentView, currentDate } = api.getState();
                  if (views.includes(currentView as View)) setView(currentView as View);
                  if (currentDate) setDate(new Date(currentDate));
                };
                api.on("navigate-to", follow);
                api.on("navigate-time", follow);
              }}
              eventCss={({ event }) => `basa-ev-${event.status}`}
              eventContent={content}
              onSelectEvent={({ id }) => {
                if (id != null) live.send("booking.opened", { bookingId: String(id) });
              }}
            />
          )}
        </Svar>
      </div>
    </div>
  );
}
