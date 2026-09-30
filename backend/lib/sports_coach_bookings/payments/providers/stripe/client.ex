defmodule SportsCoachBookings.Payments.Providers.Stripe.Client do
  @moduledoc """
  Thin, injectable HTTP client for the Stripe REST API.

  This is the **only** place a real network call to Stripe is made. It is
  configured through application env so tests never touch the network:

      config :sports_coach_bookings, :payments_stripe_client, MyStubClient

  A stub must export `request/4` with the same shape as `request/4` here and
  return `{:ok, decoded_body}` (a map) or `{:error, term}`.
  """

  @doc """
  Issues an HTTP request to the Stripe API.

  Options:

    * `:auth` — the platform secret key (Bearer)
    * `:account` — a connected account id, sent as the `Stripe-Account` header
      (used for direct charges)
    * `:params` — a map/list encoded as `application/x-www-form-urlencoded`
  """
  @callback request(
              method :: atom(),
              path :: String.t(),
              params :: map() | keyword(),
              opts :: keyword()
            ) ::
              {:ok, map()} | {:error, term()}

  @behaviour __MODULE__

  @impl true
  def request(method, path, params, opts \\ []) do
    url = base_url() <> path

    headers =
      [{"accept", "application/json"}]
      |> maybe_header("authorization", "Bearer " <> to_string(opts[:auth]))
      |> maybe_header("stripe-account", opts[:account])

    req =
      Req.new(
        method: method,
        url: url,
        headers: headers,
        form: __MODULE__.Form.encode(params),
        decode_body: true,
        retry: false
      )

    case Req.request(req) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:stripe_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp base_url do
    Application.get_env(
      :sports_coach_bookings,
      :payments_stripe_api_base,
      "https://api.stripe.com"
    )
  end

  defp maybe_header(headers, _name, nil), do: headers

  defp maybe_header(headers, name, value) when is_binary(value) and value != "",
    do: [{name, value} | headers]

  defp maybe_header(headers, name, value), do: [{name, to_string(value)} | headers]

  defmodule Form do
    @moduledoc """
    Flattens nested maps/lists into Stripe's bracket form encoding, e.g.
    `%{"line_items" => [%{"quantity" => 2}]}` becomes
    `[{"line_items[0][quantity]", "2"}]`.
    """

    @doc "Encodes `params` into a flat list of string pairs."
    @spec encode(map() | keyword()) :: [{String.t(), String.t()}]
    def encode(params) do
      params
      |> normalize()
      |> Enum.flat_map(fn {key, value} -> flatten(key, value) end)
    end

    defp flatten(prefix, value) when is_map(value) do
      Enum.flat_map(value, fn {key, nested} -> flatten("#{prefix}[#{key}]", nested) end)
    end

    defp flatten(prefix, value) when is_list(value) do
      value
      |> Enum.with_index()
      |> Enum.flat_map(fn {nested, index} -> flatten("#{prefix}[#{index}]", nested) end)
    end

    defp flatten(prefix, nil), do: [{prefix, ""}]

    defp flatten(prefix, value) when is_boolean(value),
      do: [{prefix, if(value, do: "true", else: "false")}]

    defp flatten(prefix, value), do: [{prefix, to_string(value)}]

    defp normalize(params) when is_list(params), do: params
    defp normalize(params) when is_map(params), do: Map.to_list(params)
  end
end
