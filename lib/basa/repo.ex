defmodule Basa.Repo do
  use AshPostgres.Repo,
    otp_app: :basa

  @impl true
  def installed_extensions do
    ["ash-functions", "citext", "btree_gist", "postgis"]
  end

  @impl true
  def prefer_transaction? do
    false
  end

  @impl true
  def min_pg_version do
    %Version{major: 16, minor: 0, patch: 0}
  end
end
