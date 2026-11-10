import { useEffect, useState } from "react";

export function useDark(): boolean {
  const read = () => document.documentElement.getAttribute("data-theme") === "dark";
  const [dark, setDark] = useState(read);

  useEffect(() => {
    const observer = new MutationObserver(() => setDark(read()));
    observer.observe(document.documentElement, { attributes: true, attributeFilter: ["data-theme"] });
    return () => observer.disconnect();
  }, []);

  return dark;
}

export const brand = {
  cyan: "#00ccff",
  green: "#00d400",
  yellow: "#ffd42a",
  orange: "#ff7f2a",
  cyanDeep: "#007ea3",
} as const;
