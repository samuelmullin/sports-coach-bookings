defmodule SportsCoachBookingsWeb.CatalogJSON do
  @moduledoc "Serialises catalog resources for the staff and portal APIs."

  alias SportsCoachBookings.Catalog
  alias SportsCoachBookings.Catalog.Discount
  alias SportsCoachBookings.Catalog.Offering
  alias SportsCoachBookings.Catalog.Package
  alias SportsCoachBookings.Catalog.TaxRate
  alias SportsCoachBookings.Catalog.Venue

  @doc "Serialises a venue."
  @spec venue(Venue.t()) :: map()
  def venue(venue) do
    %{
      id: venue.id,
      name: venue.name,
      address_line1: venue.address_line1,
      address_line2: venue.address_line2,
      city: venue.city,
      province: venue.province,
      postal_code: venue.postal_code,
      country: venue.country,
      timezone: venue.timezone,
      notes: venue.notes,
      map_url: venue.map_url,
      active: venue.active,
      inserted_at: datetime(venue.inserted_at),
      updated_at: datetime(venue.updated_at)
    }
  end

  @doc "Serialises an offering."
  @spec offering(Offering.t()) :: map()
  def offering(offering) do
    %{
      id: offering.id,
      name: offering.name,
      slug: offering.slug,
      description: offering.description,
      format: offering.format,
      min_age: offering.min_age,
      max_age: offering.max_age,
      duration_minutes: offering.duration_minutes,
      default_capacity: offering.default_capacity,
      credit_cost: offering.credit_cost,
      drop_in_price: offering.drop_in_price,
      taxable: offering.taxable,
      bookable_until_minutes_before: offering.bookable_until_minutes_before,
      bookable_from_days_ahead: offering.bookable_from_days_ahead,
      active: offering.active,
      position: offering.position,
      image_key: offering.image_key,
      public_enabled: offering.public_enabled,
      public_max_players: offering.public_max_players,
      public_players_per_coach: offering.public_players_per_coach,
      public_price_tiers: offering.public_price_tiers,
      private_enabled: offering.private_enabled,
      private_max_players: offering.private_max_players,
      private_players_per_coach: offering.private_players_per_coach,
      private_price_tiers: offering.private_price_tiers,
      allow_invite_reservations: offering.allow_invite_reservations,
      invite_hold_hours: offering.invite_hold_hours,
      allow_private_conversion: offering.allow_private_conversion,
      allow_private_requests: offering.allow_private_requests,
      inserted_at: datetime(offering.inserted_at),
      updated_at: datetime(offering.updated_at)
    }
  end

  @doc """
  Serialises a package.

  `offering_ids` may be a precomputed `%{package_id => [offering_id]}` map from
  `Catalog.package_offering_ids/1` (index endpoints use this to avoid N+1).
  When omitted it is looked up for the single package. An empty list means the
  package is valid for all offerings.
  """
  @spec package(Package.t(), map() | nil) :: map()
  def package(package, offering_ids_map \\ nil) do
    %{
      id: package.id,
      name: package.name,
      description: package.description,
      credit_quantity: package.credit_quantity,
      validity_days: package.validity_days,
      price: package.price,
      taxable: package.taxable,
      per_household_limit: package.per_household_limit,
      active: package.active,
      visible_in_portal: package.visible_in_portal,
      position: package.position,
      offering_ids: resolve_offering_ids(package, offering_ids_map),
      inserted_at: datetime(package.inserted_at),
      updated_at: datetime(package.updated_at)
    }
  end

  @doc "Serialises a discount."
  @spec discount(Discount.t()) :: map()
  def discount(discount) do
    %{
      id: discount.id,
      code: discount.code,
      kind: discount.kind,
      value: discount.value,
      applies_to: discount.applies_to,
      starts_at: datetime(discount.starts_at),
      ends_at: datetime(discount.ends_at),
      max_redemptions: discount.max_redemptions,
      per_household_limit: discount.per_household_limit,
      min_subtotal: discount.min_subtotal,
      active: discount.active,
      inserted_at: datetime(discount.inserted_at),
      updated_at: datetime(discount.updated_at)
    }
  end

  @doc "Serialises a tax rate."
  @spec tax_rate(TaxRate.t()) :: map()
  def tax_rate(tax_rate) do
    %{
      id: tax_rate.id,
      name: tax_rate.name,
      rate_bps: tax_rate.rate_bps,
      active: tax_rate.active,
      inserted_at: datetime(tax_rate.inserted_at),
      updated_at: datetime(tax_rate.updated_at)
    }
  end

  @doc "Wraps a list of serialised rows in the pagination envelope."
  @spec collection([map()], String.t() | nil) :: map()
  def collection(data, next_cursor \\ nil), do: %{data: data, next_cursor: next_cursor}

  defp resolve_offering_ids(package, map) when is_map(map), do: Map.get(map, package.id, [])

  defp resolve_offering_ids(package, nil) do
    case Catalog.package_eligible_offering_ids(package.id) do
      :all -> []
      ids -> ids
    end
  end

  defp datetime(nil), do: nil
  defp datetime(value), do: DateTime.to_iso8601(value)
end
