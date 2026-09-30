defmodule SportsCoachBookings.Notifications.UnsubscribeToken do
  @moduledoc """
  Signed one-click unsubscribe tokens.

  The token carries the tenant, subject, and address, so an unsubscribe can be
  applied without a login. It is used in the `List-Unsubscribe` and
  `List-Unsubscribe-Post` headers (RFC 8058) for non-transactional mail.
  """

  @salt "sports_coach_bookings unsubscribe"
  @max_age 60 * 60 * 24 * 365 * 2

  @doc "Signs an unsubscribe token for a subject."
  @spec sign(map()) :: String.t()
  def sign(%{tenant_id: tenant_id, email: email} = data) do
    payload = %{
      "tenant_id" => tenant_id,
      "subject_type" => data[:subject_type] && to_string(data[:subject_type]),
      "subject_id" => data[:subject_id],
      "email" => email
    }

    Phoenix.Token.sign(secret_key_base(), @salt, payload)
  end

  @doc "Verifies and returns the unsubscribe payload, or `{:error, reason}`."
  @spec verify(String.t()) :: {:ok, map()} | {:error, :invalid | :expired | term()}
  def verify(token) when is_binary(token) do
    Phoenix.Token.verify(secret_key_base(), @salt, token, max_age: @max_age)
  end

  def verify(_token), do: {:error, :invalid}

  defp secret_key_base do
    endpoint = Application.get_env(:sports_coach_bookings, SportsCoachBookingsWeb.Endpoint, [])

    endpoint[:secret_key_base] ||
      Application.get_env(:sports_coach_bookings, :unsubscribe_secret) ||
      "sports-coach-bookings-unsubscribe-development-secret"
  end
end
