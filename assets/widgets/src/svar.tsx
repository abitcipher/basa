import type { ReactNode } from "react";
import { useDark } from "./theme";
import { Locale, Willow, WillowDark } from "@svar-ui/react-core";
import { de, en, es, fr, it } from "@svar-ui/core-locales";
import uk from "./locales/uk";
import { pl, ro, tr } from "./locales/more";
import "@svar-ui/react-core/all.css";
import "./vendor/wx-icons/wx-icons.css";

const core: Record<string, object> = { uk, en, de, fr, es, it, pl: pl.core, ro: ro.core, tr: tr.core };

export function Svar({
  locale,
  words = {},
  children,
}: {
  locale: string;
  words?: Record<string, object>;
  children: ReactNode;
}) {
  const Theme = useDark() ? WillowDark : Willow;
  const lang = core[locale] ? locale : "en";

  return (
    <Theme fonts={false}>
      <Locale words={{ ...core[lang], ...(words[lang] ?? words.en ?? {}) }}>{children}</Locale>
    </Theme>
  );
}
