alias Basa.Catalog.Category

categories = [
  %{
    slug: "microphone",
    kind: :equipment,
    parent_slug: "music",
    name: %{"en" => "Microphone", "uk" => "Мікрофон", "de" => "Mikrofon", "fr" => "Microphone"},
    attr_schema: %{
      "type" => "object",
      "x-order" => ["mic_type", "polar_pattern", "phantom_power", "connector"],
      "properties" => %{
        "mic_type" => %{
          "title" => "Type",
          "type" => "string",
          "enum" => ["dynamic", "condenser", "ribbon", "usb"]
        },
        "polar_pattern" => %{
          "title" => "Polar pattern",
          "type" => "string",
          "enum" => ["cardioid", "supercardioid", "omni", "figure-8", "multi"]
        },
        "phantom_power" => %{"title" => "Needs phantom power", "type" => "boolean"},
        "connector" => %{
          "title" => "Connector",
          "type" => "string",
          "enum" => ["XLR", "USB", "jack 6.3", "mini-jack"]
        }
      }
    }
  },
  %{
    slug: "studio-monitor",
    kind: :equipment,
    parent_slug: "music",
    name: %{
      "en" => "Studio monitor",
      "uk" => "Студійний монітор",
      "de" => "Studiomonitor",
      "fr" => "Moniteur de studio"
    },
    attr_schema: %{
      "type" => "object",
      "x-order" => ["woofer_inch", "power_w", "active", "pair"],
      "properties" => %{
        "woofer_inch" => %{
          "title" => "Woofer size",
          "type" => "number",
          "minimum" => 3,
          "maximum" => 15,
          "x-unit" => "inch"
        },
        "power_w" => %{"title" => "Power", "type" => "integer", "minimum" => 1, "x-unit" => "W"},
        "active" => %{"title" => "Active (powered)", "type" => "boolean"},
        "pair" => %{"title" => "Sold as a pair", "type" => "boolean"}
      }
    }
  },
  %{
    slug: "mixing-console",
    kind: :equipment,
    parent_slug: "music",
    name: %{
      "en" => "Mixing console",
      "uk" => "Мікшерний пульт",
      "de" => "Mischpult",
      "fr" => "Console de mixage"
    },
    attr_schema: %{
      "type" => "object",
      "required" => ["channels"],
      "x-order" => ["channels", "digital", "usb_interface"],
      "properties" => %{
        "channels" => %{
          "title" => "Channels",
          "type" => "integer",
          "minimum" => 1,
          "maximum" => 128
        },
        "digital" => %{"title" => "Digital", "type" => "boolean"},
        "usb_interface" => %{"title" => "USB audio interface", "type" => "boolean"}
      }
    }
  },
  %{
    slug: "instrument",
    kind: :equipment,
    parent_slug: "music",
    name: %{
      "en" => "Instrument",
      "uk" => "Інструмент",
      "de" => "Instrument",
      "fr" => "Instrument"
    },
    attr_schema: %{
      "type" => "object",
      "x-order" => ["instrument_type", "left_handed"],
      "properties" => %{
        "instrument_type" => %{
          "title" => "Instrument",
          "type" => "string",
          "enum" => ["guitar", "bass", "keyboard", "drums", "synth", "other"]
        },
        "left_handed" => %{"title" => "Left-handed", "type" => "boolean"}
      }
    }
  },
  %{
    slug: "power-tool",
    kind: :equipment,
    parent_slug: "tools",
    name: %{
      "en" => "Power tool",
      "uk" => "Електроінструмент",
      "de" => "Elektrowerkzeug",
      "fr" => "Outil électrique"
    },
    attr_schema: %{
      "type" => "object",
      "x-order" => ["tool_type", "power_w", "cordless", "battery_count"],
      "properties" => %{
        "tool_type" => %{
          "title" => "Tool",
          "type" => "string",
          "enum" => [
            "drill",
            "hammer drill",
            "angle grinder",
            "circular saw",
            "jigsaw",
            "sander",
            "other"
          ]
        },
        "power_w" => %{"title" => "Power", "type" => "integer", "minimum" => 1, "x-unit" => "W"},
        "cordless" => %{"title" => "Cordless", "type" => "boolean"},
        "battery_count" => %{
          "title" => "Batteries included",
          "type" => "integer",
          "minimum" => 0,
          "maximum" => 10
        }
      }
    }
  },
  %{
    slug: "clothing",
    kind: :equipment,
    parent_slug: "clothing",
    name: %{"en" => "Clothing", "uk" => "Одяг", "de" => "Kleidung", "fr" => "Vêtements"},
    attr_schema: %{
      "type" => "object",
      "required" => ["size"],
      "x-order" => ["garment", "size", "gender", "color"],
      "properties" => %{
        "garment" => %{
          "title" => "Garment",
          "type" => "string",
          "enum" => ["suit", "dress", "costume", "jacket", "workwear", "other"]
        },
        "size" => %{
          "title" => "Size",
          "type" => "string",
          "enum" => ["XS", "S", "M", "L", "XL", "XXL"]
        },
        "gender" => %{
          "title" => "Cut",
          "type" => "string",
          "enum" => ["women", "men", "unisex", "kids"]
        },
        "color" => %{"title" => "Color", "type" => "string", "maxLength" => 40}
      }
    }
  },
  %{
    slug: "recording-studio",
    kind: :venue,
    parent_slug: "music",
    name: %{
      "en" => "Recording studio",
      "uk" => "Студія звукозапису",
      "de" => "Tonstudio",
      "fr" => "Studio d'enregistrement"
    },
    attr_schema: %{
      "type" => "object",
      "x-order" => ["area_m2", "vocal_booth", "soundproofed", "parking"],
      "properties" => %{
        "area_m2" => %{"title" => "Area", "type" => "number", "minimum" => 1, "x-unit" => "m²"},
        "vocal_booth" => %{"title" => "Vocal booth", "type" => "boolean"},
        "soundproofed" => %{"title" => "Soundproofed", "type" => "boolean"},
        "parking" => %{"title" => "Parking", "type" => "boolean"}
      }
    }
  },
  %{
    slug: "rehearsal-room",
    kind: :venue,
    parent_slug: "music",
    name: %{
      "en" => "Rehearsal room",
      "uk" => "Репетиційна база",
      "de" => "Proberaum",
      "fr" => "Salle de répétition"
    },
    attr_schema: %{
      "type" => "object",
      "x-order" => ["area_m2", "backline"],
      "properties" => %{
        "area_m2" => %{"title" => "Area", "type" => "number", "minimum" => 1, "x-unit" => "m²"},
        "backline" => %{"title" => "Backline included", "type" => "boolean"}
      }
    }
  },
  %{
    slug: "workshop",
    kind: :venue,
    parent_slug: "tools",
    name: %{"en" => "Workshop", "uk" => "Майстерня", "de" => "Werkstatt", "fr" => "Atelier"},
    attr_schema: %{
      "type" => "object",
      "x-order" => ["area_m2", "three_phase_power"],
      "properties" => %{
        "area_m2" => %{"title" => "Area", "type" => "number", "minimum" => 1, "x-unit" => "m²"},
        "three_phase_power" => %{"title" => "Three-phase power", "type" => "boolean"}
      }
    }
  }
]

t = fn uk, de, fr -> %{"uk" => uk, "de" => de, "fr" => fr} end

field_titles = %{
  "mic_type" => t.("Тип", "Typ", "Type"),
  "polar_pattern" => t.("Діаграма спрямованості", "Richtcharakteristik", "Directivité"),
  "phantom_power" =>
    t.("Потрібне фантомне живлення", "Benötigt Phantomspeisung", "Alimentation fantôme requise"),
  "connector" => t.("Роз'єм", "Anschluss", "Connecteur"),
  "woofer_inch" => t.("Розмір НЧ-динаміка", "Tieftöner-Größe", "Taille du woofer"),
  "power_w" => t.("Потужність", "Leistung", "Puissance"),
  "active" => t.("Активний (з живленням)", "Aktiv (mit Verstärker)", "Actif (alimenté)"),
  "pair" => t.("Продається парою", "Als Paar", "Vendu par paire"),
  "channels" => t.("Канали", "Kanäle", "Canaux"),
  "digital" => t.("Цифровий", "Digital", "Numérique"),
  "usb_interface" => t.("USB-аудіоінтерфейс", "USB-Audiointerface", "Interface audio USB"),
  "instrument_type" => t.("Інструмент", "Instrument", "Instrument"),
  "left_handed" => t.("Для лівші", "Linkshänder", "Gaucher"),
  "tool_type" => t.("Інструмент", "Werkzeug", "Outil"),
  "cordless" => t.("Акумуляторний", "Akku", "Sans fil"),
  "battery_count" => t.("Акумуляторів у комплекті", "Akkus inklusive", "Batteries incluses"),
  "garment" => t.("Одяг", "Kleidungsstück", "Vêtement"),
  "size" => t.("Розмір", "Größe", "Taille"),
  "gender" => t.("Крій", "Schnitt", "Coupe"),
  "color" => t.("Колір", "Farbe", "Couleur"),
  "area_m2" => t.("Площа", "Fläche", "Surface"),
  "vocal_booth" => t.("Вокальна кабіна", "Gesangskabine", "Cabine vocale"),
  "soundproofed" => t.("Звукоізоляція", "Schallisoliert", "Insonorisé"),
  "parking" => t.("Парковка", "Parkplatz", "Parking"),
  "backline" => t.("Бекляйн включено", "Backline inklusive", "Backline inclus"),
  "three_phase_power" => t.("Трифазне живлення", "Drehstrom", "Courant triphasé")
}

option_titles = %{
  "dynamic" => t.("динамічний", "dynamisch", "dynamique"),
  "condenser" => t.("конденсаторний", "Kondensator", "statique"),
  "ribbon" => t.("стрічковий", "Bändchen", "à ruban"),
  "usb" => t.("USB", "USB", "USB"),
  "cardioid" => t.("кардіоїда", "Niere", "cardioïde"),
  "supercardioid" => t.("суперкардіоїда", "Superniere", "supercardioïde"),
  "omni" => t.("кругова", "Kugel", "omnidirectionnel"),
  "figure-8" => t.("вісімка", "Acht", "bidirectionnel"),
  "multi" => t.("перемикана", "umschaltbar", "multi-directivité"),
  "jack 6.3" => t.("джек 6,3", "Klinke 6,3", "jack 6,35"),
  "mini-jack" => t.("міні-джек", "Miniklinke", "mini-jack"),
  "guitar" => t.("гітара", "Gitarre", "guitare"),
  "bass" => t.("бас-гітара", "Bass", "basse"),
  "keyboard" => t.("клавішні", "Keyboard", "clavier"),
  "drums" => t.("ударні", "Schlagzeug", "batterie"),
  "synth" => t.("синтезатор", "Synthesizer", "synthétiseur"),
  "other" => t.("інше", "Sonstiges", "autre"),
  "drill" => t.("дриль", "Bohrmaschine", "perceuse"),
  "hammer drill" => t.("перфоратор", "Bohrhammer", "perforateur"),
  "angle grinder" => t.("болгарка", "Winkelschleifer", "meuleuse d'angle"),
  "circular saw" => t.("циркулярна пила", "Kreissäge", "scie circulaire"),
  "jigsaw" => t.("лобзик", "Stichsäge", "scie sauteuse"),
  "sander" => t.("шліфмашина", "Schleifer", "ponceuse"),
  "suit" => t.("костюм", "Anzug", "costume"),
  "dress" => t.("сукня", "Kleid", "robe"),
  "costume" => t.("сценічний костюм", "Kostüm", "déguisement"),
  "jacket" => t.("куртка", "Jacke", "veste"),
  "workwear" => t.("робочий одяг", "Arbeitskleidung", "vêtements de travail"),
  "women" => t.("жіночий", "Damen", "femme"),
  "men" => t.("чоловічий", "Herren", "homme"),
  "unisex" => t.("унісекс", "Unisex", "unisexe"),
  "kids" => t.("дитячий", "Kinder", "enfant")
}

more = fn es, it, pl, ro, tr -> %{"es" => es, "it" => it, "pl" => pl, "ro" => ro, "tr" => tr} end

category_more = %{
  "Microphone" => more.("Micrófono", "Microfono", "Mikrofon", "Microfon", "Mikrofon"),
  "Studio monitor" =>
    more.(
      "Monitor de estudio",
      "Monitor da studio",
      "Monitor studyjny",
      "Monitor de studio",
      "Stüdyo monitörü"
    ),
  "Mixing console" => more.("Mesa de mezclas", "Mixer", "Konsola mikserska", "Mixer", "Mikser"),
  "Instrument" => more.("Instrumento", "Strumento", "Instrument", "Instrument", "Enstrüman"),
  "Power tool" =>
    more.(
      "Herramienta eléctrica",
      "Elettroutensile",
      "Elektronarzędzie",
      "Unealtă electrică",
      "Elektrikli alet"
    ),
  "Clothing" => more.("Ropa", "Abbigliamento", "Odzież", "Îmbrăcăminte", "Giyim"),
  "Recording studio" =>
    more.(
      "Estudio de grabación",
      "Studio di registrazione",
      "Studio nagrań",
      "Studio de înregistrări",
      "Kayıt stüdyosu"
    ),
  "Rehearsal room" =>
    more.("Sala de ensayo", "Sala prove", "Sala prób", "Sală de repetiții", "Prova odası"),
  "Workshop" => more.("Taller", "Laboratorio", "Warsztat", "Atelier", "Atölye")
}

field_more = %{
  "mic_type" => more.("Tipo", "Tipo", "Typ", "Tip", "Tür"),
  "polar_pattern" =>
    more.(
      "Patrón polar",
      "Diagramma polare",
      "Charakterystyka kierunkowa",
      "Caracteristică polară",
      "Yön karakteristiği"
    ),
  "phantom_power" =>
    more.(
      "Requiere alimentación phantom",
      "Richiede alimentazione phantom",
      "Wymaga zasilania phantom",
      "Necesită alimentare phantom",
      "Fantom besleme gerekir"
    ),
  "connector" => more.("Conector", "Connettore", "Złącze", "Conector", "Konnektör"),
  "woofer_inch" =>
    more.(
      "Tamaño del woofer",
      "Dimensione del woofer",
      "Rozmiar głośnika niskotonowego",
      "Dimensiunea woofer-ului",
      "Woofer boyutu"
    ),
  "power_w" => more.("Potencia", "Potenza", "Moc", "Putere", "Güç"),
  "active" =>
    more.(
      "Activo (autoamplificado)",
      "Attivo (amplificato)",
      "Aktywny (z zasilaniem)",
      "Activ (amplificat)",
      "Aktif (güç beslemeli)"
    ),
  "pair" =>
    more.(
      "Se vende por pares",
      "Venduto in coppia",
      "Sprzedawane w parze",
      "Vândut în pereche",
      "Çift olarak"
    ),
  "channels" => more.("Canales", "Canali", "Kanały", "Canale", "Kanallar"),
  "digital" => more.("Digital", "Digitale", "Cyfrowy", "Digital", "Dijital"),
  "usb_interface" =>
    more.(
      "Interfaz de audio USB",
      "Interfaccia audio USB",
      "Interfejs audio USB",
      "Interfață audio USB",
      "USB ses arabirimi"
    ),
  "instrument_type" => more.("Instrumento", "Strumento", "Instrument", "Instrument", "Enstrüman"),
  "left_handed" =>
    more.("Para zurdos", "Per mancini", "Dla leworęcznych", "Pentru stângaci", "Solak"),
  "tool_type" => more.("Herramienta", "Utensile", "Narzędzie", "Unealtă", "Alet"),
  "cordless" => more.("Inalámbrica", "A batteria", "Akumulatorowe", "Cu acumulator", "Akülü"),
  "battery_count" =>
    more.(
      "Baterías incluidas",
      "Batterie incluse",
      "Akumulatory w zestawie",
      "Acumulatori incluși",
      "Dahil aküler"
    ),
  "garment" => more.("Prenda", "Capo", "Ubranie", "Articol vestimentar", "Giysi"),
  "size" => more.("Talla", "Taglia", "Rozmiar", "Mărime", "Beden"),
  "gender" => more.("Corte", "Taglio", "Krój", "Croială", "Kesim"),
  "color" => more.("Color", "Colore", "Kolor", "Culoare", "Renk"),
  "area_m2" => more.("Superficie", "Superficie", "Powierzchnia", "Suprafață", "Alan"),
  "vocal_booth" =>
    more.("Cabina vocal", "Cabina vocale", "Kabina wokalna", "Cabină vocală", "Vokal kabini"),
  "soundproofed" =>
    more.("Insonorizado", "Insonorizzato", "Wyciszony", "Izolat fonic", "Ses yalıtımlı"),
  "parking" => more.("Aparcamiento", "Parcheggio", "Parking", "Parcare", "Otopark"),
  "backline" =>
    more.(
      "Backline incluido",
      "Backline incluso",
      "Backline w zestawie",
      "Backline inclus",
      "Backline dahil"
    ),
  "three_phase_power" =>
    more.(
      "Corriente trifásica",
      "Corrente trifase",
      "Prąd trójfazowy",
      "Curent trifazic",
      "Üç fazlı elektrik"
    )
}

option_more = %{
  "dynamic" => more.("dinámico", "dinamico", "dynamiczny", "dinamic", "dinamik"),
  "condenser" =>
    more.("de condensador", "a condensatore", "pojemnościowy", "cu condensator", "kondansatör"),
  "ribbon" => more.("de cinta", "a nastro", "wstęgowy", "cu bandă", "şerit"),
  "usb" => more.("USB", "USB", "USB", "USB", "USB"),
  "cardioid" => more.("cardioide", "cardioide", "kardioida", "cardioid", "kardioid"),
  "supercardioid" =>
    more.("supercardioide", "supercardioide", "superkardioida", "supercardioid", "süperkardioid"),
  "omni" =>
    more.("omnidireccional", "omnidirezionale", "dookólna", "omnidirecțional", "çok yönlü"),
  "figure-8" => more.("bidireccional", "a figura 8", "ósemkowa", "bidirecțional", "sekiz şekli"),
  "multi" => more.("conmutable", "commutabile", "przełączana", "comutabil", "değiştirilebilir"),
  "jack 6.3" => more.("jack 6,3", "jack 6,3", "jack 6,3", "jack 6,3", "jak 6,3"),
  "mini-jack" => more.("minijack", "minijack", "mini-jack", "mini-jack", "mini jak"),
  "guitar" => more.("guitarra", "chitarra", "gitara", "chitară", "gitar"),
  "bass" => more.("bajo", "basso", "gitara basowa", "bas", "bas gitar"),
  "keyboard" => more.("teclado", "tastiera", "klawisze", "clape", "klavye"),
  "drums" => more.("batería", "batteria", "perkusja", "tobe", "davul"),
  "synth" => more.("sintetizador", "sintetizzatore", "syntezator", "sintetizator", "synthesizer"),
  "other" => more.("otro", "altro", "inne", "altceva", "diğer"),
  "drill" => more.("taladro", "trapano", "wiertarka", "bormașină", "matkap"),
  "hammer drill" =>
    more.(
      "martillo perforador",
      "tassellatore",
      "młotowiertarka",
      "rotopercutor",
      "kırıcı delici"
    ),
  "angle grinder" =>
    more.("amoladora", "smerigliatrice", "szlifierka kątowa", "polizor unghiular", "avuç taşlama"),
  "circular saw" =>
    more.(
      "sierra circular",
      "sega circolare",
      "piła tarczowa",
      "fierăstrău circular",
      "daire testere"
    ),
  "jigsaw" =>
    more.(
      "sierra de calar",
      "seghetto alternativo",
      "wyrzynarka",
      "fierăstrău pendular",
      "dekupaj testere"
    ),
  "sander" => more.("lijadora", "levigatrice", "szlifierka", "șlefuitor", "zımpara makinesi"),
  "suit" => more.("traje", "abito", "garnitur", "costum", "takım elbise"),
  "dress" => more.("vestido", "vestito", "sukienka", "rochie", "elbise"),
  "costume" => more.("disfraz", "costume di scena", "kostium", "costum de scenă", "kostüm"),
  "jacket" => more.("chaqueta", "giacca", "kurtka", "geacă", "ceket"),
  "workwear" =>
    more.(
      "ropa de trabajo",
      "abbigliamento da lavoro",
      "odzież robocza",
      "îmbrăcăminte de lucru",
      "iş kıyafeti"
    ),
  "women" => more.("mujer", "donna", "damski", "femei", "kadın"),
  "men" => more.("hombre", "uomo", "męski", "bărbați", "erkek"),
  "unisex" => more.("unisex", "unisex", "unisex", "unisex", "unisex"),
  "kids" => more.("infantil", "bambino", "dziecięcy", "copii", "çocuk")
}

deep_merge = fn base, extra -> Map.merge(base, extra, fn _key, a, b -> Map.merge(a, b) end) end
field_titles = deep_merge.(field_titles, field_more)
option_titles = deep_merge.(option_titles, option_more)

categories =
  Enum.map(categories, fn c ->
    Map.update!(c, :name, &Map.merge(&1, category_more[&1["en"]] || %{}))
  end)

title_locales = Basa.I18n.codes() -- ["en"]

localize = fn schema ->
  props =
    Map.new(Map.get(schema, "properties", %{}), fn {name, prop} ->
      prop =
        prop
        |> then(&if(field_titles[name], do: Map.put(&1, "x-title", field_titles[name]), else: &1))
        |> then(fn prop ->
          case prop["enum"] do
            nil ->
              prop

            values ->
              titles =
                for loc <- title_locales, into: %{} do
                  {loc, Map.new(values, &{&1, get_in(option_titles, [&1, loc]) || &1})}
                end

              Map.put(prop, "x-enum-titles", titles)
          end
        end)

      {name, prop}
    end)

  Map.put(schema, "properties", props)
end

categories
|> Enum.with_index()
|> Enum.each(fn {attrs, i} ->
  attrs = attrs |> Map.put(:position, i) |> Map.update!(:attr_schema, localize)
  Ash.Seed.upsert!(Category, attrs, identity: :unique_slug)
end)

IO.puts("Seeded #{length(categories)} categories")
