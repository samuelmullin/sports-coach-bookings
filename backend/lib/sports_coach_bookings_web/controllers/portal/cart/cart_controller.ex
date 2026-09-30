defmodule SportsCoachBookingsWeb.Portal.Cart.CartController do
  @moduledoc "Portal: the caller's cart and checkout price preview."

  use SportsCoachBookingsWeb, :controller
  use OpenApiSpex.ControllerSpecs

  action_fallback SportsCoachBookingsWeb.FallbackController

  alias SportsCoachBookings.Commerce
  alias SportsCoachBookings.Commerce.Policy
  alias SportsCoachBookingsWeb.CommerceJSON
  alias SportsCoachBookingsWeb.Schemas.Commerce, as: Schemas
  alias SportsCoachBookingsWeb.Schemas.ErrorResponse

  tags(["portal"])

  operation(:show,
    summary: "Get the caller's cart with a price preview",
    responses: [
      ok: {"Cart", "application/json", Schemas.cart()},
      forbidden: {"Forbidden", "application/json", ErrorResponse}
    ]
  )

  @doc "GET /api/portal/cart"
  def show(conn, _params) do
    with :ok <- authorize(conn, :view_cart, :cart) do
      render_cart(conn)
    end
  end

  operation(:price,
    summary: "Price the caller's cart without persisting an order",
    responses: [
      ok: {"Pricing", "application/json", Schemas.pricing()},
      unprocessable_entity: {"Pricing error", "application/json", ErrorResponse},
      forbidden: {"Forbidden", "application/json", ErrorResponse}
    ]
  )

  @doc "GET /api/portal/cart/price"
  def price(conn, _params) do
    with :ok <- authorize(conn, :price, :cart),
         {:ok, priced} <- Commerce.price_cart(household_id(conn)) do
      json(conn, CommerceJSON.pricing(priced))
    end
  end

  operation(:add_line,
    summary: "Add a package, product, or drop-in to the cart",
    request_body: {"Cart line", "application/json", Schemas.cart_line_request()},
    responses: [
      created: {"Cart", "application/json", Schemas.cart()},
      unprocessable_entity: {"Validation error", "application/json", ErrorResponse},
      forbidden: {"Forbidden", "application/json", ErrorResponse}
    ]
  )

  @doc "POST /api/portal/cart/lines"
  def add_line(conn, params) do
    with :ok <- authorize(conn, :add_line, :cart_line) do
      attrs = body(params)

      case add_by_type(conn, attrs) do
        %{} = cart -> conn |> put_status(:created) |> json(CommerceJSON.cart(cart))
        {:error, reason} -> {:error, reason}
      end
    end
  end

  operation(:update_line,
    summary: "Update a cart line's quantity",
    parameters: [id: [in: :path, type: :string, required: true]],
    request_body: {"Quantity", "application/json", Schemas.quantity_request()},
    responses: [
      ok: {"Cart", "application/json", Schemas.cart()},
      not_found: {"Not found", "application/json", ErrorResponse},
      unprocessable_entity: {"Validation error", "application/json", ErrorResponse},
      forbidden: {"Forbidden", "application/json", ErrorResponse}
    ]
  )

  @doc "PATCH /api/portal/cart/lines/:id"
  def update_line(conn, %{"id" => id} = params) do
    with :ok <- authorize(conn, :update_line, :cart_line) do
      update_quantity(conn, id, field(body(params), :quantity))
    end
  end

  defp update_quantity(_conn, _id, quantity) when not is_integer(quantity) do
    {:error, {:invalid_quantity, "quantity must be an integer"}}
  end

  defp update_quantity(conn, id, quantity) do
    case Commerce.update_cart_line(household_id(conn), id, quantity) do
      %{} = cart -> json(conn, CommerceJSON.cart(cart))
      {:error, reason} -> {:error, reason}
    end
  end

  operation(:remove_line,
    summary: "Remove a cart line",
    parameters: [id: [in: :path, type: :string, required: true]],
    responses: [
      ok: {"Cart", "application/json", Schemas.cart()},
      not_found: {"Not found", "application/json", ErrorResponse},
      forbidden: {"Forbidden", "application/json", ErrorResponse}
    ]
  )

  @doc "DELETE /api/portal/cart/lines/:id"
  def remove_line(conn, %{"id" => id}) do
    with :ok <- authorize(conn, :remove_line, :cart_line) do
      case Commerce.remove_cart_line(household_id(conn), id) do
        %{} = cart -> json(conn, CommerceJSON.cart(cart))
        {:error, reason} -> {:error, reason}
      end
    end
  end

  operation(:apply_discount,
    summary: "Apply a discount code to the cart",
    request_body: {"Discount", "application/json", Schemas.discount_request()},
    responses: [
      ok: {"Cart", "application/json", Schemas.cart()},
      forbidden: {"Forbidden", "application/json", ErrorResponse}
    ]
  )

  @doc "POST /api/portal/cart/discount"
  def apply_discount(conn, %{"code" => code}) do
    with :ok <- authorize(conn, :apply_discount, :cart) do
      _ = Commerce.apply_discount_code(household_id(conn), code)
      render_cart(conn)
    end
  end

  operation(:remove_discount,
    summary: "Remove the cart's discount code",
    responses: [
      ok: {"Cart", "application/json", Schemas.cart()},
      forbidden: {"Forbidden", "application/json", ErrorResponse}
    ]
  )

  @doc "DELETE /api/portal/cart/discount"
  def remove_discount(conn, _params) do
    with :ok <- authorize(conn, :remove_discount, :cart) do
      _ = Commerce.remove_discount_code(household_id(conn))
      render_cart(conn)
    end
  end

  ## Helpers

  defp add_by_type(conn, attrs) do
    household_id = household_id(conn)
    quantity = quantity(attrs)
    ref_id = ref_id(attrs)

    case type(attrs) do
      :package -> Commerce.add_package_to_cart(household_id, ref_id, quantity)
      :product -> Commerce.add_product_to_cart(household_id, ref_id, quantity)
      :drop_in -> Commerce.add_drop_in(household_id, ref_id)
      _ -> {:error, {:invalid_type, "type must be package, product, or drop_in"}}
    end
  end

  defp render_cart(conn) do
    cart = Commerce.get_or_create_cart(household_id(conn))

    priced =
      case Commerce.price_cart(household_id(conn)) do
        {:ok, priced} -> priced
        {:error, _reason} -> nil
      end

    json(conn, CommerceJSON.cart(cart, priced))
  end

  defp authorize(conn, action, resource) do
    Policy.authorize(conn.assigns[:current_customer_actor], action, resource)
  end

  defp household_id(conn), do: conn.assigns[:current_customer_actor].household_id

  defp body(params) do
    case Map.get(params, "line") do
      %{} = line -> line
      _ -> Map.drop(params, ["id"])
    end
  end

  defp type(attrs), do: normalize_type(field(attrs, :type))
  defp ref_id(attrs), do: field(attrs, :ref_id)
  defp quantity(attrs), do: field(attrs, :quantity) || 1

  defp normalize_type(type) when type in [:package, :product, :drop_in], do: type
  defp normalize_type("package"), do: :package
  defp normalize_type("product"), do: :product
  defp normalize_type("drop_in"), do: :drop_in
  defp normalize_type(_type), do: nil

  defp field(attrs, key) when is_map(attrs) do
    Map.get(attrs, to_string(key)) || Map.get(attrs, key)
  end
end
