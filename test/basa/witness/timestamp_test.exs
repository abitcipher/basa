defmodule Basa.Witness.TimestampTest do
  use ExUnit.Case, async: true

  alias Basa.Witness.Timestamp.RFC3161

  @hash Base.decode16!("d86d6b71f32823cd9c6619a49a71aa9818cc73587f2b419d4a5ded735ad6ccf5",
          case: :lower
        )
  @token File.read!("test/support/freetsa_reply.tsr")

  test "a FreeTSA token checks out offline, only for its own hash" do
    assert {:ok, %DateTime{year: 2026, month: 11, day: 1}} = RFC3161.verify(@token, @hash)
    assert {:error, :not_verified} = RFC3161.verify(@token, :crypto.hash(:sha256, "other"))
    assert {:error, _} = RFC3161.verify("garbage", @hash)
  end
end
