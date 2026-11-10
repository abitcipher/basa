// @svar-ui/core-locales ships plain JS
declare module "@svar-ui/core-locales" {
  const locale: { core: object; calendar: object; formats: object; lang: string };
  export const en: typeof locale, de: typeof locale, fr: typeof locale, es: typeof locale, it: typeof locale;
}

declare module "@svar-ui/calendar-locales" {
  const locale: { eventCalendar: Record<string, string> };
  export const en: typeof locale, de: typeof locale, fr: typeof locale, es: typeof locale, it: typeof locale;
}

declare module "@svar-ui/kanban-locales" {
  const locale: { kanban: Record<string, string> };
  export const en: typeof locale, de: typeof locale, fr: typeof locale, es: typeof locale, it: typeof locale;
}
