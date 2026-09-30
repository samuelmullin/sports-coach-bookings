defmodule SportsCoachBookings.Bookings.Policy do
  @moduledoc """
  Authorization for the booking engine. Owned by WP-14.

  | Actor | Book / cancel / rebook (own household) | Roster / history | Attendance | Book on behalf / override |
  |---|---|---|---|---|
  | Owner / admin | Yes | Yes | Yes | Yes |
  | Coach | No | Read (assigned sessions) | Yes (assigned sessions) | No |
  | Household manager | Yes (own household) | — | — | No |
  | Anonymous | No | No | No | No |

  Role gating happens here; resource-specific scoping (a customer may only act
  on their own household's booking; a coach may only read/attend sessions they
  are assigned to) is enforced by the context, which can see the booking and
  the session.
  """

  use SportsCoachBookings.Core.Policy

  alias SportsCoachBookings.Core.CustomerActor
  alias SportsCoachBookings.Core.StaffActor

  @resources [:booking, :session]

  @owner_admin_actions [
    :book,
    :book_on_behalf,
    :list,
    :cancel,
    :cancel_preview,
    :override_cancel,
    :rebook,
    :rebook_options,
    :roster,
    :mark_attendance,
    :history
  ]

  @coach_actions [:list, :roster, :mark_attendance, :history]

  @customer_actions [:book, :list, :cancel, :cancel_preview, :rebook, :rebook_options]

  ## Owner / admin: full control within the tenant.

  def authorize(%StaffActor{role: role}, action, resource)
      when role in [:owner, :admin] and action in @owner_admin_actions and
             resource in @resources,
      do: :ok

  ## Coach: read assigned sessions and record attendance; never book or cancel.

  def authorize(%StaffActor{role: :coach}, action, resource)
      when action in @coach_actions and resource in @resources,
      do: :ok

  ## Household manager: act only on their own household (context-enforced).

  def authorize(%CustomerActor{}, action, resource)
      when action in @customer_actions and resource in @resources,
      do: :ok

  ## Default: deny.

  def authorize(_actor, _action, _resource), do: {:error, :forbidden}

  @doc "Every action the policy understands. Used by tests and tooling."
  @spec actions() :: [atom()]
  def actions do
    Enum.uniq(@owner_admin_actions ++ @coach_actions ++ @customer_actions)
  end

  @doc "The resources the policy understands. Used by tests and tooling."
  @spec resources() :: [atom()]
  def resources, do: @resources

  @doc "The actions a coach is allowed."
  @spec coach_actions() :: [atom()]
  def coach_actions, do: @coach_actions

  @doc "The actions a household manager is allowed."
  @spec customer_actions() :: [atom()]
  def customer_actions, do: @customer_actions

  @doc "The actions only an owner or admin may perform."
  @spec owner_admin_actions() :: [atom()]
  def owner_admin_actions, do: @owner_admin_actions
end
