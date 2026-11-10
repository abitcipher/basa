import { useEffect, useMemo, useRef, useState } from "react";
import { AgGridReact } from "ag-grid-react";
import {
  AllCommunityModule,
  ModuleRegistry,
  type GridState,
  type StateUpdatedEvent,
  colorSchemeDark,
  themeQuartz,
  type ColDef,
} from "ag-grid-community";
import {
  AG_GRID_LOCALE_DE,
  AG_GRID_LOCALE_EN,
  AG_GRID_LOCALE_ES,
  AG_GRID_LOCALE_FR,
  AG_GRID_LOCALE_IT,
  AG_GRID_LOCALE_PL,
  AG_GRID_LOCALE_RO,
  AG_GRID_LOCALE_TR,
  AG_GRID_LOCALE_UA,
} from "@ag-grid-community/locale";
import { adminBookings, adminPayments, adminUsers, buildCSRFHeaders } from "./ash_rpc";
import { useDark } from "./theme";
import type { Live } from "./live";
import { loadView, saveView } from "./view_state";

ModuleRegistry.registerModules([AllCommunityModule]);

const gridLocales: Record<string, Record<string, string>> = {
  uk: AG_GRID_LOCALE_UA,
  en: AG_GRID_LOCALE_EN,
  de: AG_GRID_LOCALE_DE,
  fr: AG_GRID_LOCALE_FR,
  es: AG_GRID_LOCALE_ES,
  it: AG_GRID_LOCALE_IT,
  pl: AG_GRID_LOCALE_PL,
  ro: AG_GRID_LOCALE_RO,
  tr: AG_GRID_LOCALE_TR,
};

type Kind = "users" | "bookings" | "payments";

type Props = {
  kind: Kind;
  locale: string;
  labels: Record<string, string>;
  live: Live<"AdminGrid">;
};

const LIMIT = 1000;

async function fetchRows(kind: Kind): Promise<Record<string, unknown>[] | null> {
  const headers = buildCSRFHeaders();
  const page = { limit: LIMIT, offset: 0 };

  const result =
    kind === "users"
      ? await adminUsers({ fields: ["id", "displayName", "email", "telegramUsername", "locale", "bookingsCount"], page, headers })
      : kind === "bookings"
        ? await adminBookings({
            fields: ["id", "startsAt", "lotTitle", "lessorName", "lesseeName", "status", "priceAmount", "currency"],
            page,
            headers,
          })
        : await adminPayments({
            fields: ["id", "paidAt", "purpose", "product", "userName", "lotTitle", "amount", "currency", "status"],
            page,
            headers,
          });

  if (!result.success) return null;
  const data = result.data as { results?: Record<string, unknown>[] } | Record<string, unknown>[];
  return Array.isArray(data) ? data : (data.results ?? []);
}

export function AdminGrid({ kind, locale, labels }: Props) {
  const [rows, setRows] = useState<Record<string, unknown>[] | null>(null);
  const [failed, setFailed] = useState(false);
  const grid = useRef<AgGridReact>(null);
  const dark = useDark();

  useEffect(() => {
    setRows(null);
    fetchRows(kind).then((r) => (r ? setRows(r) : setFailed(true)));
  }, [kind]);

  const dateTime = useMemo(() => new Intl.DateTimeFormat(locale, { dateStyle: "short", timeStyle: "short" }), [locale]);
  const number = useMemo(() => new Intl.NumberFormat(locale, { maximumFractionDigits: 2 }), [locale]);
  const when = (v: unknown) => (v ? dateTime.format(new Date(String(v))) : "");
  const money = (p: { data?: Record<string, unknown>; value: unknown }) =>
    p.value == null ? "" : `${number.format(Number(p.value))} ${p.data?.currency ?? ""}`;

  const columns = useMemo<ColDef[]>(() => {
    const col = (field: string, extra: ColDef = {}): ColDef => ({ field, headerName: labels[field] ?? field, ...extra });

    switch (kind) {
      case "users":
        return [
          col("displayName", { flex: 2 }),
          col("email", { flex: 2 }),
          col("telegramUsername"),
          col("locale", { width: 110 }),
          col("bookingsCount", { width: 130, filter: "agNumberColumnFilter" }),
        ];
      case "bookings":
        return [
          col("startsAt", { valueFormatter: (p) => when(p.value), sort: "desc", filter: "agDateColumnFilter" }),
          col("lotTitle", { flex: 2 }),
          col("lessorName"),
          col("lesseeName"),
          col("status", { valueFormatter: (p) => labels[`status_${p.value}`] ?? String(p.value) }),
          col("priceAmount", { valueFormatter: money, type: "rightAligned", filter: "agNumberColumnFilter" }),
        ];
      case "payments":
        return [
          col("paidAt", { valueFormatter: (p) => when(p.value), sort: "desc" }),
          col("purpose"),
          col("userName", { flex: 2 }),
          col("lotTitle", { flex: 2 }),
          col("status"),
          col("amount", { valueFormatter: money, type: "rightAligned", filter: "agNumberColumnFilter" }),
        ];
    }
  }, [kind, labels, dateTime, number]);

  const theme = useMemo(() => (dark ? themeQuartz.withPart(colorSchemeDark) : themeQuartz), [dark]);

  const viewKey = `admin-grid:${kind}`;
  const initialState = useMemo(() => loadView<GridState>(viewKey) ?? undefined, [viewKey]);

  if (failed) return <p className="text-sm text-rose-600">{labels.error}</p>;

  return (
    <div className="space-y-2">
      <div className="flex items-center justify-between gap-2 text-sm">
        <span className="opacity-70">{rows ? `${rows.length}${rows.length === LIMIT ? "+" : ""}` : ""}</span>
        <button
          type="button"
          className="rounded-lg border border-zinc-300 px-3 py-1 hover:bg-zinc-50 dark:border-zinc-700 dark:hover:bg-zinc-800"
          onClick={() => grid.current?.api.exportDataAsCsv({ fileName: `basa-${kind}.csv` })}
        >
          {labels.export}
        </button>
      </div>
      <div className="h-[70vh]">
        <AgGridReact
          key={kind}
          ref={grid}
          initialState={initialState}
          onStateUpdated={(e: StateUpdatedEvent) => saveView(viewKey, e.state)}
          theme={theme}
          rowData={rows ?? undefined}
          loading={rows === null}
          columnDefs={columns}
          defaultColDef={{ flex: 1, sortable: true, filter: true, resizable: true, minWidth: 110 }}
          localeText={gridLocales[locale] ?? AG_GRID_LOCALE_EN}
          pagination
          paginationPageSize={50}
          paginationPageSizeSelector={[25, 50, 100]}
        />
      </div>
    </div>
  );
}
