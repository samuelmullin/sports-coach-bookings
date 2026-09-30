defmodule SportsCoachBookingsWeb.UnsubscribeControllerTest do
  use SportsCoachBookingsWeb.ConnCase, async: false

  alias SportsCoachBookings.DataCase
  alias SportsCoachBookings.Notifications.Preferences
  alias SportsCoachBookings.Notifications.UnsubscribeToken

  setup do
    tenant = insert(:tenant, slug: "acme")
    DataCase.put_tenant(tenant)
    customer = insert(:customer_user, tenant_id: tenant.id)
    {:ok, _} = Preferences.update(customer, %{marketing_opt_in: true})

    %{tenant: tenant, customer: customer}
  end

  defp token_for(tenant, customer) do
    UnsubscribeToken.sign(%{
      tenant_id: tenant.id,
      subject_type: :customer_user,
      subject_id: customer.id,
      email: customer.email
    })
  end

  test "POST one-click unsubscribe turns off marketing", %{
    conn: conn,
    tenant: tenant,
    customer: customer
  } do
    response =
      conn
      |> with_host(tenant.slug)
      |> post("/unsubscribe/#{token_for(tenant, customer)}")

    assert json_response(response, 200) == %{"unsubscribed" => true}
    refute Preferences.get(customer).marketing_opt_in
  end

  test "GET shows a confirmation page", %{conn: conn, tenant: tenant, customer: customer} do
    response =
      conn
      |> with_host(tenant.slug)
      |> get("/unsubscribe/#{token_for(tenant, customer)}")

    assert response.status == 200
    assert response.resp_body =~ "unsubscribed"
  end

  test "an invalid token is rejected", %{conn: conn, tenant: tenant} do
    response = conn |> with_host(tenant.slug) |> post("/unsubscribe/not-a-token")
    assert response.status == 422
  end
end
