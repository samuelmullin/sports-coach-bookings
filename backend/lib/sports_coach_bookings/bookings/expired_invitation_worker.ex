defmodule SportsCoachBookings.Bookings.ExpiredInvitationWorker do
  @moduledoc "Releases one expired invitation reservation. Idempotent."

  use SportsCoachBookings.Core.TenantWorker, queue: :default

  alias SportsCoachBookings.Bookings

  @impl true
  def perform_with_tenant(%Oban.Job{args: %{"invitation_id" => invitation_id}}) do
    {:ok, _result} = Bookings.expire_invitation(invitation_id)
    :ok
  end
end
