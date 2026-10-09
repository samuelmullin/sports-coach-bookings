defmodule SportsCoachBookingsWeb.PrivacyJSON do
  @moduledoc "Serialises PIPEDA export bundles and erasure summaries."

  alias SportsCoachBookingsWeb.BookingsJSON
  alias SportsCoachBookingsWeb.CommerceJSON
  alias SportsCoachBookingsWeb.CreditsJSON
  alias SportsCoachBookingsWeb.CustomersJSON
  alias SportsCoachBookingsWeb.FeedbackJSON
  alias SportsCoachBookingsWeb.PlayersJSON
  alias SportsCoachBookingsWeb.WaiversJSON

  @doc "Serialises the household export bundle."
  @spec export(map()) :: map()
  def export(bundle) do
    %{
      generated_at: DateTime.to_iso8601(bundle.generated_at),
      household: CustomersJSON.household_detail(bundle.household),
      players: Enum.map(bundle.players, &player/1),
      bookings: Enum.map(bundle.bookings, &BookingsJSON.entry/1),
      credit_lots: Enum.map(bundle.credit_lots, &CreditsJSON.lot/1),
      credit_ledger: Enum.map(bundle.credit_ledger, &CreditsJSON.entry/1),
      orders: Enum.map(bundle.orders, &CommerceJSON.order/1)
    }
  end

  defp player(bundle) do
    %{
      player: PlayersJSON.player(bundle.player),
      profile: bundle.profile && PlayersJSON.profile(bundle.profile),
      emergency_contacts: Enum.map(bundle.emergency_contacts, &PlayersJSON.emergency_contact/1),
      authorized_pickups: Enum.map(bundle.authorized_pickups, &PlayersJSON.authorized_pickup/1),
      medical_info: bundle.medical_info && PlayersJSON.medical_info(bundle.medical_info),
      waiver_signatures: Enum.map(bundle.waiver_signatures, &WaiversJSON.signature/1),
      shared_feedback: Enum.map(bundle.shared_feedback, &FeedbackJSON.feedback/1)
    }
  end

  @doc "Serialises an erasure summary."
  @spec erasure(map()) :: map()
  def erasure(summary), do: summary
end
