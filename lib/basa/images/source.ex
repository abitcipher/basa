defmodule Basa.Images.Source do
  @type candidate :: %{
          ref: String.t(),
          source: atom(),
          source_id: String.t(),
          key: String.t() | nil,
          url: String.t() | nil,
          thumbnail: String.t(),
          title: String.t() | nil,
          creator: String.t() | nil,
          creator_url: String.t() | nil,
          license: String.t(),
          license_version: String.t() | nil,
          license_url: String.t() | nil,
          landing_url: String.t() | nil,
          width: integer() | nil,
          height: integer() | nil,
          tags: [String.t()]
        }

  @callback search(query :: String.t(), limit :: pos_integer()) ::
              {:ok, [candidate()]} | {:error, term()}
end
