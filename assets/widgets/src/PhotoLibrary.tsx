import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { Filemanager, getMenuOptions, type IApi, type IEntity } from "@svar-ui/react-filemanager";
import "@svar-ui/react-filemanager/all.css";
import { buildCSRFHeaders, myItems, myRooms } from "./ash_rpc";
import { Svar } from "./svar";
import { filemanagerWords } from "./locales/filemanager";
import { loadView, saveView } from "./view_state";
import type { Live } from "./live";

type Props = {
  locale: string;
  labels: { items: string; rooms: string; error: string; retry: string };
  live: Live<"PhotoLibrary">;
};

type Kind = "item" | "room";
type Owner = { id: string; title: string; photos: string[]; photoUrls: string[] };
type Photo = { owner: Kind; id: string; key: string; url: string };
type Mode = "cards" | "table" | "panels";

type Place = { kind: Kind; id?: string };
type View = { place: Place | null; mode: Mode; preview: boolean };

const viewKey = "photo-library";
const modes: Mode[] = ["cards", "table", "panels"];

const clean = (s: string) => s.replaceAll("/", "∕");

export function PhotoLibrary({ locale, labels, live }: Props) {
  const [owners, setOwners] = useState<{ items: Owner[]; rooms: Owner[] } | null>(null);
  const [failed, setFailed] = useState(false);
  const saved = useMemo(() => loadView<View>(viewKey), []);
  const [mode, setMode] = useState<Mode>(saved && modes.includes(saved.mode) ? saved.mode : "cards");
  const [preview, setPreview] = useState<boolean>(saved?.preview ?? false);

  const load = useCallback(async () => {
    const headers = buildCSRFHeaders();
    const fields = ["id", "title", "photos", "photoUrls"] as ["id", "title", "photos", "photoUrls"];
    const [items, rooms] = await Promise.all([myItems({ fields, headers }), myRooms({ fields, headers })]);
    if (items.success && rooms.success) {
      setOwners({ items: items.data as Owner[], rooms: rooms.data as Owner[] });
      setFailed(false);
    } else {
      setFailed(true);
    }
  }, []);

  useEffect(() => {
    load();
    return live.on("photos.changed", () => load());
  }, [load, live]);

  const { items: itemsLabel, rooms: roomsLabel } = labels;
  const tree = useMemo(() => {
    const data: IEntity[] = [];
    const photos = new Map<string, Photo>();
    const places = new Map<string, Place>();
    const paths = new Map<string, string>();
    const add = (root: string, kind: Kind, list: Owner[]) => {
      const top = `/${clean(root)}`;
      data.push({ id: top, type: "folder" });
      places.set(top, { kind });
      paths.set(kind, top);
      const used = new Set<string>();
      for (const o of list) {
        let name = clean(o.title);
        if (used.has(name)) name = `${name} (${o.id.slice(0, 4)})`;
        used.add(name);
        const folder = `${top}/${name}`;
        data.push({ id: folder, type: "folder" });
        places.set(folder, { kind, id: o.id });
        paths.set(`${kind}:${o.id}`, folder);
        o.photos.forEach((key, i) => {
          const ext = key.split(".").pop() || "jpg";
          const id = `${folder}/${name} ${i + 1}.${ext}`;
          data.push({ id, type: "file" });
          photos.set(id, { owner: kind, id: o.id, key, url: o.photoUrls[i] });
        });
      }
    };
    if (owners) {
      add(itemsLabel, "item", owners.items);
      add(roomsLabel, "room", owners.rooms);
    }
    return { data, photos, places, paths };
  }, [owners, itemsLabel, roomsLabel]);

  const treeRef = useRef(tree);
  treeRef.current = tree;
  const apiRef = useRef<IApi | null>(null);
  const viewRef = useRef<View>({ place: saved?.place ?? null, mode, preview });

  const remember = useCallback((change: Partial<View>) => {
    viewRef.current = { ...viewRef.current, ...change };
    saveView(viewKey, viewRef.current);
  }, []);

  const pathOf = (place: Place | null) =>
    place ? treeRef.current.paths.get(place.id ? `${place.kind}:${place.id}` : place.kind) : undefined;

  const init = useCallback(
    (api: IApi) => {
      apiRef.current = api;
      const photoOf = (id: string | number) => treeRef.current.photos.get(String(id));

      api.intercept("delete-files", ({ ids }: { ids: (string | number)[] }) => {
        const chosen = ids.map(photoOf).filter((p): p is Photo => !!p);
        if (chosen.length) live.send("photos.deleted", { photos: chosen.map(({ owner, id, key }) => ({ owner, id, key })) });
        return false;
      });
      for (const action of ["rename-file", "move-files", "copy-files", "create-file"] as const) api.intercept(action, () => false);
      for (const action of ["download-file", "open-file"] as const)
        api.intercept(action, ({ id }: { id: string | number }) => {
          const p = photoOf(id);
          if (p) window.open(p.url, "_blank");
          return false;
        });

      api.on("set-path", ({ id }: { id: string | number }) => remember({ place: treeRef.current.places.get(String(id)) ?? null }));
      api.on("set-mode", ({ mode }: { mode: string }) => {
        if (!modes.includes(mode as Mode)) return;
        setMode(mode as Mode);
        remember({ mode: mode as Mode });
      });
      api.on("show-preview", ({ mode }: { mode: boolean }) => {
        setPreview(mode);
        remember({ preview: mode });
      });

      const path = pathOf(viewRef.current.place);
      if (path) api.exec("set-path", { id: path });
    },
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [live, remember],
  );

  useEffect(() => {
    const api = apiRef.current;
    if (!api) return;
    const path = pathOf(viewRef.current.place) ?? "/";
    api.exec("set-path", { id: path });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [tree]);

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
    <div className="basa-photos h-[70vh] overflow-hidden rounded-xl border border-zinc-200 dark:border-zinc-800">
      <Svar locale={locale} words={filemanagerWords}>
        {owners === null ? (
          <div className="h-full animate-pulse bg-zinc-100 dark:bg-zinc-800" />
        ) : (
          <Filemanager
            data={tree.data}
            mode={mode}
            preview={preview}
            init={init}
            previews={(file) => (file.type === "file" && file.id ? (tree.photos.get(String(file.id))?.url ?? null) : null)}
            menuOptions={(mode, item) =>
              item && item.type === "file"
                ? getMenuOptions(mode).filter((o) => o.id === "download" || o.id === "delete")
                : []
            }
          />
        )}
      </Svar>
    </div>
  );
}
