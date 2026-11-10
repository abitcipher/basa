defmodule Basa.System.Validations.NearSteps do
  use Ash.Resource.Validation
  use Gettext, backend: BasaWeb.Gettext

  @impl true
  def validate(changeset, _opts, _context) do
    get = &Ash.Changeset.get_attribute(changeset, &1)
    steps = Basa.System.near_values(get.(:near_steps_km), get.(:near_city), get.(:near_region))

    cond do
      steps == [] ->
        {:error, field: :near_steps_km, message: gettext("Offer at least one distance.")}

      get.(:near_default) not in steps ->
        {:error,
         field: :near_default, message: gettext("Pick the first choice from the offered ones.")}

      true ->
        :ok
    end
  end
end
