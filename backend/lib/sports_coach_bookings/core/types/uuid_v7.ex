defmodule SportsCoachBookings.Core.Types.UUIDv7 do
  @moduledoc """
  An Ecto type for time-ordered UUIDv7 primary keys (RFC 9562).

  The in-memory representation is the canonical lowercase string form; the
  database representation is a 16-byte binary stored in a Postgres `uuid`
  column. IDs are generated in Elixir (`autogenerate/0`), so no database
  extension is required.
  """

  use Ecto.Type

  @impl true
  def type, do: :uuid

  @impl true
  def cast(value), do: Ecto.UUID.cast(value)

  @impl true
  def load(value), do: Ecto.UUID.load(value)

  @impl true
  def dump(value), do: Ecto.UUID.dump(value)

  @impl true
  def autogenerate, do: generate()

  @doc """
  Generates a new UUIDv7 as a canonical lowercase string.
  """
  @spec generate() :: String.t()
  def generate do
    ms = System.system_time(:millisecond)
    <<rand_a::12, _::4>> = :crypto.strong_rand_bytes(2)
    <<rand_b::62, _::2>> = :crypto.strong_rand_bytes(8)

    <<ms::48, 7::4, rand_a::12, 2::2, rand_b::62>>
    |> encode()
  end

  @doc """
  Re-encodes a raw 16-byte UUID binary into its canonical string form.
  """
  @spec to_string(<<_::128>>) :: String.t()
  def to_string(<<_::128>> = raw), do: encode(raw)

  defp encode(raw) do
    hex = Base.encode16(raw, case: :lower)

    <<p1::binary-size(8), p2::binary-size(4), p3::binary-size(4), p4::binary-size(4),
      p5::binary-size(12)>> = hex

    p1 <> "-" <> p2 <> "-" <> p3 <> "-" <> p4 <> "-" <> p5
  end
end
