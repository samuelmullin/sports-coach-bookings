defmodule SportsCoachBookings.Customers.Phone do
  @moduledoc """
  Validates and normalizes customer phone numbers to E.164.

  The backend is authoritative: it uses libphonenumber metadata (through
  `ex_phone_number`) so the UI can collect a national number in the user's local
  format while we store a canonical E.164 value.

  Inputs may be a `{country_iso2, national_number}` pair or a raw E.164 string
  (leading `+`). The E.164 form is accepted for compatibility with existing
  clients and wins when present.
  """

  @type result :: {:ok, String.t() | nil} | {:error, :invalid}

  @doc """
  Normalizes `country` + `number` to an E.164 string.

  Returns `{:ok, nil}` when the input is blank (phone stays optional),
  `{:ok, e164}` when the number is valid for the region, and
  `{:error, :invalid}` otherwise.
  """
  @spec normalize(String.t() | nil, String.t() | nil) :: result()
  def normalize(country, number) do
    cond do
      blank?(number) -> {:ok, nil}
      e164?(number) -> parse(number, nil)
      true -> parse(number, region(country))
    end
  end

  defp parse(number, region) do
    with {:ok, parsed} <- ExPhoneNumber.parse(String.trim(number), region),
         true <- ExPhoneNumber.is_valid_number?(parsed) do
      {:ok, ExPhoneNumber.format(parsed, :e164)}
    else
      _ -> {:error, :invalid}
    end
  end

  defp blank?(nil), do: true
  defp blank?(number) when is_binary(number), do: String.trim(number) == ""
  defp blank?(_number), do: true

  defp e164?(number), do: String.starts_with?(String.trim(number), "+")

  defp region(nil), do: nil

  defp region(country) when is_binary(country) do
    case String.trim(country) do
      "" -> nil
      value -> String.upcase(value)
    end
  end

  defp region(_country), do: nil
end
