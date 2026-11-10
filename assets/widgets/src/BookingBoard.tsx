import { useCallback, useEffect, useMemo, useState } from "react";
import { Kanban, type KanbanCard, type KanbanInstanceApi } from "@svar-ui/react-kanban";
import { de, en, es, fr, it } from "@svar-ui/kanban-locales";
import "@svar-ui/react-kanban/all.css";
import { buildCSRFHeaders, lessorSchedule } from "./ash_rpc";
import { Svar } from "./svar";
import { addDays, isoDate } from "./time";
import type { Live } from "./live";

type Column = "pending" | "confirmed" | "completed" | "closed";

type Props = {
  locale: string;
  labels: Record<Column, string> & { error: string; retry: string; empty: string };
  live: Live<"BookingBoard">;
};

type Row = {
  id: string;
  lotTitle: string;
  startsAt: string;
  endsAt: string;
  status: string;
  lessee: string | null;
  timezone: string;
  priceAmount: string;
  currency: string;
};

const today = new Date();
const from = isoDate(addDays(today, -14));
const to = isoDate(addDays(today, 60));

const COLUMNS: Column[] = ["pending", "confirmed", "completed", "closed"];

export function BookingBoard({ locale, labels, live }: Props) {
  const [rows, setRows] = useState<Row[] | null>(null);
  const [failed, setFailed] = useState(false);

  const load = useCallback(async () => {
    const result = await lessorSchedule({
      input: { from, to },
      fields: ["id", "lotTitle", "startsAt", "endsAt", "status", "lessee", "timezone", "priceAmount", "currency"],
      headers: buildCSRFHeaders(),
    });
    if (result.success) {
      const loaded: Row[] = result.data;
      setRows(loaded);
      setFailed(false);
    } else {
      setFailed(true);
    }
  }, []);

  useEffect(() => {
    load();
    return live.on("bookings.changed", () => load());
  }, [load, live]);

  const columns = useMemo(() => COLUMNS.map((id) => ({ id, label: labels[id], addCard: false })), [labels]);

  const cards = useMemo(() => {
    return (rows ?? []).map((b) => {
      const when = new Intl.DateTimeFormat(locale, {
        weekday: "short",
        day: "numeric",
        month: "short",
        hour: "2-digit",
        minute: "2-digit",
        timeZone: b.timezone,
      }).format(new Date(b.startsAt));
      const price = new Intl.NumberFormat(locale, { maximumFractionDigits: 2 }).format(Number(b.priceAmount));
      return { id: b.id, label: b.lotTitle, column: b.status, when, lessee: b.lessee, price: `${price} ${b.currency}` };
    });
  }, [rows, locale]);

  const init = useCallback(
    (api: KanbanInstanceApi) => {
      api.intercept("move-card", ({ id, column }) => {
        const card = api.getCards().find((c) => c.id === id);
        if (card && column && column !== card.column) live.send("booking.moved", { bookingId: String(id), to: String(column) });
        return false;
      });
      api.on("select-card", ({ id }) => {
        if (id != null) live.send("booking.opened", { bookingId: String(id) });
      });
    },
    [live],
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

  if (rows !== null && rows.length === 0) return <p className="text-sm opacity-70">{labels.empty}</p>;

  return (
    <div className="basa-board h-[70vh] overflow-hidden rounded-xl border border-zinc-200 dark:border-zinc-800">
      <Svar locale={locale} words={{ en, de, fr, es, it }}>
        {rows === null ? (
          <div className="h-full animate-pulse bg-zinc-100 dark:bg-zinc-800" />
        ) : (
          <Kanban
            cards={cards}
            columns={columns}
            card={{ menu: false }}
            render={{ fixedColumnWidth: false }}
            cardContent={CardContent}
            cardCss={(card) => `basa-card-${card.column}`}
            init={init}
          />
        )}
      </Svar>
    </div>
  );
}

function CardContent({ card }: { card: KanbanCard }) {
  return (
    <div className="space-y-0.5 p-2 text-sm">
      <div className="font-semibold">{card.label}</div>
      <div className="opacity-80">{card.when}</div>
      <div className="flex justify-between gap-2 text-xs opacity-70">
        <span>{card.lessee}</span>
        <span>{card.price}</span>
      </div>
    </div>
  );
}
