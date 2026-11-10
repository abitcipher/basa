defmodule BasaWeb.MemAttestController do
  use BasaWeb, :controller

  require Ash.Query

  alias Basa.Witness.{MemAttest, MemAttestation}

  @max_body 1024

  def create(conn, %{"token" => token}) do
    with {:ok, challenge} <- MemAttest.challenge_from_token(token),
         %MemAttestation{} = record <- pending(challenge),
         {:ok, body, conn} <- Plug.Conn.read_body(conn, length: @max_body),
         {:ok, _} <-
           Basa.Witness.receive_mem_attestation(record, body, :https, authorize?: false) do
      send_resp(conn, 201, "")
    else
      {:more, _, conn} -> send_resp(conn, 413, "")
      {:error, %Ash.Error.Invalid{}} -> send_resp(conn, 422, "")
      _ -> send_resp(conn, 404, "")
    end
  end

  defp pending(challenge) do
    MemAttestation
    |> Ash.Query.filter(challenge == ^challenge and status == :pending)
    |> Ash.read_one!(authorize?: false)
  end
end
