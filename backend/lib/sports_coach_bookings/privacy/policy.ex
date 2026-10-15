defmodule SportsCoachBookings.Privacy.Policy do
  @moduledoc """
  Authorization for PIPEDA household data export and erasure.

  | Actor | Export | Erase |
  |---|---|---|
  | Household manager | Own household | Own household (primary member only, enforced in `Privacy`) |
  | Owner / admin / coach | None | None |
  | Anonymous | None | None |

  Staff cannot trigger an export or erasure on a customer's behalf: both
  require the account holder's own session (and, for erasure, their password).
  """

  use SportsCoachBookings.Core.Policy

  alias SportsCoachBookings.Core.CustomerActor

  @actions [:export, :erase]

  def authorize(%CustomerActor{}, action, :household) when action in @actions, do: :ok

  def authorize(_actor, _action, _resource), do: {:error, :forbidden}

  @doc "The actions the policy understands. Used by tests and tooling."
  @spec actions() :: [atom()]
  def actions, do: @actions
end
