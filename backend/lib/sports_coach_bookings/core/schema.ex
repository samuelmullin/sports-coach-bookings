defmodule SportsCoachBookings.Core.Schema do
  @moduledoc """
  Base schema macro for all SportsCoachBookings schemas.

  Sets UUIDv7 primary keys, binary foreign keys, and `utc_datetime_usec`
  timestamps so every context is consistent.
  """

  defmacro __using__(_opts) do
    quote do
      use Ecto.Schema

      @primary_key {:id, SportsCoachBookings.Core.Types.UUIDv7, autogenerate: true}
      @foreign_key_type :binary_id
      @timestamps_opts [type: :utc_datetime_usec]
    end
  end
end
