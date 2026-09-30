defmodule SportsCoachBookingsWeb.ErrorJSONTest do
  use ExUnit.Case, async: true

  alias SportsCoachBookingsWeb.ErrorJSON

  test "renders the standard error envelope for 404" do
    assert ErrorJSON.render("404.json", %{}) ==
             %{error: %{code: "not_found", message: "Not Found", details: %{}}}
  end

  test "renders the standard error envelope for 500" do
    assert ErrorJSON.render("500.json", %{}) ==
             %{
               error: %{
                 code: "internal_server_error",
                 message: "Internal Server Error",
                 details: %{}
               }
             }
  end
end
