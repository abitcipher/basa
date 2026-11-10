defmodule Basa.ImportAccessTest do
  use Basa.DataCase, async: true

  import Basa.Fixtures

  alias Basa.Import

  @text "The user takes full responsibility for how the imported content is used."

  setup do
    %{admin: user(%{role: :admin}), owner: user()}
  end

  test "the admin grants, the user confirms the current agreement, then the tool opens", ctx do
    assert Import.status(ctx.owner) == :none
    assert {:error, %Ash.Error.Forbidden{}} = Import.grant_access(ctx.owner.id, actor: ctx.owner)

    {:ok, _} = Import.grant_access(ctx.owner.id, actor: ctx.admin)
    assert Import.status(ctx.owner) == :no_agreement

    assert {:error, %Ash.Error.Forbidden{}} = Import.publish_agreement(@text, actor: ctx.owner)
    {:ok, v1} = Import.publish_agreement(@text, actor: ctx.admin)
    assert v1.version == 1
    assert Import.status(ctx.owner) == :confirm

    access = Import.access_for(ctx.owner)
    assert {:error, _} = Import.accept_agreement(access, 7, actor: ctx.owner)
    assert {:error, %Ash.Error.Forbidden{}} = Import.accept_agreement(access, 1, actor: user())

    {:ok, accepted} = Import.accept_agreement(access, 1, actor: ctx.owner)
    assert accepted.accepted_hash == Import.Agreement.hash(v1)
    assert Import.allowed?(ctx.owner)

    {:ok, v2} = Import.publish_agreement(@text <> " Version two.", actor: ctx.admin)
    assert v2.version == 2
    assert Import.status(ctx.owner) == :confirm
  end

  test "revoked, the tool closes and comes back with a new grant", ctx do
    allow(ctx)
    {:ok, _} = Import.revoke_access(Import.access_for(ctx.owner), actor: ctx.admin)
    assert Import.status(ctx.owner) == :none

    assert {:error, %Ash.Error.Forbidden{}} =
             Import.create_source(source_params(), actor: ctx.owner)

    {:ok, _} = Import.grant_access(ctx.owner.id, actor: ctx.admin)
    assert Import.allowed?(ctx.owner)
  end

  test "sources: only with access, only the owner's, insecure only by an admin", ctx do
    assert {:error, %Ash.Error.Forbidden{}} =
             Import.create_source(source_params(), actor: ctx.owner)

    allow(ctx)
    {:ok, source} = Import.create_source(source_params(), actor: ctx.owner)
    assert source.browser == :auto and source.insecure == false

    assert {:error, %Ash.Error.Invalid{}} =
             Import.create_source(%{name: "x", sample_urls: ["ftp://shop.example/"]},
               actor: ctx.owner
             )

    assert {:error, %Ash.Error.Invalid{}} =
             Import.create_source(%{name: "x", sample_urls: []}, actor: ctx.owner)

    stranger = user()
    assert {:error, _} = Import.get_source(source.id, actor: stranger)

    assert {:error, %Ash.Error.Forbidden{}} =
             Import.set_source_insecure(source, true, actor: ctx.owner)

    {:ok, source} = Import.set_source_insecure(source, true, actor: ctx.admin)
    assert source.insecure

    {:ok, source} = Import.update_source(source, %{recipe: %{"fields" => %{}}}, actor: ctx.owner)
    assert source.recipe == %{"fields" => %{}}
  end

  defp allow(ctx) do
    {:ok, _} = Import.grant_access(ctx.owner.id, actor: ctx.admin)
    {:ok, agreement} = Import.publish_agreement(@text, actor: ctx.admin)

    {:ok, _} =
      Import.accept_agreement(Import.access_for(ctx.owner), agreement.version, actor: ctx.owner)
  end

  defp source_params,
    do: %{name: "Shop", sample_urls: ["http://shop.example/p/1", "http://shop.example/p/2"]}
end
