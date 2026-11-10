const LEAFLET = "https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.9.4"
let leafletLoading = null

function loadLeaflet() {
  if (window.L) return Promise.resolve(window.L)
  if (leafletLoading) return leafletLoading
  leafletLoading = new Promise((resolve, reject) => {
    const css = document.createElement("link")
    css.rel = "stylesheet"
    css.href = `${LEAFLET}/leaflet.min.css`
    document.head.appendChild(css)
    const js = document.createElement("script")
    js.src = `${LEAFLET}/leaflet.min.js`
    js.onload = () => resolve(window.L)
    js.onerror = reject
    document.head.appendChild(js)
  })
  return leafletLoading
}

export const MapPicker = {
  async mounted() {
    const L = await loadLeaflet()
    const lat = parseFloat(this.el.dataset.lat) || 46.4825
    const lng = parseFloat(this.el.dataset.lng) || 30.7233

    this.map = L.map(this.el).setView([lat, lng], 14)
    L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
      maxZoom: 19,
      attribution: "© OpenStreetMap"
    }).addTo(this.map)

    const icon = L.icon({
      iconUrl: `${LEAFLET}/images/marker-icon.png`,
      iconRetinaUrl: `${LEAFLET}/images/marker-icon-2x.png`,
      shadowUrl: `${LEAFLET}/images/marker-shadow.png`,
      iconSize: [25, 41], iconAnchor: [12, 41]
    })
    const readonly = this.el.dataset.readonly !== undefined
    this.marker = L.marker([lat, lng], {draggable: !readonly, icon}).addTo(this.map)
    if (readonly) {
      this.map.scrollWheelZoom.disable()
      if (this.el.dataset.radiusKm) {
        L.circle([lat, lng], {radius: parseFloat(this.el.dataset.radiusKm) * 1000, weight: 1}).addTo(this.map)
      }
      return
    }

    const push = ({lat, lng}) => this.pushEvent("pin", {lat, lng})
    this.marker.on("dragend", () => push(this.marker.getLatLng()))
    this.map.on("click", (e) => { this.marker.setLatLng(e.latlng); push(e.latlng) })

    this.handleEvent("map:center", ({lat, lng}) => {
      this.map.setView([lat, lng], 13)
      this.marker.setLatLng([lat, lng])
    })
    this.handleEvent("map:refresh", () => setTimeout(() => this.map.invalidateSize(), 50))
  },
  destroyed() { this.map && this.map.remove() }
}

export const ChatScroll = {
  mounted() {
    this.scroll()
    this.handleEvent("chat:scroll", () => setTimeout(() => this.scroll(), 30))
  },
  updated() { this.scroll() },
  scroll() { this.el.scrollTop = this.el.scrollHeight }
}

const RULES_EDITOR = "/assets/rules_editor"

function readDraft(key, base) {
  try {
    const d = JSON.parse(sessionStorage.getItem(key) || "null")
    if (d && d.base === base && Date.now() - d.at < 86_400_000) return d.graph
    if (d) sessionStorage.removeItem(key)
  } catch {  }
  return null
}
function writeDraft(key, base, graph) {
  try { sessionStorage.setItem(key, JSON.stringify({ base, graph, at: Date.now() })) } catch {  }
}
function dropDraft(key) {
  try { sessionStorage.removeItem(key) } catch {  }
}

export const RulesEditor = {
  async mounted() {
    if (!document.querySelector(`link[href="${RULES_EDITOR}/rules_editor.css"]`)) {
      const css = document.createElement("link")
      css.rel = "stylesheet"
      css.href = `${RULES_EDITOR}/rules_editor.css`
      document.head.appendChild(css)
    }

    const { mount, mountJson } = await import(/* @vite-ignore */ `${RULES_EDITOR}/rules_editor.js`)
    this.mountJson = mountJson
    this.mode = "visual"
    this.tab = 1
    const saved = this.el.dataset.graph
    const draftKey = `basa:draft:rules:${location.pathname}#${this.el.id}`
    const draft = readDraft(draftKey, saved)
    const graph = JSON.parse(draft || saved)
    let baseline = null
    this.editor = mount(this.el.querySelector("[data-editor-root]"), {
      graph,
      onChange: (value) => {
        const json = JSON.stringify(value)
        if (baseline === null) {
          baseline = draft ? JSON.stringify(JSON.parse(saved)) : json
          if (draft) this.pushEvent("changed", {})
          return
        }
        if (json !== baseline) {
          writeDraft(draftKey, saved, json)
          this.pushEvent("changed", {})
        } else {
          dropDraft(draftKey)
        }
      }
    })
    this.context = mountJson(document.getElementById("rules-context"), {
      value: JSON.parse(this.el.dataset.context || "{}")
    })
    this.handleEvent("rules:saved", () => {
      baseline = JSON.stringify(this.graph())
      dropDraft(draftKey)
    })

    this.el.addEventListener("rules:tab", (e) => this.setTab(e.detail.tab))

    this.el.addEventListener("rules:save", () => {
      this.withGraph((graph) => this.pushEvent("save_graph", { graph }))
    })

    this.el.addEventListener("rules:simulate", () => {
      if (!this.setTab(1)) return
      const context = this.context.getText()
      this.pushEvent("simulate", { graph: this.editor.getGraph(), context }, (reply) => {
        this.editor.setSimulate(reply.simulate)
      })
    })
  },

  graph() {
    return this.mode === "json" ? this.json.get() : this.editor.getGraph()
  },

  withGraph(fn) {
    try { fn(this.graph()) } catch (e) { this.pushEvent("json_error", { message: e.message }) }
  },

  setTab(tab) {
    if (tab === 2 && this.mode !== "json") {
      const graph = this.editor.getGraph()
      if (this.json) {
        this.json.set(graph)
      } else {
        this.json = this.mountJson(this.el.querySelector("[data-json-root]"), {
          value: graph,
          onChange: () => this.pushEvent("changed", {})
        })
      }
      this.mode = "json"
    } else if (tab === 1 && this.mode === "json") {
      let graph
      try { graph = this.json.get() } catch (e) {
        this.pushEvent("json_error", { message: e.message })
        return false
      }
      this.editor.setGraph(graph)
      this.mode = "visual"
    }
    if (tab !== this.tab) {
      this.liveSocket.execJS(this.el, this.el.getAttribute(`data-show-${tab}`))
      this.tab = tab
      requestAnimationFrame(() => {
        if (tab === 2 && this.json) this.json.refresh()
        if (tab === 3) this.context.refresh()
      })
    }
    return true
  },

  destroyed() {
    this.editor && this.editor.unmount()
    this.json && this.json.destroy()
    this.context && this.context.destroy()
  }
}

export const CityPicker = {
  mounted() {
    const options = () => [...this.el.querySelectorAll("[role=option]")]
    const input = () => this.el.querySelector("[data-city-input]")

    this.el.addEventListener("focusin", (e) => {
      if (e.target === input()) e.target.select()
    })

    this.el.addEventListener("keydown", (e) => {
      const list = options()
      const i = list.indexOf(document.activeElement)
      if (e.key === "ArrowDown" && list.length) {
        e.preventDefault()
        list[Math.min(i + 1, list.length - 1)].focus()
      } else if (e.key === "ArrowUp" && list.length) {
        e.preventDefault()
        i <= 0 ? input().focus() : list[i - 1].focus()
      } else if (e.key === "Enter" && e.target === input()) {
        e.preventDefault()
        list[0] && list[0].click()
      }
    })

    this.el.addEventListener("click", (e) => {
      if (!e.target.closest("[data-near-me]")) return
      const fail = (reason) => this.pushEventTo(this.el, "geo_error", {reason})
      if (!window.isSecureContext) return fail("insecure")
      if (!navigator.geolocation) return fail("unavailable")
      const reasons = {1: "denied", 2: "unavailable", 3: "timeout"}
      navigator.geolocation.getCurrentPosition(
        ({coords}) => this.pushEventTo(this.el, "near", {lat: coords.latitude, lng: coords.longitude}),
        (err) => fail(reasons[err.code] || "unavailable"),
        {enableHighAccuracy: false, timeout: 10000, maximumAge: 600000}
      )
    })
  }
}

const WIDGETS = "/assets/widgets"
let widgetsLoading = null

function loadWidgets() {
  widgetsLoading = widgetsLoading || import(/* @vite-ignore */ `${WIDGETS}/widgets.js`)
  return widgetsLoading
}

export const Widget = {
  async mounted() {
    const { mount } = await loadWidgets()
    const component = this.el.dataset.component
    const listeners = new Map()

    this.handleEvent(`widget:${this.el.id}`, ({type, data}) => {
      (listeners.get(type) || []).forEach((callback) => callback(data))
    })

    const live = {
      send: (type, data) => this.pushEvent("widget:event", {widget: this.el.id, component, type, data}),
      on: (type, callback) => {
        listeners.set(type, [...(listeners.get(type) || []), callback])
        return () => listeners.set(type, (listeners.get(type) || []).filter((c) => c !== callback))
      }
    }
    this.lastProps = this.el.dataset.props
    this.widget = await mount(this.el.querySelector("[data-widget-root]"), component, this.props(), live)
  },
  updated() {
    if (!this.widget || this.el.dataset.props === this.lastProps) return
    this.lastProps = this.el.dataset.props
    this.widget.update(this.props())
  },
  destroyed() { this.widget && this.widget.unmount() },
  props() { return JSON.parse(this.el.dataset.props || "{}") }
}

export const ResultsMap = {
  async mounted() {
    const L = await loadLeaflet()
    this.L = L
    this.map = L.map(this.el, {scrollWheelZoom: false})
    L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
      maxZoom: 19,
      attribution: "© OpenStreetMap"
    }).addTo(this.map)
    this.icon = L.icon({
      iconUrl: `${LEAFLET}/images/marker-icon.png`,
      iconRetinaUrl: `${LEAFLET}/images/marker-icon-2x.png`,
      shadowUrl: `${LEAFLET}/images/marker-shadow.png`,
      iconSize: [25, 41], iconAnchor: [12, 41], popupAnchor: [0, -34]
    })
    this.layer = L.layerGroup().addTo(this.map)

    this.el.addEventListener("click", (e) => {
      const button = e.target.closest("[data-open-lot]")
      if (button) this.pushEvent("open_lot", {id: button.dataset.openLot})
    })

    this.draw()
  },
  updated() { this.map && this.draw() },
  destroyed() { this.map && this.map.remove() },

  draw() {
    const markers = JSON.parse(this.el.dataset.markers || "[]")
    const label = this.el.dataset.openLabel || "Open"
    this.layer.clearLayers()

    const places = new Map()
    for (const m of markers) {
      const key = `${m.lat.toFixed(5)},${m.lng.toFixed(5)}`
      places.set(key, [...(places.get(key) || []), m])
    }

    for (const offers of places.values()) {
      const popup = document.createElement("div")
      popup.className = "space-y-2"
      for (const m of offers) {
        const item = document.createElement("div")
        const title = document.createElement("p")
        title.className = "font-semibold"
        title.textContent = (m.featured ? "★ " : "") + m.title
        const price = document.createElement("p")
        price.textContent = m.price
        const open = document.createElement("button")
        open.type = "button"
        open.dataset.openLot = m.id
        open.className = "underline"
        open.textContent = label
        item.append(title, price, open)
        popup.append(item)
      }
      this.L.marker([offers[0].lat, offers[0].lng], {icon: this.icon}).bindPopup(popup).addTo(this.layer)
    }

    if (markers.length === 1) this.map.setView([markers[0].lat, markers[0].lng], 14)
    else if (markers.length > 1) this.map.fitBounds(markers.map((m) => [m.lat, m.lng]), {padding: [30, 30], maxZoom: 15})
    setTimeout(() => this.map.invalidateSize(), 50)
  }
}

export const PhotoSort = {
  mounted() { this.init() },
  updated() { this.init() },
  destroyed() { this.cleanup && this.cleanup() },
  async init() {
    this.cleanup && this.cleanup()
    const { sortable } = await import(/* @vite-ignore */ `${WIDGETS}/sortable.js`)
    this.cleanup = sortable(this.el, (keys) => this.pushEvent("reorder_photos", { keys }))
  }
}

export const Composer = {
  mounted() { this.bind() },
  updated() { this.bind() },
  bind() {
    const input = this.el.querySelector("[data-composer-input]")
    const send = this.el.querySelector("[data-composer-send]")
    if (!input || input === this.input) return
    this.input = input

    const refresh = () => {
      input.style.height = "auto"
      input.style.height = `${input.scrollHeight}px`
      send.disabled = input.value.trim() === ""
    }
    const touch = window.matchMedia("(pointer: coarse)").matches

    input.addEventListener("input", refresh)
    input.addEventListener("keydown", (e) => {
      if (e.key === "Enter" && !e.shiftKey && !e.isComposing && !touch) {
        e.preventDefault()
        if (input.value.trim() !== "") this.el.requestSubmit()
      }
    })
    refresh()
    setTimeout(refresh, 50)
    if (this.sentOnce) input.focus()
    this.sentOnce = true
  }
}

const KEY_DB = "basa-device-keys"

function keyStore(mode, fn) {
  return new Promise((resolve, reject) => {
    const open = indexedDB.open(KEY_DB, 1)
    open.onupgradeneeded = () => open.result.createObjectStore("keys")
    open.onerror = () => reject(open.error)
    open.onsuccess = () => {
      const tx = open.result.transaction("keys", mode)
      const req = fn(tx.objectStore("keys"))
      tx.oncomplete = () => resolve(req && req.result)
      tx.onerror = () => reject(tx.error)
    }
  })
}

const b64 = (buf) => btoa(String.fromCharCode(...new Uint8Array(buf)))
const unb64 = (s) => Uint8Array.from(atob(s), (c) => c.charCodeAt(0))

export const DeviceKey = {
  async mounted() {
    this.slot = `user:${this.el.dataset.userId}`
    this.handleEvent("device:connect", () => this.connect())
    this.handleEvent("device:sign", ({ message, for: forId }) => this.sign(message, forId || null))
    this.handleEvent("device:unwrap", ({ sealed, aad, for: forId }) => this.unwrap(sealed, aad, forId || null))
    const supported = await this.supported()
    const pair = supported ? await keyStore("readonly", (s) => s.get(this.slot)).catch(() => null) : null
    this.pushEvent("device:status", { supported, public_key: pair ? await this.publicKey(pair) : null })
  },
  async supported() {
    try {
      await crypto.subtle.generateKey({ name: "Ed25519" }, false, ["sign", "verify"])
      return true
    } catch (_) {
      return false
    }
  },
  async publicKey(pair) {
    return b64(await crypto.subtle.exportKey("raw", pair.publicKey))
  },
  async connect() {
    let pair = await keyStore("readonly", (s) => s.get(this.slot)).catch(() => null)
    if (!pair) {
      pair = await crypto.subtle.generateKey({ name: "Ed25519" }, false, ["sign", "verify"])
      await keyStore("readwrite", (s) => s.put(pair, this.slot))
    }
    const box = await this.boxPair()
    this.pushEvent("device:register", {
      public_key: await this.publicKey(pair),
      box_key: await this.publicKey(box)
    })
  },
  async boxPair() {
    const slot = `${this.slot}:box`
    let box = await keyStore("readonly", (s) => s.get(slot)).catch(() => null)
    if (!box) {
      box = await crypto.subtle.generateKey({ name: "X25519" }, false, ["deriveBits"])
      await keyStore("readwrite", (s) => s.put(box, slot))
    }
    return box
  },
  async unwrap(sealed, aad, forId) {
    try {
      const box = await keyStore("readonly", (s) => s.get(`${this.slot}:box`))
      const { openShare } = await import(/* @vite-ignore */ `${WIDGETS}/devicekeys.js`)
      const share = await openShare(box, unb64(sealed), new TextEncoder().encode(aad))
      this.pushEvent("device:share", { share: b64(share), for: forId })
    } catch (_) {
      this.pushEvent("device:share", { share: null, for: forId })
    }
  },
  async sign(message, forId) {
    const pair = await keyStore("readonly", (s) => s.get(this.slot))
    if (!pair) return this.pushEvent("device:signature", { signature: null, for: forId })
    const signature = await crypto.subtle.sign({ name: "Ed25519" }, pair.privateKey, unb64(message))
    this.pushEvent("device:signature", { signature: b64(signature), for: forId })
  }
}

export const VoiceRecorder = {
  mounted() {
    this.button = this.el.querySelector("[data-voice-toggle]")
    this.timer = this.el.querySelector("[data-voice-timer]")
    this.button.addEventListener("click", () => (this.recorder ? this.stop() : this.start()))
  },
  destroyed() { this.release() },
  async start() {
    try {
      this.stream = await navigator.mediaDevices.getUserMedia({ audio: true })
    } catch (_) {
      this.el.dataset.state = "denied"
      return
    }
    const type = ["audio/webm;codecs=opus", "audio/ogg;codecs=opus", "audio/mp4"].find((t) => MediaRecorder.isTypeSupported(t)) || ""
    this.recorder = new MediaRecorder(this.stream, type ? { mimeType: type } : {})
    const chunks = []
    this.recorder.ondataavailable = (e) => e.data.size && chunks.push(e.data)
    this.recorder.onstop = () => {
      const mime = (this.recorder.mimeType || "audio/webm").split(";")[0]
      const ext = { "audio/webm": "webm", "audio/ogg": "ogg", "audio/mp4": "m4a" }[mime] || "webm"
      const file = new File(chunks, `voice.${ext}`, { type: mime })
      this.recorder = null
      this.release()
      this.el.dataset.state = "idle"
      this.upload(this.el.dataset.upload, [file])
    }
    this.recorder.start()
    this.el.dataset.state = "recording"
    const started = Date.now()
    this.tick = setInterval(() => {
      const s = Math.floor((Date.now() - started) / 1000)
      if (this.timer) this.timer.textContent = `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`
      if (s >= 120) this.stop()
    }, 250)
  },
  stop() {
    clearInterval(this.tick)
    if (this.recorder && this.recorder.state !== "inactive") this.recorder.stop()
  },
  release() {
    if (this.stream) this.stream.getTracks().forEach((t) => t.stop())
    this.stream = null
  }
}

export const UiApply = {
  mounted() {
    this.handleEvent("ui:apply", ({ attrs, glow }) => {
      const html = document.documentElement
      for (const [k, v] of Object.entries(attrs)) html.setAttribute(k, v)
      const main = document.getElementById("app-main")
      if (main) main.dataset.glow = glow
    })
  }
}

export const BrokenPictures = {
  mounted() {
    this.onError = (e) => {
      if (e.target.tagName === "IMG") this.apply();
    };
    this.el.addEventListener("error", this.onError, true);
    this.apply();
  },
  updated() {
    this.apply();
  },
  destroyed() {
    this.el.removeEventListener("error", this.onError, true);
  },
  apply() {
    const tiles = [...this.el.querySelectorAll("[data-picture]")];
    let shown = 0;
    for (const tile of tiles) {
      const img = tile.querySelector("img");
      const broken = img && img.complete && img.naturalWidth === 0;
      tile.hidden = broken;
      if (!broken) shown++;
    }
    const none = this.el.querySelector("[data-pictures-none]");
    if (none) none.hidden = tiles.length === 0 || shown > 0;
  },
};

const THUMB_KEY = "basa:photo-size"
export const ThumbSize = {
  mounted() {
    this.size = Number(readStored(THUMB_KEY)) || 80
    this.el.addEventListener("input", (e) => {
      if (!e.target.matches("[data-thumb-size]")) return
      this.size = Number(e.target.value)
      writeStored(THUMB_KEY, String(this.size))
      this.apply()
    })
    this.apply()
  },
  updated() { this.apply() },
  apply() {
    this.el.style.setProperty("--thumb", `${this.size}px`)
    const slider = this.el.querySelector("[data-thumb-size]")
    if (slider && Number(slider.value) !== this.size) slider.value = this.size
  }
}

function readStored(key) {
  try { return localStorage.getItem(key) } catch (_) { return null }
}
function writeStored(key, value) {
  try { localStorage.setItem(key, value) } catch (_) {  }
}

export const PagePicker = {
  mounted() {
    this.frame = this.el.querySelector("iframe")
    this.layer = this.el.querySelector("[data-picker-layer]")
    this.frame.addEventListener("load", () => this.styled = false)

    const at = (x, y) => {
      const doc = this.frame.contentDocument
      if (!doc) return null
      this.style(doc)
      const box = this.frame.getBoundingClientRect()
      return doc.elementFromPoint(x - box.left, y - box.top)
    }

    let hovered = null
    const hover = (el) => {
      if (hovered === el) return
      if (hovered) hovered.removeAttribute("data-basa-hover")
      hovered = el
      if (el) el.setAttribute("data-basa-hover", "")
    }

    this.layer.addEventListener("mousemove", (e) => hover(at(e.clientX, e.clientY)))
    this.layer.addEventListener("mouseleave", () => hover(null))
    this.layer.addEventListener("click", (e) => {
      const el = at(e.clientX, e.clientY)
      if (el) { hover(el); this.pushEvent("picked", describe(el)) }
    })
    this.layer.addEventListener("wheel", (e) => {
      e.preventDefault()
      this.frame.contentWindow && this.frame.contentWindow.scrollBy(e.deltaX, e.deltaY)
    }, { passive: false })

    let last = null
    this.layer.addEventListener("touchstart", (e) => { last = e.touches[0] }, { passive: true })
    this.layer.addEventListener("touchmove", (e) => {
      const t = e.touches[0]
      if (last && this.frame.contentWindow) this.frame.contentWindow.scrollBy(last.clientX - t.clientX, last.clientY - t.clientY)
      last = t
      e.preventDefault()
    }, { passive: false })
  },

  style(doc) {
    if (this.styled || !doc.documentElement) return
    this.styled = true
    const accent = getComputedStyle(document.documentElement).getPropertyValue("--color-primary-light").trim() || "currentColor"
    const style = doc.createElement("style")
    style.textContent = `[data-basa-hover]{outline:2px solid ${accent} !important;outline-offset:1px}`
    ;(doc.head || doc.documentElement).appendChild(style)
  }
}

function describe(el) {
  const chain = []
  for (let n = el; n && n.nodeType === 1; n = n.parentElement) {
    let nth = 1
    for (let s = n.previousElementSibling; s; s = s.previousElementSibling) if (s.localName === n.localName) nth++
    const attrs = {}
    if (n.getAttribute("itemprop")) attrs.itemprop = n.getAttribute("itemprop")
    chain.unshift({ tag: n.localName, id: n.id || null, classes: [...n.classList], attrs, nth })
  }
  const parts = []
  const walker = el.ownerDocument.createTreeWalker(el, NodeFilter.SHOW_TEXT)
  while (walker.nextNode()) parts.push(walker.currentNode.nodeValue)
  const text = parts.join(" ").replace(/\s+/g, " ").trim().slice(0, 1000)
  const src = el.getAttribute("data-src") || el.getAttribute("data-lazy-src") || el.getAttribute("data-original") || el.getAttribute("src")
  return { chain, text, src }
}
