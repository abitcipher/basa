defmodule Basa.Import.Charset do
  @cp1251 "ЂЃ‚ѓ„…†‡€‰Љ‹ЊЌЋЏђ‘’“”•–—\uFFFD™љ›њќћџ\u00A0ЎўЈ¤Ґ¦§Ё©Є«¬\u00AD®Ї°±Ііґµ¶·ё№є»јЅѕїАБВГДЕЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯабвгдежзийклмнопрстуфхцчшщъыьэюя"
          |> String.to_charlist()
          |> List.to_tuple()

  @spec to_utf8(binary(), String.t() | nil) :: String.t()
  def to_utf8(body, content_type) do
    case charset(content_type) || meta_charset(body) do
      cs when cs in ["windows-1251", "cp1251", "win-1251"] -> from_cp1251(body)
      cs when cs in ["iso-8859-1", "latin1", "windows-1252"] -> latin1(body)
      _ -> if String.valid?(body), do: body, else: guess(body)
    end
  end

  defp charset(nil), do: nil

  defp charset(content_type) do
    case Regex.run(~r/charset=["']?([\w-]+)/i, content_type) do
      [_, cs] -> String.downcase(cs)
      _ -> nil
    end
  end

  defp meta_charset(body) do
    head = binary_part(body, 0, min(byte_size(body), 4096))

    case Regex.run(~r/<meta[^>]+charset=["']?([\w-]+)/i, head) do
      [_, cs] -> String.downcase(cs)
      _ -> nil
    end
  end

  defp guess(body), do: from_cp1251(body)

  @doc false
  def from_cp1251(body), do: for(<<b <- body>>, into: "", do: <<cp1251(b)::utf8>>)

  defp cp1251(b) when b < 0x80, do: b
  defp cp1251(b), do: elem(@cp1251, b - 0x80)

  defp latin1(body), do: :unicode.characters_to_binary(body, :latin1)
end
