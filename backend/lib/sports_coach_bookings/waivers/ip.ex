defmodule SportsCoachBookings.Waivers.IP do
  @moduledoc """
  Ecto type for Postgres `inet`.

  Ecto has no built-in primitive for `inet`, so this maps a textual IP address
  to the `%Postgrex.INET{}` struct that the Postgres adapter encodes. The
  underlying storage type is `:inet` (see `type/0`).
  """

  use Ecto.Type

  @impl Ecto.Type
  def type, do: :inet

  @impl Ecto.Type
  def cast(nil), do: {:ok, nil}
  def cast(%Postgrex.INET{} = inet), do: {:ok, inet}
  def cast(ip) when is_binary(ip), do: parse(ip)
  def cast(_), do: :error

  @impl Ecto.Type
  def load(nil), do: {:ok, nil}
  def load(%Postgrex.INET{} = inet), do: {:ok, inet}

  @impl Ecto.Type
  def dump(nil), do: {:ok, nil}
  def dump(%Postgrex.INET{} = inet), do: {:ok, inet}
  def dump(ip) when is_binary(ip), do: parse(ip)
  def dump(_), do: :error

  @doc "Formats a `%Postgrex.INET{}` (or `nil`) as a string."
  @spec format(Postgrex.INET.t() | nil) :: String.t() | nil
  def format(nil), do: nil

  def format(%Postgrex.INET{address: address, netmask: nil}),
    do: address |> :inet.ntoa() |> Kernel.to_string()

  def format(%Postgrex.INET{address: address, netmask: netmask}),
    do: "#{address |> :inet.ntoa() |> Kernel.to_string()}/#{netmask}"

  defp parse(ip) do
    case :inet.parse_address(String.to_charlist(ip)) do
      {:ok, address} -> {:ok, %Postgrex.INET{address: address}}
      _ -> :error
    end
  end
end
