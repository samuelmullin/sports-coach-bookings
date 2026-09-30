defmodule SportsCoachBookingsWeb.Portal.Legal.Helpers do
  @moduledoc false

  alias SportsCoachBookings.Legal
  alias SportsCoachBookings.Notifications

  @email_regex ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/

  @doc "Whether `email` looks like a deliverable address."
  @spec valid_email?(term()) :: boolean()
  def valid_email?(email) when is_binary(email), do: Regex.match?(@email_regex, email)
  def valid_email?(_email), do: false

  @doc """
  Resolves the destination address: the request `email` when present, else the
  signed-in customer's account address (anonymous viewers have neither).
  """
  @spec resolve_email(Plug.Conn.t(), map()) :: {:ok, String.t()} | {:error, :invalid_email}
  def resolve_email(conn, params) do
    case Map.get(params, "email") || customer_email(conn) do
      email when is_binary(email) ->
        if valid_email?(email), do: {:ok, email}, else: {:error, :invalid_email}

      _ ->
        {:error, :invalid_email}
    end
  end

  defp customer_email(conn) do
    case conn.assigns[:current_customer_actor] do
      %{customer_user: %{email: email}} when is_binary(email) -> email
      _ -> nil
    end
  end

  @doc "Notification assigns for a document/waiver body (see `Legal.render_assigns/2`)."
  @spec assigns(String.t(), String.t()) :: map()
  def assigns(title, markdown), do: Legal.render_assigns(title, markdown)

  @doc """
  Queues a copy of a document to `email` through the notifications engine.

  Works for anonymous recipients (recipient type `:email`). Returns `:ok` or
  `{:error, reason}`.
  """
  @spec send_copy(String.t(), map()) :: :ok | {:error, term()}
  def send_copy(email, assigns) when is_binary(email) and is_map(assigns) do
    recipients = [%{type: :email, id: nil, email: email}]

    case Notifications.deliver(:legal_document, recipients, assigns, category: :transactional) do
      {:ok, _result} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
