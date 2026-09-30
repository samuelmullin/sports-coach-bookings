defmodule SportsCoachBookingsWeb.ErrorJSON do
  @moduledoc """
  Renders the standard error envelope:

      {"error": {"code": "snake_case", "message": "…", "details": {…}}}
  """

  def render(template, _assigns) do
    status = Phoenix.Controller.status_message_from_template(template)

    %{
      error: %{
        code: code_for(template),
        message: status,
        details: %{}
      }
    }
  end

  defp code_for("400.json"), do: "bad_request"
  defp code_for("401.json"), do: "unauthorized"
  defp code_for("403.json"), do: "forbidden"
  defp code_for("404.json"), do: "not_found"
  defp code_for("405.json"), do: "method_not_allowed"
  defp code_for("409.json"), do: "conflict"
  defp code_for("422.json"), do: "unprocessable_entity"
  defp code_for("429.json"), do: "too_many_requests"
  defp code_for("500.json"), do: "internal_server_error"
  defp code_for(_), do: "error"
end
