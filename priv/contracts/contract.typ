// BASA contract layout (Basa.Witness.Contract). All words come translated in
// sys.inputs.data (JSON); this file only lays them out: one column, or two
// side by side when the parties speak different languages. Rendered with
// --ignore-system-fonts and a fixed --creation-timestamp, so the same data
// always gives the same PDF bytes.

#let d = json(bytes(sys.inputs.data))
#let texts = d.texts
#let two = texts.len() == 2

#set document(title: texts.at(0).title, author: "BASA")
#set page(
  paper: "a4",
  margin: (x: 18mm, top: 20mm, bottom: 22mm),
  footer: context [
    #set text(size: 7.5pt, fill: luma(110))
    #if d.draft != none [#d.draft #h(1fr)]
    #counter(page).display("1 / 1", both: true)
  ],
)
#set text(font: "Libertinus Serif", size: if two { 9.5pt } else { 10.5pt })
#set par(justify: true, leading: 0.55em, spacing: 0.75em)

#let column(t, lang, body) = text(lang: lang, body(t))

#let side(i, body) = if two {
  grid(
    columns: (1fr, 1fr),
    column-gutter: 16pt,
    column(texts.at(0), d.languages.at(0), body),
    column(texts.at(1), d.languages.at(1), body),
  )
} else {
  column(texts.at(0), d.languages.at(0), body)
}

// Title and the contract's number, date and place
#side(0, t => [
  #align(center)[
    #text(size: 15pt, weight: "bold")[#t.title] \
    #v(2pt)
    #text(size: 9pt)[#t.meta]
  ]
])
#v(10pt)

#for (i, _) in texts.at(0).sections.enumerate() {
  side(i, t => {
    let s = t.sections.at(i)
    block(breakable: true, below: 9pt)[
      #text(weight: "bold")[#(i + 1). #s.heading]
      #for p in s.paras [#par(p)]
      #if s.items.len() > 0 [
        #list(..s.items)
      ]
    ]
  })
}
