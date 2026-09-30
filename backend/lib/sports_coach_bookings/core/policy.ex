defmodule SportsCoachBookings.Core.Policy do
  @moduledoc """
  Behaviour implemented by `<Context>.Policy` modules.

  Controllers (and only controllers) call the policy before invoking any
  context function. A policy decides whether an actor may perform `action` on
  `resource`.

  Actors are one of:

    * `SportsCoachBookings.Core.StaffActor` — an owner, admin, or coach.
    * `SportsCoachBookings.Core.CustomerActor` — a household manager.
    * `nil` — an anonymous caller.
  """

  @type actor ::
          SportsCoachBookings.Core.StaffActor.t()
          | SportsCoachBookings.Core.CustomerActor.t()
          | nil

  @type action :: atom()
  @type resource :: term()

  @callback authorize(actor(), action(), resource()) :: :ok | {:error, :forbidden}

  @doc """
  Implements a deny-by-default `authorize/3` that contexts override per action.

  Using this macro ensures every context policy starts closed; each WP must
  replace the default with explicit owner/admin/coach/customer/anonymous clauses
  and test the full matrix.
  """
  defmacro __using__(_opts) do
    quote do
      @behaviour SportsCoachBookings.Core.Policy

      @typedoc "An actor accepted by `authorize/3`."
      @type actor :: SportsCoachBookings.Core.Policy.actor()

      @impl SportsCoachBookings.Core.Policy
      def authorize(_actor, _action, _resource), do: {:error, :forbidden}

      defoverridable authorize: 3
    end
  end
end
