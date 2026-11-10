defmodule Basa.DssStub do
  @fixture Path.expand("fixtures/dss/emulator.json", __DIR__)
  @external_resource @fixture

  def recorded, do: @fixture |> File.read!() |> Jason.decode!()

  def qualified do
    update_in(recorded(), ["SimpleReport", "signatureOrTimestampOrEvidenceRecord"], fn [t] ->
      [
        update_in(t, ["Signature"], fn s ->
          Map.merge(s, %{
            "Indication" => "TOTAL_PASSED",
            "SubIndication" => nil,
            "SignatureLevel" => %{
              "value" => "QESig",
              "description" => "Qualified Electronic Signature"
            }
          })
        end)
      ]
    end)
  end

  def with_dss(answer, fun) do
    old = Application.get_env(:basa, Basa.Witness.QES.Dss)
    Application.put_env(:basa, Basa.Witness.QES.Dss, Keyword.put(old, :url, "http://dss.test"))
    stub(answer)

    try do
      fun.()
    after
      Application.put_env(:basa, Basa.Witness.QES.Dss, old)
    end
  end

  def stub(answer) do
    Req.Test.stub(Basa.Witness.QES.Dss, fn conn ->
      case answer do
        :down ->
          Req.Test.transport_error(conn, :econnrefused)

        f when is_function(f, 1) ->
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          Req.Test.json(conn, f.(Jason.decode!(body)))

        report ->
          Req.Test.json(conn, report)
      end
    end)
  end
end
