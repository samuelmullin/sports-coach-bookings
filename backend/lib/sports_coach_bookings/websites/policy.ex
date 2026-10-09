defmodule SportsCoachBookings.Websites.Policy do
  @moduledoc "Authorization for hosted websites and their contact inbox."

  use SportsCoachBookings.Core.Policy

  alias SportsCoachBookings.Core.StaffActor

  @impl SportsCoachBookings.Core.Policy
  def authorize(%StaffActor{role: role}, action, resource)
      when role in [:owner, :admin] and
             action in [:get, :update, :publish, :upload, :list, :review] and
             resource in [:site, :contact_submission],
      do: :ok

  def authorize(_actor, :view, :published_site), do: :ok
  def authorize(_actor, :create, :contact_submission), do: :ok
  def authorize(_actor, _action, _resource), do: {:error, :forbidden}
end
