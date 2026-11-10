const CARDS = "[role=region]:not(.fixed, .scroll-area-wrapper, [role=region] [role=region])"
const REACH = 120
const PALETTE = [
  [0, 204, 255],
  [0, 212, 0],
  [255, 212, 42],
  [255, 127, 42],
]

const colourAt = (t) => {
  const pos = Math.min(Math.max(t, 0), 1) * (PALETTE.length - 1)
  const i = Math.min(Math.floor(pos), PALETTE.length - 2)
  const f = pos - i
  return PALETTE[i].map((c, k) => Math.round(c + (PALETTE[i + 1][k] - c) * f)).join(" ")
}

export function installCardGlow() {
  const capable = window.matchMedia("(hover: hover) and (pointer: fine)")
  const reduced = window.matchMedia("(prefers-reduced-motion: reduce)")
  let pointer = null
  let frame = null
  let lit = new Set()

  const enabled = (main) =>
    main && main.dataset.glow !== "off" && capable.matches && !reduced.matches

  const clear = () => {
    lit.forEach((el) => el.style.setProperty("--glow-on", "0"))
    lit = new Set()
  }

  const update = () => {
    frame = null
    const main = document.getElementById("app-main")
    if (!pointer || !enabled(main)) return clear()

    const { x, y } = pointer
    main.style.setProperty("--glow-rgb", colourAt(x / window.innerWidth))
    const now = new Set()

    main.querySelectorAll(CARDS).forEach((el) => {
      const r = el.getBoundingClientRect()
      const near =
        x > r.left - REACH && x < r.right + REACH && y > r.top - REACH && y < r.bottom + REACH
      if (!near) return
      el.style.setProperty("--gx", `${(x - r.left).toFixed(0)}px`)
      el.style.setProperty("--gy", `${(y - r.top).toFixed(0)}px`)
      el.style.setProperty("--glow-on", "1")
      now.add(el)
    })

    lit.forEach((el) => now.has(el) || el.style.setProperty("--glow-on", "0"))
    lit = now
  }

  const schedule = () => {
    if (frame === null) frame = window.requestAnimationFrame(update)
  }

  document.addEventListener("pointermove", (e) => {
    if (e.pointerType !== "mouse" && e.pointerType !== "pen") return
    pointer = { x: e.clientX, y: e.clientY }
    schedule()
  }, { passive: true })

  window.addEventListener("scroll", schedule, { passive: true, capture: true })
  document.addEventListener("mouseout", (e) => {
    if (!e.relatedTarget) { pointer = null; schedule() }
  })
  window.addEventListener("phx:page-loading-stop", schedule)
}
