import { createRoot } from "react-dom/client";
import { StrictMode, type ComponentType } from "react";
import type { Live } from "./live";
import "./widgets.css";

const widgets: Record<string, () => Promise<ComponentType<any>>> = {
  AvailabilityCalendar: () => import("./AvailabilityCalendar").then((m) => m.AvailabilityCalendar),
  PhotoGallery: () => import("./PhotoGallery").then((m) => m.PhotoGallery),
  LessorCalendar: () => import("./LessorCalendar").then((m) => m.LessorCalendar),
  ResourceTimeline: () => import("./ResourceTimeline").then((m) => m.ResourceTimeline),
  BookingBoard: () => import("./BookingBoard").then((m) => m.BookingBoard),
  LessorStats: () => import("./LessorStats").then((m) => m.LessorStats),
  AdminGrid: () => import("./AdminGrid").then((m) => m.AdminGrid),
  PhotoLibrary: () => import("./PhotoLibrary").then((m) => m.PhotoLibrary),
};

export async function mount(element: HTMLElement, name: string, props: object, live: Live<any>) {
  const load = widgets[name];
  if (!load) throw new Error(`Unknown widget: ${name}`);
  const Widget = await load();

  element.replaceChildren();
  const root = createRoot(element);

  const render = (p: object) =>
    root.render(
      <StrictMode>
        <Widget {...p} live={live} />
      </StrictMode>,
    );

  render(props);

  return {
    update: (next: object) => render(next),
    unmount: () => root.unmount(),
  };
}
