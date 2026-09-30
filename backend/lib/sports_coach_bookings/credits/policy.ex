defmodule SportsCoachBookings.Credits.Policy do
  @moduledoc """
  Authorization for the credit ledger. Owned by WP-12.

  | Actor | Read balance / lots / ledger | Grant / adjust |
  |---|---|---|
  | Owner / admin | Yes (any household) | Yes |
  | Coach | Yes (read-only) | No |
  | Household manager | Yes (own household only) | No |
  | Anonymous | No | No |

  The context scopes every customer read to the caller's own household; the
  policy only gates the action, not the row.
  """

  use SportsCoachBookings.Core.Policy

  alias SportsCoachBookings.Core.CustomerActor
  alias SportsCoachBookings.Core.StaffActor

  @resources [:credit_lot, :credit_ledger_entry]

  @read_actions [:list, :list_ledger]
  @write_actions [:grant, :adjust]

  ## Owner / admin: full control within their tenant.

  def authorize(%StaffActor{role: role}, _action, _resource) when role in [:owner, :admin],
    do: :ok

  ## Coach: read-only.

  def authorize(%StaffActor{role: :coach}, action, resource)
      when action in @read_actions and resource in @resources,
      do: :ok

  ## Household manager: read-only, scoped to their own household by the context.

  def authorize(%CustomerActor{}, action, resource)
      when action in @read_actions and resource in @resources,
      do: :ok

  ## Default: deny.

  def authorize(_actor, _action, _resource), do: {:error, :forbidden}

  @doc "The actions the policy understands. Used by tests and tooling."
  @spec actions() :: [atom()]
  def actions, do: @read_actions ++ @write_actions

  @doc "The resources the policy understands. Used by tests and tooling."
  @spec resources() :: [atom()]
  def resources, do: @resources

  @doc "The actions a coach is allowed."
  @spec coach_actions() :: [atom()]
  def coach_actions, do: @read_actions

  @doc "The actions a household manager is allowed."
  @spec customer_actions() :: [atom()]
  def customer_actions, do: @read_actions

  @doc "The actions that require a staff writer (owner/admin)."
  @spec write_actions() :: [atom()]
  def write_actions, do: @write_actions
end
