defmodule SportsCoachBookings.Tenancy.Storage.Svg do
  @moduledoc """
  SVG safety policy for branding uploads.

  A real storage/CDN pipeline would rasterise SVGs. This environment has no
  image toolchain, so we **sanitise by rejection**: any SVG carrying script,
  event-handler, external-reference, or embed vectors is refused. See
  `docs/rfcs/20260928-tenancy-storage-stub.md`.
  """

  @unsafe_patterns [
    # Scripting / event handlers.
    ~r/<script/i,
    ~r/javascript:/i,
    ~r/on[a-z]+\s*=/i,
    # Embedding / foreign content.
    ~r/<foreignObject/i,
    ~r/<iframe/i,
    ~r/<embed/i,
    ~r/<object/i,
    ~r/<animate/i,
    ~r/<\s*set[\s>]/i,
    ~r/<\s*use[\s>]/i,
    # XML entity / stylesheet injection.
    ~r/<!DOCTYPE/i,
    ~r/<!ENTITY/i,
    ~r/<\?xml-stylesheet/i,
    # External or data references (href/xlink:href/url()).
    ~r/(?:xlink:)?href\s*=\s*["']\s*(?:https?:|\/\/|data:)/i,
    ~r/url\s*\(\s*["']?\s*(?:https?:|\/\/|data:)/i
  ]

  @doc "Returns `{:ok, svg}` when safe, `{:error, :unsafe_svg}` otherwise."
  @spec sanitize(binary()) :: {:ok, binary()} | {:error, :unsafe_svg}
  def sanitize(svg) when is_binary(svg) do
    if Enum.any?(@unsafe_patterns, &Regex.match?(&1, svg)) do
      {:error, :unsafe_svg}
    else
      {:ok, svg}
    end
  end

  def sanitize(_), do: {:error, :unsafe_svg}
end
