defmodule SportsCoachBookings.Tenancy.Contrast do
  @moduledoc """
  WCAG 2.1 contrast-ratio checks for branding.

  These produce **warnings**, never errors: a tenant may ship an inaccessible
  palette, but the API surfaces the issue so the UI can nudge them. The
  thresholds are the AA minimums (4.5:1 for normal text, 3:1 for large text).
  """

  @aa_normal 4.5

  @doc """
  Returns a list of human-readable WCAG AA warnings for `branding`.

  Checks `text_color` against `background_color`, and `primary_color` against
  white/black button text.
  """
  @spec warnings(map() | struct()) :: [String.t()]
  def warnings(branding) do
    []
    |> check_main_text(branding)
    |> check_button(branding)
    |> Enum.reverse()
  end

  @doc "Contrast ratio between two hex colours, or `:error` for bad input."
  @spec ratio(binary() | nil, binary() | nil) :: float() | :error
  def ratio(hex1, hex2) do
    with {r1, g1, b1} <- parse(hex1),
         {r2, g2, b2} <- parse(hex2) do
      l1 = luminance({r1, g1, b1})
      l2 = luminance({r2, g2, b2})
      {lighter, darker} = if l1 >= l2, do: {l1, l2}, else: {l2, l1}
      (lighter + 0.05) / (darker + 0.05)
    else
      _ -> :error
    end
  end

  @doc "Parses `#rgb` or `#rrggbb` into an `{r, g, b}` tuple of 0..255."
  @spec parse(binary() | nil) :: {0..255, 0..255, 0..255} | :error
  def parse(<<"#", hex::binary-size(3)>>) do
    <<r, g, b>> = hex
    {expand(r), expand(g), expand(b)}
  rescue
    _ -> :error
  end

  def parse(<<"#", hex::binary-size(6)>>) do
    <<r1, r2, g1, g2, b1, b2>> = hex

    {String.to_integer(<<r1, r2>>, 16), String.to_integer(<<g1, g2>>, 16),
     String.to_integer(<<b1, b2>>, 16)}
  rescue
    _ -> :error
  end

  def parse(_), do: :error

  defp expand(char) do
    String.to_integer(<<char, char>>, 16)
  end

  defp check_main_text(warnings, branding) do
    case ratio(field(branding, :text_color), field(branding, :background_color)) do
      ratio when is_float(ratio) and ratio < @aa_normal ->
        [
          "text_color/#{field(branding, :background_color)} contrast " <>
            "#{Float.round(ratio, 2)}:1 is below WCAG AA 4.5:1"
          | warnings
        ]

      _ ->
        warnings
    end
  end

  defp check_button(warnings, branding) do
    case field(branding, :primary_color) do
      nil ->
        warnings

      _primary ->
        white = ratio(field(branding, :primary_color), "#ffffff")
        black = ratio(field(branding, :primary_color), "#000000")

        if is_float(white) and is_float(black) and white < @aa_normal and black < @aa_normal do
          [
            "primary_color has insufficient contrast against both white (#{round2(white)}:1) " <>
              "and black (#{round2(black)}:1) button text"
            | warnings
          ]
        else
          warnings
        end
    end
  end

  defp field(branding, key) when is_map(branding), do: Map.get(branding, key)
  defp field(_branding, _key), do: nil

  defp round2(value), do: Float.round(value, 2)

  defp luminance({r, g, b}) do
    [r, g, b]
    |> Enum.map(&(&1 / 255))
    |> Enum.map(fn channel ->
      if channel <= 0.03928 do
        channel / 12.92
      else
        :math.pow((channel + 0.055) / 1.055, 2.4)
      end
    end)
    |> then(fn [r, g, b] -> 0.2126 * r + 0.7152 * g + 0.0722 * b end)
  end
end
