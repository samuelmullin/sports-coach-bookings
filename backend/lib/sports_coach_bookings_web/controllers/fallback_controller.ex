defmodule SportsCoachBookingsWeb.FallbackController do
  @moduledoc """
  Translates `{:error, …}` returns from contexts into the standard error JSON
  envelope and the correct HTTP status.
  """

  use SportsCoachBookingsWeb, :controller

  def call(conn, {:error, :not_found}) do
    error(conn, :not_found, "not_found", "Not found")
  end

  def call(conn, {:error, :forbidden}) do
    error(conn, :forbidden, "forbidden", "Forbidden")
  end

  def call(conn, {:error, :unauthorized}) do
    error(conn, :unauthorized, "unauthorized", "Unauthorized")
  end

  def call(conn, {:error, :conflict}) do
    error(conn, :conflict, "conflict", "Conflict")
  end

  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    details = %{fields: changeset_errors(changeset)}

    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: %{code: "validation_error", message: "Validation failed", details: details}})
  end

  def call(conn, {:error, {:session_full, session_id}}) when is_binary(session_id) do
    conn
    |> put_status(:conflict)
    |> json(%{
      error: %{
        code: "session_full",
        message: "A selected session is full",
        details: %{session_id: session_id}
      }
    })
  end

  def call(conn, {:error, {:invalid_session, session_id}}) when is_binary(session_id) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      error: %{
        code: "invalid_session",
        message: "A selected session no longer exists",
        details: %{session_id: session_id}
      }
    })
  end

  def call(conn, {:error, {code, message}}) when is_atom(code) and is_binary(message) do
    error(conn, :unprocessable_entity, to_string(code), message)
  end

  def call(conn, {:error, {code, message, details}})
      when is_atom(code) and is_binary(message) and is_map(details) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: %{code: to_string(code), message: message, details: details}})
  end

  def call(conn, {:error, code}) when is_atom(code) do
    status = status_for(code)

    error(
      conn,
      status,
      to_string(code),
      Phoenix.Controller.status_message_from_template("#{status}.json")
    )
  end

  def call(conn, {:error, reason}) do
    error(conn, :internal_server_error, "internal_error", inspect(reason))
  end

  defp error(conn, status, code, message) do
    conn
    |> put_status(status)
    |> json(%{error: %{code: code, message: message, details: %{}}})
  end

  defp status_for(:session_full), do: :conflict
  defp status_for(:player_conflict), do: :conflict
  defp status_for(:reservation_expired), do: :conflict
  defp status_for(:expired), do: :conflict
  defp status_for(:email_unconfirmed), do: :forbidden
  defp status_for(:account_deactivated), do: :forbidden
  defp status_for(:already_has_household), do: :conflict
  defp status_for(:invalid_code), do: :unprocessable_entity
  defp status_for(:invalid_email), do: :unprocessable_entity
  defp status_for(:invalid_credentials), do: :unauthorized
  defp status_for(:invalid_invite), do: :not_found
  defp status_for(:expired_invite), do: :gone
  defp status_for(:already_member), do: :conflict
  defp status_for(:last_owner), do: :conflict
  defp status_for(:currency_locked), do: :conflict
  defp status_for(:slug_taken), do: :conflict
  defp status_for(:reserved_slug), do: :unprocessable_entity
  defp status_for(:invalid_slug), do: :unprocessable_entity
  defp status_for(:invalid_role), do: :unprocessable_entity
  defp status_for(:unsupported_content_type), do: :unprocessable_entity
  defp status_for(:file_too_large), do: :unprocessable_entity
  defp status_for(_), do: :unprocessable_entity

  defp changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  rescue
    _ -> Ecto.Changeset.traverse_errors(changeset, fn {message, _opts} -> message end)
  end
end
