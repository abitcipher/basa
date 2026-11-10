import "phoenix_html";
import { Socket } from "phoenix";
import { LiveSocket } from "phoenix_live_view";
import { hooks as colocatedHooks } from "phoenix-colocated/basa";
import topbar from "../vendor/topbar";
import { MapPicker, ChatScroll, RulesEditor, CityPicker, Widget, ResultsMap, PhotoSort, Composer, DeviceKey, VoiceRecorder, UiApply, BrokenPictures, ThumbSize, PagePicker } from "./hooks";
import MishkaComponents from "../vendor/mishka_components.js";
import { startTelegram, TmaChatScroll } from "basa_tma";
import { installCardGlow } from "./card_glow";
import { startKeepState, KeepState } from "./keep_state";
const csrfToken = document
  .querySelector("meta[name='csrf-token']")
  .getAttribute("content");
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {
    _csrf_token: csrfToken,
  },
  hooks: {
    ...colocatedHooks,
    MapPicker,
    ChatScroll,
    TmaChatScroll,
    RulesEditor,
    CityPicker,
    Widget,
    ResultsMap,
    PhotoSort,
    Composer,
    DeviceKey,
    VoiceRecorder,
    UiApply,
    BrokenPictures,
    PagePicker,
    ThumbSize,
    KeepState,
    ...MishkaComponents,
  },
});
topbar.config({
  barColors: {
    0: "#29d",
  },
  shadowColor: "rgba(0, 0, 0, .3)",
});
window.addEventListener("phx:page-loading-start", (_info) => topbar.show(300));
window.addEventListener("phx:page-loading-stop", (_info) => topbar.hide());

window.addEventListener("phx:witness:download", ({ detail }) => {
  const link = document.createElement("a")
  link.href = detail.url
  link.download = ""
  document.body.appendChild(link)
  link.click()
  link.remove()
});
startKeepState();

liveSocket.connect();

startTelegram(liveSocket, { home: "/" });
installCardGlow();
window.liveSocket = liveSocket;
if (process.env.NODE_ENV === "development") {
  window.addEventListener(
    "phx:live_reload:attached",
    ({ detail: reloader }) => {
      reloader.enableServerLogs();
      let keyDown;
      window.addEventListener("keydown", (e) => (keyDown = e.key));
      window.addEventListener("keyup", (_e) => (keyDown = null));
      window.addEventListener(
        "click",
        (e) => {
          if (keyDown === "c") {
            e.preventDefault();
            e.stopImmediatePropagation();
            reloader.openEditorAtCaller(e.target);
          } else if (keyDown === "d") {
            e.preventDefault();
            e.stopImmediatePropagation();
            reloader.openEditorAtDef(e.target);
          }
        },
        true,
      );
      window.liveReloader = reloader;
    },
  );
}
