defmodule SportsCoachBookings.Payments.Providers.StripeTest do
  use ExUnit.Case, async: true

  alias SportsCoachBookings.Payments.Providers.Stripe

  @secret "whsec_test_secret"

  defp sign(body, timestamp \\ Integer.to_string(System.system_time(:second))) do
    signature =
      :crypto.mac(:hmac, :sha256, @secret, "#{timestamp}.#{body}")
      |> Base.encode16(case: :lower)

    {"t=#{timestamp},v1=#{signature}", body}
  end

  defp completed_event do
    %{
      "id" => "evt_completed",
      "type" => "checkout.session.completed",
      "account" => "acct_123",
      "data" => %{
        "object" => %{
          "id" => "cs_123",
          "payment_intent" => "pi_123",
          "amount_total" => 5_000,
          "currency" => "cad",
          "metadata" => %{
            "tenant_id" => "t_1",
            "order_id" => "o_1",
            "order_number" => "A-0001"
          }
        }
      }
    }
  end

  test "verifies a signature over the raw body" do
    {header, body} = sign(Jason.encode!(completed_event()))

    assert {:ok, %{"id" => "evt_completed"}} =
             Stripe.verify_webhook(body, %{"stripe-signature" => header})
  end

  test "rejects a tampered body" do
    {header, body} = sign(Jason.encode!(completed_event()))

    assert {:error, :invalid_signature} =
             Stripe.verify_webhook(body <> " ", %{"stripe-signature" => header})
  end

  test "rejects a stale timestamp" do
    stale = Integer.to_string(System.system_time(:second) - 10_000)
    {header, body} = sign(Jason.encode!(completed_event()), stale)

    assert {:error, :invalid_signature} =
             Stripe.verify_webhook(body, %{"stripe-signature" => header})
  end

  test "rejects a missing signature header" do
    assert {:error, :invalid_signature} = Stripe.verify_webhook("{}", %{})
  end

  test "normalises checkout.session.completed into a flat data map" do
    assert {:ok, normalized} = Stripe.normalize_event(completed_event())
    assert normalized.type == :checkout_completed
    assert normalized.event_id == "evt_completed"
    assert normalized.data["tenant_id"] == "t_1"
    assert normalized.data["order_id"] == "o_1"
    assert normalized.data["account_ref"] == "acct_123"
    assert normalized.data["checkout_ref"] == "cs_123"
    assert normalized.data["payment_ref"] == "pi_123"
    assert normalized.data["amount"] == 5_000
    assert normalized.data["currency"] == "cad"
  end

  test "normalises charge.refunded, including the refund ref" do
    event = %{
      "id" => "evt_refund",
      "type" => "charge.refunded",
      "account" => "acct_123",
      "data" => %{
        "object" => %{
          "id" => "ch_1",
          "payment_intent" => "pi_123",
          "amount_refunded" => 2_000,
          "currency" => "cad",
          "metadata" => %{"tenant_id" => "t_1"},
          "refunds" => %{"data" => [%{"id" => "re_1"}]}
        }
      }
    }

    assert {:ok, normalized} = Stripe.normalize_event(event)
    assert normalized.type == :charge_refunded
    assert normalized.data["refund_ref"] == "re_1"
    assert normalized.data["refund_amount"] == 2_000
    assert normalized.data["payment_ref"] == "pi_123"
  end

  test "ignores unknown event types" do
    assert :ignore = Stripe.normalize_event(%{"id" => "evt_x", "type" => "customer.created"})
  end
end
