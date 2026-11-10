const PREFIX = "basa:draft:"
const MAX_AGE = 24 * 60 * 60 * 1000
const MAX_SIZE = 100_000
const SKIP_TYPES = new Set(["password", "file", "hidden", "submit", "button", "reset", "image"])

const store = {
  get(key) {
    try { return JSON.parse(sessionStorage.getItem(key) || "null") } catch { return null }
  },
  set(key, value) {
    try { sessionStorage.setItem(key, JSON.stringify(value)) } catch {  }
  },
  remove(key) {
    try { sessionStorage.removeItem(key) } catch {  }
  },
}

function pageKey() {
  const url = new URL(window.location.href)
  url.searchParams.delete("locale")
  return url.pathname + url.search
}

const draftKey = (form) => `${PREFIX}${pageKey()}#${form.id}`

const keepable = (form) =>
  form.id && !form.hasAttribute("data-no-draft") && !form.closest("[data-no-draft]")

function fields(form) {
  const counts = {}
  const out = []
  for (const el of form.elements) {
    if (!el.name || el.disabled || SKIP_TYPES.has(el.type)) continue
    if (el.name.startsWith("_") || el.name.includes("[_unused_") || el.dataset.noDraft !== undefined) continue
    if ((el.autocomplete || "").startsWith("cc-")) continue
    const n = counts[el.name] = (counts[el.name] ?? -1) + 1
    out.push([`${el.name}#${n}`, el])
  }
  return out
}

function read(el) {
  if (el.type === "checkbox" || el.type === "radio") return el.checked
  if (el.type === "select-multiple") return [...el.selectedOptions].map((o) => o.value)
  return el.value
}

function write(el, value) {
  if (el.type === "checkbox" || el.type === "radio") el.checked = value === true
  else if (el.type === "select-multiple") for (const o of el.options) o.selected = value.includes(o.value)
  else el.value = value
}

const snapshot = (form) => Object.fromEntries(fields(form).map(([k, el]) => [k, read(el)]))
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b)

const bases = new WeakMap()

function save(form) {
  if (!keepable(form)) return
  const base = bases.get(form)
  if (!base) return
  const values = snapshot(form)
  const key = draftKey(form)
  if (same(values, base)) return store.remove(key)
  const draft = { base, values, at: Date.now() }
  if (JSON.stringify(draft).length > MAX_SIZE) return store.remove(key)
  store.set(key, draft)
}

function restore(form) {
  if (!keepable(form) || bases.has(form)) return
  const base = snapshot(form)
  bases.set(form, base)
  const key = draftKey(form)
  const draft = store.get(key)
  if (!draft) return
  if (Date.now() - draft.at > MAX_AGE || !same(draft.base, base)) return store.remove(key)

  let changed = null
  for (const [k, el] of fields(form)) {
    if (!(k in draft.values) || same(read(el), draft.values[k])) continue
    write(el, draft.values[k])
    changed = changed || el
  }
  if (changed) changed.dispatchEvent(new Event("input", { bubbles: true }))
}

const restoreAll = () => document.querySelectorAll("form[id]").forEach(restore)

function dropLocaleParam() {
  const url = new URL(window.location.href)
  if (!url.searchParams.has("locale")) return
  url.searchParams.delete("locale")
  window.history.replaceState(window.history.state, "", url.pathname + url.search + url.hash)
}

const keptKey = (key) => `basa:keep:${key}`

export const KeepState = {
  mounted() {
    const key = this.el.dataset.key
    const saved = store.get(keptKey(key))
    if (saved && saved !== this.el.dataset.token) {
      this.pushEvent("keep:restore", { token: saved }, (reply) => {
        if (!reply || !reply.ok) store.set(keptKey(key), this.el.dataset.token)
      })
    } else {
      store.set(keptKey(key), this.el.dataset.token)
    }
  },
  updated() {
    store.set(keptKey(this.el.dataset.key), this.el.dataset.token)
  },
}

export function startKeepState() {
  window.addEventListener("phx:keep:forget", ({ detail }) => store.remove(keptKey(detail.key)))

  dropLocaleParam()

  document.addEventListener("focusin", (e) => e.target.form && restore(e.target.form))
  document.addEventListener("input", (e) => e.target.form && save(e.target.form))
  document.addEventListener("change", (e) => e.target.form && save(e.target.form))
  document.addEventListener("submit", (e) => e.target.id && store.remove(draftKey(e.target)), true)

  document.addEventListener("click", (e) => {
    const link = e.target.closest && e.target.closest("a[data-locale]")
    if (!link || e.metaKey || e.ctrlKey || e.shiftKey || e.button !== 0) return
    e.preventDefault()
    document.querySelectorAll("form[id]").forEach(save)
    const url = new URL(window.location.href)
    url.searchParams.set("locale", link.dataset.locale)
    window.location.assign(url.toString())
  })

  window.addEventListener("phx:page-loading-stop", () => requestAnimationFrame(restoreAll))
  if (!document.querySelector("[data-phx-main]")) {
    if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", restoreAll)
    else restoreAll()
  }
}
