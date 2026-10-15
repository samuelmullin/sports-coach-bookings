defmodule SportsCoachBookings.Catalog.Offering do
  @moduledoc "A class type a tenant sells (private, semi-private, or group)."

  use SportsCoachBookings.Core.TenantSchema

  @type t :: %__MODULE__{}

  @formats [:private, :semi_private, :group]

  schema "offerings" do
    field :tenant_id, :binary_id
    field :name, :string
    field :slug, :string
    field :description, :string
    field :format, Ecto.Enum, values: @formats
    field :min_age, :integer
    field :max_age, :integer
    field :duration_minutes, :integer
    field :default_capacity, :integer, default: 1
    field :credit_cost, :integer, default: 1
    field :drop_in_price, :integer
    field :taxable, :boolean, default: false
    field :bookable_until_minutes_before, :integer, default: 60
    field :bookable_from_days_ahead, :integer
    field :active, :boolean, default: true
    field :position, :integer, default: 0
    field :image_key, :string

    # Public/private are booking modes, not marketing formats. `format` is
    # retained for backwards compatibility while clients migrate.
    field :public_enabled, :boolean, default: true
    field :public_max_players, :integer, default: 1
    field :public_players_per_coach, :integer, default: 1
    field :public_price_tiers, :map, default: %{}
    field :private_enabled, :boolean, default: false
    field :private_max_players, :integer, default: 1
    field :private_players_per_coach, :integer, default: 1
    field :private_price_tiers, :map, default: %{}
    field :allow_invite_reservations, :boolean, default: false
    field :invite_hold_hours, :integer, default: 48
    field :allow_private_conversion, :boolean, default: false
    field :allow_private_requests, :boolean, default: false

    timestamps()
  end

  @doc false
  def changeset(offering, attrs) do
    attrs = legacy_booking_mode_defaults(offering, attrs)

    offering
    |> Ecto.Changeset.cast(attrs, [
      :tenant_id,
      :name,
      :slug,
      :description,
      :format,
      :min_age,
      :max_age,
      :duration_minutes,
      :default_capacity,
      :credit_cost,
      :drop_in_price,
      :taxable,
      :bookable_until_minutes_before,
      :bookable_from_days_ahead,
      :active,
      :position,
      :image_key,
      :public_enabled,
      :public_max_players,
      :public_players_per_coach,
      :public_price_tiers,
      :private_enabled,
      :private_max_players,
      :private_players_per_coach,
      :private_price_tiers,
      :allow_invite_reservations,
      :invite_hold_hours,
      :allow_private_conversion,
      :allow_private_requests
    ])
    |> Ecto.Changeset.validate_required([:tenant_id, :name, :format, :duration_minutes])
    |> Ecto.Changeset.validate_number(:duration_minutes, greater_than: 0)
    |> Ecto.Changeset.validate_number(:default_capacity, greater_than_or_equal_to: 1)
    |> Ecto.Changeset.validate_number(:credit_cost, greater_than_or_equal_to: 0)
    |> Ecto.Changeset.validate_number(:min_age, greater_than_or_equal_to: 0)
    |> Ecto.Changeset.validate_number(:max_age, greater_than_or_equal_to: 0)
    |> Ecto.Changeset.validate_number(:position, greater_than_or_equal_to: 0)
    |> Ecto.Changeset.validate_number(:public_max_players, greater_than_or_equal_to: 1)
    |> Ecto.Changeset.validate_number(:public_players_per_coach, greater_than_or_equal_to: 1)
    |> Ecto.Changeset.validate_number(:private_max_players, greater_than_or_equal_to: 1)
    |> Ecto.Changeset.validate_number(:private_players_per_coach, greater_than_or_equal_to: 1)
    |> Ecto.Changeset.validate_number(:invite_hold_hours, greater_than_or_equal_to: 1)
    |> validate_modes()
    |> validate_tiers(:public_price_tiers, :public_max_players)
    |> validate_tiers(:private_price_tiers, :private_max_players)
    |> default_slug()
    |> Ecto.Changeset.unique_constraint([:tenant_id, :slug])
  end

  @doc false
  def slugify(name) when is_binary(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, "-")
    |> String.trim("-")
  end

  def slugify(_), do: "offering"

  defp default_slug(changeset) do
    case Ecto.Changeset.get_field(changeset, :slug) do
      slug when is_binary(slug) and slug != "" ->
        changeset

      _ ->
        case Ecto.Changeset.get_field(changeset, :name) do
          name when is_binary(name) -> Ecto.Changeset.put_change(changeset, :slug, slugify(name))
          _ -> changeset
        end
    end
  end

  @doc "Returns the per-player money and credit price for a booking mode and party size."
  @spec price_tier(t(), :public | :private, pos_integer()) ::
          %{price: non_neg_integer() | nil, credit_cost: non_neg_integer()} | nil
  def price_tier(%__MODULE__{} = offering, mode, party_size)
      when mode in [:public, :private] and is_integer(party_size) and party_size > 0 do
    tiers =
      if mode == :public, do: offering.public_price_tiers, else: offering.private_price_tiers

    case Map.get(tiers || %{}, Integer.to_string(party_size)) do
      %{} = tier ->
        %{
          price: tier_value(tier, "price"),
          credit_cost: tier_value(tier, "credit_cost") || 0
        }

      _ ->
        nil
    end
  end

  defp validate_modes(changeset) do
    public? = Ecto.Changeset.get_field(changeset, :public_enabled)
    private? = Ecto.Changeset.get_field(changeset, :private_enabled)

    if public? or private?,
      do: changeset,
      else:
        Ecto.Changeset.add_error(changeset, :public_enabled, "enable at least one booking mode")
  end

  defp validate_tiers(changeset, tiers_field, max_field) do
    tiers = Ecto.Changeset.get_field(changeset, tiers_field) || %{}
    max_players = Ecto.Changeset.get_field(changeset, max_field) || 1
    require_coverage? = map_size(tiers) > 0 or Ecto.Changeset.changed?(changeset, tiers_field)

    missing? = require_coverage? and missing_tier?(tiers, max_players)
    invalid? = missing? or Enum.any?(tiers, &(not valid_tier?(&1, max_players)))

    if invalid?,
      do: Ecto.Changeset.add_error(changeset, tiers_field, "contains an invalid player tier"),
      else: changeset
  end

  defp missing_tier?(tiers, max_players) do
    Enum.any?(1..max_players, &(not Map.has_key?(tiers, Integer.to_string(&1))))
  end

  defp valid_tier?({size, tier}, max_players) when is_map(tier) do
    case Integer.parse(to_string(size)) do
      {count, ""} when count >= 1 and count <= max_players -> valid_tier_prices?(tier)
      _ -> false
    end
  end

  defp valid_tier?(_tier, _max_players), do: false

  defp valid_tier_prices?(tier) do
    price = tier_value(tier, "price")
    credits = tier_value(tier, "credit_cost") || 0

    (is_nil(price) or (is_integer(price) and price >= 0)) and
      is_integer(credits) and credits >= 0
  end

  defp tier_value(tier, "price"), do: Map.get(tier, "price", Map.get(tier, :price))

  defp tier_value(tier, "credit_cost"),
    do: Map.get(tier, "credit_cost", Map.get(tier, :credit_cost))

  defp legacy_booking_mode_defaults(%__MODULE__{id: nil} = offering, attrs) do
    capacity = attr(attrs, :default_capacity) || offering.default_capacity || 1
    format = attr(attrs, :format)
    price = attr(attrs, :drop_in_price)
    credits = attr(attrs, :credit_cost)
    credits = if is_nil(credits), do: offering.credit_cost || 0, else: credits

    tier =
      Map.new(1..capacity, fn size ->
        {Integer.to_string(size), %{"price" => price, "credit_cost" => credits}}
      end)

    attrs
    |> put_default(:public_enabled, format not in [:private, "private"])
    |> put_default(:public_max_players, capacity)
    |> put_default(:public_players_per_coach, capacity)
    |> put_default(:public_price_tiers, tier)
    |> put_default(:private_enabled, format in [:private, "private"])
    |> put_default(:private_max_players, capacity)
    |> put_default(:private_players_per_coach, capacity)
    |> put_default(:private_price_tiers, tier)
  end

  defp legacy_booking_mode_defaults(_offering, attrs), do: attrs

  defp attr(attrs, key), do: Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key))

  defp put_default(attrs, key, value) do
    string_key = Atom.to_string(key)

    cond do
      Map.has_key?(attrs, key) or Map.has_key?(attrs, string_key) ->
        attrs

      Enum.any?(Map.keys(attrs), &is_binary/1) ->
        Map.put(attrs, string_key, value)

      true ->
        Map.put(attrs, key, value)
    end
  end
end
