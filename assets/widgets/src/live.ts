import type { Packets } from "./packets";

export type Live<W extends keyof Packets> = {
  send: <T extends keyof Packets[W]["from"] & string>(type: T, data: Packets[W]["from"][T]) => void;
  on: <T extends keyof Packets[W]["to"] & string>(type: T, callback: (data: Packets[W]["to"][T]) => void) => () => void;
};
