defmodule SportsCoachBookings.Payments.Providers.Stripe do
  @moduledoc """
  Stripe Connect adapter (Express accounts, direct charges) behind
  `SportsCoachBookings.Payments.Provider`.

  All HTTP goes through the injectable client configured at
  `:payments_stripe_client` (default `Stripe.Client`), so tests never make a
  real network call. Configuration (per pending decision #1, account type and
  webhook secret are config values):

      config :sports_coach_bookings,
        payments_stripe_secret_key: "sk_live_…",
        payments_stripe_webhook_secret: "whsec_…",
        payments_stripe_account_type: "express",
        payments_stripe_api_base: "https://api.stripe.com",
        payments_stripe_client: SportsCoachBookings.Payments.Providers.Stripe.Client

  The webhook endpoint handles `checkout.session.completed`,
  `checkout.session.expired`, `payment_intent.payment_failed`,
  `charge.refunded`, and `account.updated`.
  """

  @behaviour SportsCoachBookings.Payments.Provider

  alias SportsCoachBookings.Payments.{CheckoutRequest, CheckoutSession, NormalizedEvent}
  alias SportsCoachBookings.Payments.Providers.Stripe.Client

  @session_ttl_seconds 30 * 60
  @webhook_tolerance 300

  @impl true
  def create_connected_account(tenant) do
    with :ok <- configured?() do
      params = %{
        "type" => account_type(),
        "metadata" => %{"tenant_id" => tenant_id(tenant)}
      }

      case client().request(:post, "/v1/accounts", params, auth: secret_key()) do
        {:ok, %{"id" => id}} -> {:ok, id}
        {:ok, body} -> {:error, {:unexpected_response, body}}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @impl true
  def onboarding_link(account_ref, return_url, refresh_url) do
    with :ok <- configured?() do
      params = %{
        "account" => account_ref,
        "type" => "account_onboarding",
        "return_url" => return_url,
        "refresh_url" => refresh_url
      }

      case client().request(:post, "/v1/account_links", params, auth: secret_key()) do
        {:ok, %{"url" => url}} -> {:ok, url}
        {:ok, body} -> {:error, {:unexpected_response, body}}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @impl true
  def account_status(account_ref) do
    with :ok <- configured?() do
      case client().request(:get, "/v1/accounts/#{account_ref}", %{}, auth: secret_key()) do
        {:ok, %{"charges_enabled" => charges, "payouts_enabled" => payouts} = body} ->
          {:ok,
           %{
             charges_enabled: charges,
             payouts_enabled: payouts,
             requirements_due: get_in(body, ["requirements", "currently_due"]) || []
           }}

        {:ok, body} ->
          {:error, {:unexpected_response, body}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @impl true
  def create_checkout(account_ref, %CheckoutRequest{} = request) do
    with :ok <- configured?() do
      params =
        %{
          "mode" => "payment",
          "success_url" => request.success_url,
          "cancel_url" => request.cancel_url,
          "customer_email" => request.customer_email,
          "expires_at" => expires_at_unix(),
          "line_items" => Enum.map(request.line_items, &line_item(&1, request.currency)),
          "payment_intent_data" =>
            reject_nil(%{
              "application_fee_amount" => request.application_fee_amount,
              "metadata" => request.metadata
            }),
          "metadata" => request.metadata
        }
        |> reject_nil()

      case client().request(:post, "/v1/checkout/sessions", params,
             auth: secret_key(),
             account: account_ref
           ) do
        {:ok, %{"id" => id, "url" => url} = body} ->
          {:ok,
           %CheckoutSession{
             session_ref: id,
             redirect_url: url,
             expires_at: expires_at(body)
           }}

        {:ok, body} ->
          {:error, {:unexpected_response, body}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @impl true
  def refund(account_ref, payment_ref, %{amount: amount, currency: currency}, reason) do
    with :ok <- configured?() do
      params =
        %{
          "payment_intent" => payment_ref,
          "amount" => amount,
          "reason" => stripe_reason(reason),
          "metadata" => %{"currency" => currency, "reason" => to_string(reason)}
        }
        |> reject_nil()

      case client().request(:post, "/v1/refunds", params,
             auth: secret_key(),
             account: account_ref
           ) do
        {:ok, %{"id" => id}} -> {:ok, id}
        {:ok, body} -> {:error, {:unexpected_response, body}}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @impl true
  def verify_webhook(raw_body, headers) when is_binary(raw_body) do
    with secret when is_binary(secret) and secret != "" <- webhook_secret(),
         {:ok, header} <- find_header(headers, "stripe-signature"),
         {:ok, timestamp, signatures} <- parse_signature(header),
         :ok <- check_tolerance(timestamp),
         expected <- :crypto.mac(:hmac, :sha256, secret, timestamp <> "." <> raw_body),
         true <- valid_signature?(signatures, expected),
         {:ok, event} <- Jason.decode(raw_body) do
      {:ok, event}
    else
      _ -> {:error, :invalid_signature}
    end
  end

  def verify_webhook(_raw_body, _headers), do: {:error, :invalid_signature}

  @impl true
  def normalize_event(%{"id" => event_id, "type" => type} = event) when is_binary(event_id) do
    case normalize_type(type) do
      nil ->
        :ignore

      normalized ->
        {:ok, %NormalizedEvent{type: normalized, event_id: event_id, data: data(event)}}
    end
  end

  def normalize_event(_event), do: :ignore

  ## Normalisation

  defp data(event) do
    object = get_in(event, ["data", "object"]) || %{}
    metadata = object["metadata"] || %{}

    %{
      "tenant_id" => metadata["tenant_id"],
      "order_id" => metadata["order_id"],
      "order_number" => metadata["order_number"],
      "account_ref" => event["account"],
      "checkout_ref" => checkout_ref(event["type"], object),
      "payment_ref" => payment_ref(event["type"], object),
      "amount" => amount(event["type"], object),
      "currency" => object["currency"],
      "refund_ref" => refund_ref(event["type"], object),
      "refund_amount" => refund_amount(event["type"], object),
      "charges_enabled" => object["charges_enabled"],
      "payouts_enabled" => object["payouts_enabled"],
      "requirements" => object["requirements"]
    }
  end

  defp checkout_ref(type, object)
       when type in ["checkout.session.completed", "checkout.session.expired"],
       do: object["id"]

  defp checkout_ref(_type, _object), do: nil

  defp payment_ref("checkout.session.completed", object), do: object["payment_intent"]
  defp payment_ref("payment_intent.payment_failed", object), do: object["id"]
  defp payment_ref("charge.refunded", object), do: object["payment_intent"]
  defp payment_ref(_type, _object), do: nil

  defp amount(type, object)
       when type in ["checkout.session.completed", "checkout.session.expired"],
       do: object["amount_total"]

  defp amount("payment_intent.payment_failed", object), do: object["amount"]
  defp amount("charge.refunded", object), do: object["amount_refunded"]
  defp amount(_type, _object), do: nil

  defp refund_amount("charge.refunded", object), do: object["amount_refunded"]
  defp refund_amount(_type, _object), do: nil

  defp refund_ref("charge.refunded", object) do
    refunds = get_in(object, ["refunds", "data"])

    case refunds do
      [%{"id" => id} | _] -> id
      _ -> nil
    end
  end

  defp refund_ref(_type, _object), do: nil

  defp normalize_type("checkout.session.completed"), do: :checkout_completed
  defp normalize_type("checkout.session.expired"), do: :checkout_expired
  defp normalize_type("payment_intent.payment_failed"), do: :payment_failed
  defp normalize_type("charge.refunded"), do: :charge_refunded
  defp normalize_type("account.updated"), do: :account_updated
  defp normalize_type(_type), do: nil

  ## Signature

  defp parse_signature(header) do
    parts =
      header
      |> String.split(",")
      |> Enum.map(&String.split(&1, "=", parts: 2))
      |> Enum.reject(fn pair -> length(pair) != 2 end)

    timestamp = parts |> Enum.find_value(fn [k, v] -> if k == "t", do: v end)
    signatures = for ["v1", value] <- parts, do: value

    if is_binary(timestamp) and signatures != [] do
      {:ok, timestamp, signatures}
    else
      :error
    end
  end

  defp valid_signature?(signatures, expected) do
    encoded = Base.encode16(expected, case: :lower)
    Enum.any?(signatures, &Plug.Crypto.secure_compare(&1, encoded))
  end

  defp check_tolerance(timestamp) do
    case Integer.parse(timestamp) do
      {unix, ""} ->
        if abs(System.system_time(:second) - unix) <= @webhook_tolerance, do: :ok, else: :error

      _ ->
        :error
    end
  end

  ## Helpers

  defp line_item(%CheckoutRequest.LineItem{} = item, currency) do
    %{
      "quantity" => item.quantity,
      "price_data" => %{
        "currency" => String.downcase(currency),
        "unit_amount" => item.unit_amount,
        "product_data" => %{"name" => item.name}
      }
    }
  end

  defp expires_at_unix,
    do: System.system_time(:second) + @session_ttl_seconds

  defp expires_at(%{"expires_at" => unix}) when is_integer(unix), do: DateTime.from_unix!(unix)
  defp expires_at(_body), do: nil

  defp stripe_reason(reason) when reason in ["duplicate", "fraudulent", "requested_by_customer"],
    do: reason

  defp stripe_reason(:duplicate), do: "duplicate"
  defp stripe_reason(:fraudulent), do: "fraudulent"
  defp stripe_reason(:requested_by_customer), do: "requested_by_customer"
  defp stripe_reason(_reason), do: nil

  defp tenant_id(%{id: id}), do: id
  defp tenant_id(id), do: to_string(id)

  defp reject_nil(params) do
    params
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp find_header(headers, name) when is_list(headers) do
    case Enum.find(headers, fn {key, _} -> String.downcase(to_string(key)) == name end) do
      {_key, value} when is_binary(value) -> {:ok, value}
      _ -> :error
    end
  end

  defp find_header(headers, name) when is_map(headers) do
    find_header(Map.to_list(headers), name)
  end

  defp find_header(_headers, _name), do: :error

  defp client, do: Application.get_env(:sports_coach_bookings, :payments_stripe_client, Client)

  defp configured? do
    case secret_key() do
      key when is_binary(key) and key != "" -> :ok
      _ -> {:error, :not_configured}
    end
  end

  defp secret_key,
    do: Application.get_env(:sports_coach_bookings, :payments_stripe_secret_key)

  defp webhook_secret,
    do: Application.get_env(:sports_coach_bookings, :payments_stripe_webhook_secret)

  defp account_type,
    do: Application.get_env(:sports_coach_bookings, :payments_stripe_account_type, "express")
end
