defmodule Basa.System do
  use Ash.Domain, otp_app: :basa

  resources do
    resource Basa.System.Settings do
      define :update_settings, action: :update
    end
  end

  def settings do
    case Ash.get(Basa.System.Settings, "global", authorize?: false) do
      {:ok, settings} ->
        settings

      {:error, _} ->
        Basa.System.Settings
        |> Ash.Changeset.for_create(:create, %{}, authorize?: false)
        |> Ash.create!(upsert?: true, upsert_fields: [])
    end
  end

  def widgets_enabled?, do: settings().widgets_enabled

  def near_steps(settings \\ settings()),
    do: near_values(settings.near_steps_km, settings.near_city, settings.near_region)

  @doc false
  def near_values(km, city?, region?) do
    Enum.map(Enum.sort(Enum.uniq(km || [])), &to_string/1) ++
      if(city?, do: ["city"], else: []) ++ if(region?, do: ["region"], else: [])
  end

  def near_step(value, settings \\ settings()) do
    value = to_string(value || "")
    if value in near_steps(settings), do: value, else: settings.near_default
  end
end
