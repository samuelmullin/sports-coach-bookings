defmodule SportsCoachBookings.Payments.Providers.Fake do
  @moduledoc """
  A deterministic in-memory provider for tests and local development.

  It implements the `SportsCoachBookings.Payments.Provider` behaviour without
  any network calls. Webhook verification simply JSON-decodes the raw body.
  """

  @behaviour SportsCoachBookings.Payments.Provider

  alias SportsCoachBookings.Payments.{CheckoutRequest, CheckoutSession, NormalizedEvent}

  @impl true
  def create_connected_account(tenant) do
    {:ok, "acct_fake_" <> id_of(tenant)}
  end

  @impl true
  def onboarding_link(account_ref, _return_url, _refresh_url) do
    {:ok, "https://provider.fake/onboarding/#{account_ref}"}
  end

  @impl true
  def account_status(_account_ref) do
    {:ok, %{charges_enabled: true, payouts_enabled: true, requirements_due: []}}
  end

  @impl true
  def create_checkout(account_ref, %CheckoutRequest{} = request) do
    {:ok,
     %CheckoutSession{
       session_ref: "cs_fake_" <> id_of(request.order_id),
       redirect_url: "https://provider.fake/checkout/#{account_ref}/#{request.order_number}",
       expires_at: DateTime.add(DateTime.utc_now(), 30 * 60, :second)
     }}
  end

  @impl true
  def refund(_account_ref, _payment_ref, _money, _reason) do
    {:ok, "re_fake_" <> Integer.to_string(System.unique_integer([:positive]))}
  end

  @impl true
  def verify_webhook(raw_body, _headers) do
    case Jason.decode(raw_body) do
      {:ok, event} -> {:ok, event}
      {:error, _} -> {:error, :invalid_signature}
    end
  end

  @impl true
  def normalize_event(%{"type" => type} = event) do
    {:ok,
     %NormalizedEvent{
       type: normalize_type(type),
       event_id: event["id"] || Integer.to_string(System.unique_integer([:positive])),
       data: event["data"] || %{}
     }}
  end

  def normalize_event(_), do: :ignore

  defp normalize_type("checkout.session.completed"), do: :checkout_completed
  defp normalize_type("checkout.session.expired"), do: :checkout_expired
  defp normalize_type("payment_intent.payment_failed"), do: :payment_failed
  defp normalize_type("charge.refunded"), do: :charge_refunded
  defp normalize_type("account.updated"), do: :account_updated
  defp normalize_type(_other), do: :unknown

  defp id_of(%{id: id}), do: id
  defp id_of(id), do: to_string(id)
end
