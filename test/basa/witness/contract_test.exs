defmodule Basa.Witness.ContractTest do
  use Basa.DataCase, async: true

  import Basa.Fixtures

  alias Basa.Witness
  alias Basa.Witness.{Contract, Store, Verify}

  setup do
    lessor = user(%{display_name: "Olena", locale: :uk})
    lessee = user(%{display_name: "Max", locale: :en})

    lot =
      published_lot(lessor, basket(lessor, [item(lessor)]), room(lessor), %{
        title: "Vocal session"
      })

    starts = hours_from_now(30)

    {:ok, booking} =
      Basa.Bookings.book(
        %{lot_id: lot.id, starts_at: starts, ends_at: DateTime.add(starts, 3600)},
        actor: lessee
      )

    %{booking: booking, lessor: lessor, lessee: lessee}
  end

  defp open(booking, attrs \\ %{}),
    do: Witness.open_transaction!(booking.id, attrs, authorize?: false)

  test "opening picks languages (offeror's first) and the template", %{booking: booking} do
    tx = open(booking, %{jurisdiction: :ua})
    assert tx.languages == [:uk, :en]
    assert tx.template == "lease-ua@1"
  end

  test "a bilingual draft contract with the booking's terms", %{booking: booking} do
    tx = open(booking, %{jurisdiction: :ua, consumer: true, deposit_amount: Decimal.new(500)})
    {:ok, data} = Contract.data(tx)

    assert data.languages == ["uk", "en"]
    [uk, en] = data.texts
    assert uk.title == "Договір оренди" and en.title == "Lease contract"
    assert data.draft =~ "Чернетка"

    headings = Enum.map(en.sections, & &1.heading)
    assert "Consumer rights" in headings and "Languages" in headings
    assert Enum.any?(en.sections, &Enum.any?(&1.paras, fn p -> p =~ "deposit of 500" end))
    assert Enum.any?(en.sections, &Enum.any?(&1.paras, fn p -> p =~ "Olena" end))
    assert length(uk.sections) == length(en.sections)
  end

  test "one language and no consumer clause when both speak it", ctx do
    Ash.Seed.update!(ctx.lessee, %{locale: :uk})
    tx = open(ctx.booking, %{jurisdiction: :eu})
    {:ok, data} = Contract.data(tx)

    assert data.languages == ["uk"]
    refute Enum.any?(hd(data.texts).sections, &(&1.heading in ["Права споживача", "Мови"]))
  end

  test "the PDF is reproducible and goes into the evidence", %{booking: booking, lessor: lessor} do
    tx = open(booking)
    assert {:ok, "%PDF" <> _ = pdf} = Contract.render(tx)
    assert Contract.render(tx) == {:ok, pdf}

    assert {:ok, evidence} = Contract.attach(tx, lessor)

    assert {evidence.kind, evidence.media_type, evidence.position} ==
             {:contract, "application/pdf", 0}

    assert Store.read(evidence, tx) == {:ok, pdf}
    assert Verify.transaction(tx).ok?
  end

  test "an unknown template is refused", %{booking: booking} do
    tx = open(booking, %{template: "gift-ua@1"})
    assert Contract.render(tx) == {:error, {:unknown_template, "gift-ua@1"}}
  end
end
