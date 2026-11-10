defmodule Basa.Witness.Contract do
  use Gettext, backend: BasaWeb.Gettext

  require Ash.Query

  alias Basa.Witness.{Party, Store, Transaction}

  @templates ~w(lease-ua@1 lease-eu@1 sale-ua@1 sale-eu@1)
  @draft true

  def attach(%Transaction{} = tx, actor \\ nil) do
    with {:ok, pdf} <- render(tx), do: Store.add(tx, :contract, "application/pdf", pdf, actor)
  end

  def render(%Transaction{} = tx) do
    with :ok <- known_template(tx.template),
         {:ok, data} <- data(tx) do
      typst(data, DateTime.to_unix(tx.inserted_at))
    end
  end

  def data(%Transaction{} = tx) do
    tx =
      Ash.load!(tx, [booking: [lot: [:room, basket: [:items, :attendants]]]], authorize?: false)

    parties =
      Party
      |> Ash.Query.filter(transaction_id == ^tx.id)
      |> Ash.Query.load(:user)
      |> Ash.read!(authorize?: false)
      |> Map.new(&{&1.role, &1})

    languages = Enum.map(tx.languages, &to_string/1)

    texts =
      for lang <- languages do
        Gettext.with_locale(BasaWeb.Gettext, lang, fn -> texts(tx, parties, languages) end)
      end

    {:ok,
     %{
       languages: languages,
       texts: texts,
       draft:
         if(@draft,
           do:
             Enum.map_join(languages, " / ", fn lang ->
               Gettext.with_locale(BasaWeb.Gettext, lang, fn -> draft_notice() end)
             end)
         )
     }}
  end

  defp texts(tx, parties, languages) do
    booking = tx.booking
    lot = booking.lot
    room = lot.room
    tz = lot.timezone
    number = tx.id |> String.slice(0, 8) |> String.upcase()

    sections =
      [
        section(dgettext("contracts", "Parties"), [
          dgettext("contracts", "Offeror: %{name} (BASA user %{id}).",
            name: name(parties.offeror),
            id: parties.offeror.user_id
          ),
          dgettext("contracts", "Acceptor: %{name} (BASA user %{id}).",
            name: name(parties.acceptor),
            id: parties.acceptor.user_id
          )
        ]),
        deal_sections(tx, booking, lot, room, tz),
        section(dgettext("contracts", "Evidence"), [
          dgettext(
            "contracts",
            "BASA keeps the evidence package of this contract: this document, photos, voice recordings and other files the parties add. Its BASA-HASH identifies it."
          ),
          dgettext(
            "contracts",
            "The files are encrypted with a key split between the offeror, the acceptor and BASA; any two of them can open the files. BASA also holds a recovery key, used only on a court order or another formal lawful request, or when the parties cannot act; every use is logged."
          ),
          dgettext(
            "contracts",
            "BASA provides reliable information, verified cryptographically and procedurally, to the witness, who is a party to this contract. BASA itself is not a party to this contract."
          )
        ]),
        section(dgettext("contracts", "Personal data"), [
          dgettext(
            "contracts",
            "Each party agrees that BASA stores their voice recordings and photos in the evidence package to identify them as a party to this contract. The files are kept for the period in BASA's terms and opened only as described above."
          )
        ]),
        tx.consumer &&
          section(dgettext("contracts", "Consumer rights"), [consumer_clause(tx.jurisdiction)]),
        section(dgettext("contracts", "Governing law and disputes"), [
          law_clause(tx.jurisdiction),
          dgettext(
            "contracts",
            "The parties first try to settle any dispute amicably; otherwise a competent court decides."
          )
        ]),
        length(languages) > 1 &&
          section(dgettext("contracts", "Languages"), [
            dgettext(
              "contracts",
              "This contract is made in these languages: %{languages}. If the versions differ, the version in this language prevails: %{primary}.",
              languages: Enum.map_join(languages, ", ", &language_name/1),
              primary: language_name(hd(languages))
            )
          ]),
        section(dgettext("contracts", "Signing"), [
          dgettext(
            "contracts",
            "Each party signs electronically on their own device, by signing the BASA-HASH of the evidence package that includes this document."
          )
        ])
      ]
      |> List.flatten()
      |> Enum.filter(& &1)

    %{
      title:
        if(tx.contract_type == :sale,
          do: dgettext("contracts", "Sale contract"),
          else: dgettext("contracts", "Lease contract")
        ),
      meta:
        dgettext("contracts", "No. %{number} · %{date} · %{place}",
          number: number,
          date: local_date(tx.inserted_at, tz),
          place: room.city
        ),
      sections: sections
    }
  end

  defp deal_sections(%{contract_type: :sale} = tx, booking, lot, room, tz) do
    [
      section(
        dgettext("contracts", "Subject"),
        [
          dgettext("contracts", "The offeror sells to the acceptor “%{offer}”, made up of:",
            offer: lot.title
          )
        ],
        Enum.map(lot.basket.items, &item/1)
      ),
      section(dgettext("contracts", "Place"), [place(room)]),
      section(dgettext("contracts", "Handover"), [
        dgettext("contracts", "The handover is on %{date} (time zone %{timezone}).",
          date: local(booking.starts_at, tz),
          timezone: tz
        ),
        dgettext("contracts", "Ownership passes to the acceptor at the handover.")
      ]),
      section(dgettext("contracts", "Price"), [
        dgettext(
          "contracts",
          "The price is %{price}. The parties settle payment between themselves; BASA takes no part in the payment.",
          price: Basa.Money.format(booking.price_amount, booking.currency)
        )
      ]),
      section(dgettext("contracts", "Condition and claims"), [
        dgettext(
          "contracts",
          "The offeror hands over everything in the condition shown in the photos of the evidence package."
        ),
        dgettext(
          "contracts",
          "At the handover the acceptor confirms receipt with a delivery act and photos."
        ),
        dngettext(
          "contracts",
          "The acceptor may raise a claim for defects not shown in the photos within %{count} day of delivery; after that the delivery counts as accepted.",
          "The acceptor may raise a claim for defects not shown in the photos within %{count} days of delivery; after that the delivery counts as accepted.",
          tx.claims_window_days
        )
      ])
    ]
  end

  defp deal_sections(tx, booking, lot, room, tz) do
    [
      section(
        dgettext("contracts", "Subject"),
        [
          dgettext("contracts", "The offeror lets the acceptor use “%{offer}”, made up of:",
            offer: lot.title
          )
        ],
        Enum.map(lot.basket.items, &item/1) ++ Enum.map(lot.basket.attendants, & &1.name)
      ),
      section(dgettext("contracts", "Place"), [place(room)]),
      section(dgettext("contracts", "Term"), [
        dgettext("contracts", "From %{start} to %{end} (time zone %{timezone}).",
          start: local(booking.starts_at, tz),
          end: local(booking.ends_at, tz),
          timezone: tz
        )
      ]),
      section(dgettext("contracts", "Price and deposit"), [
        dgettext(
          "contracts",
          "The price is %{price}. The parties settle payment between themselves; BASA takes no part in the payment.",
          price: Basa.Money.format(booking.price_amount, booking.currency)
        ),
        if(tx.deposit_amount,
          do:
            dgettext("contracts", "The acceptor leaves a deposit of %{deposit}.",
              deposit: Basa.Money.format(tx.deposit_amount, booking.currency)
            ),
          else: dgettext("contracts", "There is no deposit.")
        )
      ]),
      section(dgettext("contracts", "Condition and return"), [
        dgettext(
          "contracts",
          "The offeror hands over everything in the condition shown in the photos of the evidence package."
        ),
        dgettext(
          "contracts",
          "At the end of the term the acceptor returns it in the same condition, apart from normal wear, and files a return act with photos."
        ),
        dngettext(
          "contracts",
          "The offeror accepts the return act or raises a claim within %{count} day; after that the return counts as accepted.",
          "The offeror accepts the return act or raises a claim within %{count} days; after that the return counts as accepted.",
          tx.claims_window_days
        )
      ])
    ]
  end

  defp draft_notice,
    do: dgettext("contracts", "Draft template: not legal text until a lawyer has reviewed it.")

  defp consumer_clause(:ua),
    do:
      dgettext(
        "contracts",
        "The acceptor is a consumer. Nothing in this contract limits their rights under the consumer protection law of Ukraine."
      )

  defp consumer_clause(:eu),
    do:
      dgettext(
        "contracts",
        "The acceptor is a consumer. Nothing in this contract limits the protection given to them by the mandatory consumer law of the country where they live."
      )

  defp law_clause(:ua),
    do:
      dgettext(
        "contracts",
        "This contract is governed by the law of Ukraine, in particular the Civil Code of Ukraine."
      )

  defp law_clause(:eu),
    do:
      dgettext(
        "contracts",
        "This contract is governed by the law of the country where the offeror lives, without taking from a consumer the protection of the mandatory rules of their own country."
      )

  defp section(heading, paras, items \\ []), do: %{heading: heading, paras: paras, items: items}

  defp name(%Party{legal_name: legal}) when is_binary(legal) and legal != "", do: legal
  defp name(%Party{user: user}), do: user.display_name || to_string(user.email)

  defp item(item) do
    parts = Enum.reject([item.brand, item.model], &(&1 in [nil, ""]))
    title = String.downcase(item.title)

    if parts == [] or Enum.all?(parts, &String.contains?(title, String.downcase(&1))),
      do: item.title,
      else: "#{item.title} (#{Enum.join(parts, " ")})"
  end

  defp place(room) do
    if room.mobile,
      do:
        dgettext(
          "contracts",
          "Mobile setup based in %{city}; the parties agree the exact address.",
          city: room.city
        ),
      else: Enum.join(Enum.reject([room.address, room.city], &(&1 in [nil, ""])), ", ")
  end

  defp language_name(code) do
    {_, _, name} = List.keyfind(Basa.I18n.locales(), code, 0)
    name
  end

  defp local(dt, tz), do: dt |> DateTime.shift_zone!(tz) |> Calendar.strftime("%d.%m.%Y %H:%M")
  defp local_date(dt, tz), do: dt |> DateTime.shift_zone!(tz) |> Calendar.strftime("%d.%m.%Y")

  defp known_template(t) when t in @templates, do: :ok
  defp known_template(t), do: {:error, {:unknown_template, t}}

  defp typst(data, timestamp) do
    dir = Application.app_dir(:basa, "priv/contracts")

    args = [
      "compile",
      "--root",
      dir,
      "--ignore-system-fonts",
      "--creation-timestamp",
      to_string(timestamp),
      "--input",
      "data=" <> Jason.encode!(data),
      Path.join(dir, "contract.typ"),
      "-"
    ]

    case System.cmd(typst_path(), args, stderr_to_stdout: false) do
      {"%PDF" <> _ = pdf, 0} -> {:ok, pdf}
      {output, status} -> {:error, {:typst, status, String.slice(output, 0, 500)}}
    end
  rescue
    e in ErlangError -> {:error, {:typst_missing, Exception.message(e)}}
  end

  defp typst_path,
    do:
      Application.get_env(:basa, __MODULE__, [])[:typst] || System.find_executable("typst") ||
        "typst"
end
