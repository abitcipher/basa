import { draggable, dropTargetForElements, monitorForElements } from "@atlaskit/pragmatic-drag-and-drop/element/adapter";
import { combine } from "@atlaskit/pragmatic-drag-and-drop/combine";

export function sortable(container: HTMLElement, onReorder: (keys: string[]) => void): () => void {
  const items = [...container.querySelectorAll<HTMLElement>("[data-sort-key]")];
  container.querySelectorAll("img").forEach((img) => (img.draggable = false));
  const keys = () => items.map((el) => el.dataset.sortKey as string);

  const cleanups = items.map((el) =>
    combine(
      draggable({ element: el, getInitialData: () => ({ key: el.dataset.sortKey, scope: container.id }) }),
      dropTargetForElements({
        element: el,
        canDrop: ({ source }) => source.data.scope === container.id,
        getData: () => ({ key: el.dataset.sortKey }),
        onDragEnter: () => el.classList.add("ring-2", "ring-primary-light"),
        onDragLeave: () => el.classList.remove("ring-2", "ring-primary-light"),
        onDrop: () => el.classList.remove("ring-2", "ring-primary-light"),
      }),
    ),
  );

  const monitor = monitorForElements({
    canMonitor: ({ source }) => source.data.scope === container.id,
    onDrop: ({ source, location }) => {
      const target = location.current.dropTargets[0];
      if (!target) return;
      const from = keys().indexOf(String(source.data.key));
      const to = keys().indexOf(String(target.data.key));
      if (from < 0 || to < 0 || from === to) return;
      const order = keys();
      const [moved] = order.splice(from, 1);
      order.splice(to, 0, moved);
      onReorder(order);
    },
  });

  return combine(...cleanups, monitor);
}
