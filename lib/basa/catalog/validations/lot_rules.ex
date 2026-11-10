defmodule Basa.Catalog.Validations.LotRules do
  use Ash.Resource.Validation

  @impl true
  def validate(changeset, _opts, _context) do
    get = &Ash.Changeset.get_attribute(changeset, &1)

    cond do
      get.(:price_unit) == :slot and is_nil(get.(:slot_minutes)) ->
        {:error, field: :slot_minutes, message: Basa.I18n.t("is required for slot pricing")}

      get.(:max_units) && get.(:max_units) < (get.(:min_units) || 1) ->
        {:error, field: :max_units, message: Basa.I18n.t("must be at least the minimum")}

      not Tzdata.zone_exists?(get.(:timezone) || "Europe/Kyiv") ->
        {:error, field: :timezone, message: Basa.I18n.t("is not a known time zone")}

      true ->
        case Basa.Bookings.Schedule.validate_weekly_hours(get.(:weekly_hours) || %{}) do
          :ok -> :ok
          {:error, message} -> {:error, field: :weekly_hours, message: message}
        end
    end
  end
end
