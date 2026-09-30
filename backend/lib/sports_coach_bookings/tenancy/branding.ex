defmodule SportsCoachBookings.Tenancy.Branding do
  @moduledoc """
  Per-tenant branding (one row per tenant). Tenant-owned (RLS).

  Colours are validated as hex; `font_family` must come from a fixed allowlist.
  Asset keys are converted to public URLs by `SportsCoachBookings.Tenancy.Storage`.
  """

  use SportsCoachBookings.Core.TenantSchema

  alias SportsCoachBookings.Tenancy.Storage

  @type t :: %__MODULE__{}

  @fonts ~w(inter roboto lato open_sans montserrat source_sans_pro system)
  @color_fields ~w(primary_color secondary_color accent_color background_color text_color)a

  schema "branding" do
    field :tenant_id, :binary_id
    field :logo_key, :string
    field :favicon_key, :string
    field :primary_color, :string
    field :secondary_color, :string
    field :accent_color, :string
    field :background_color, :string
    field :text_color, :string
    field :font_family, :string
    field :email_footer_text, :string
    field :social_links, :map, default: %{}

    timestamps()
  end

  @doc false
  def changeset(branding, attrs) do
    branding
    |> Ecto.Changeset.cast(attrs, [
      :tenant_id,
      :logo_key,
      :favicon_key,
      :primary_color,
      :secondary_color,
      :accent_color,
      :background_color,
      :text_color,
      :font_family,
      :email_footer_text,
      :social_links
    ])
    |> Ecto.Changeset.validate_required([:tenant_id])
    |> validate_colors()
    |> Ecto.Changeset.validate_inclusion(:font_family, @fonts, message: "is not an allowed font")
    |> Ecto.Changeset.unique_constraint(:tenant_id)
  end

  @doc "The font families a tenant may choose."
  @spec allowed_fonts() :: [String.t()]
  def allowed_fonts, do: @fonts

  defp validate_colors(changeset) do
    Enum.reduce(@color_fields, changeset, fn field, acc ->
      case Ecto.Changeset.get_field(acc, field) do
        nil -> acc
        value -> validate_hex_color(acc, field, value)
      end
    end)
  end

  defp validate_hex_color(changeset, field, value) do
    if value =~ ~r/^#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6})$/ do
      changeset
    else
      Ecto.Changeset.add_error(changeset, field, "must be a hex colour like #1a2b3c")
    end
  end

  @doc "A public URL for an asset key, or `nil`."
  @spec asset_url(binary() | nil) :: binary() | nil
  def asset_url(nil), do: nil
  def asset_url(key), do: Storage.public_url(key)
end
