defmodule SportsCoachBookingsWeb.Schemas.Inventory do
  @moduledoc """
  Inline OpenApiSpex schemas for the WP-08 inventory endpoints, in the style of
  `SportsCoachBookingsWeb.Schemas.Api`. Each function returns an
  `%OpenApiSpex.Schema{}` used directly in controller `operation/2` specs.
  """

  alias OpenApiSpex.Schema

  @option_values %Schema{
    type: :object,
    additionalProperties: %Schema{type: :string},
    description: "Map of option name to value, e.g. {\"size\": \"YM\"}"
  }

  @doc "A generic paginated list envelope around `item`."
  def list(item) do
    %Schema{
      type: :object,
      properties: %{
        data: %Schema{type: :array, items: item},
        next_cursor: %Schema{type: :string, nullable: true}
      },
      required: [:data]
    }
  end

  ## Products

  def product_request do
    %Schema{
      type: :object,
      properties: %{
        name: %Schema{type: :string},
        description: %Schema{type: :string, nullable: true},
        image_keys: %Schema{type: :array, items: %Schema{type: :string}},
        taxable: %Schema{type: :boolean},
        active: %Schema{type: :boolean},
        visible_in_portal: %Schema{type: :boolean},
        position: %Schema{type: :integer}
      },
      required: [:name]
    }
  end

  def product do
    %Schema{
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid},
        name: %Schema{type: :string},
        description: %Schema{type: :string, nullable: true},
        image_keys: %Schema{type: :array, items: %Schema{type: :string}},
        image_urls: %Schema{type: :array, items: %Schema{type: :string}},
        taxable: %Schema{type: :boolean},
        active: %Schema{type: :boolean},
        visible_in_portal: %Schema{type: :boolean},
        position: %Schema{type: :integer},
        inserted_at: %Schema{type: :string, format: :"date-time", nullable: true},
        updated_at: %Schema{type: :string, format: :"date-time", nullable: true}
      },
      required: [:id, :name, :active, :visible_in_portal]
    }
  end

  def product_list, do: list(product())

  def reorder_request do
    %Schema{
      type: :object,
      properties: %{ids: %Schema{type: :array, items: %Schema{type: :string, format: :uuid}}},
      required: [:ids]
    }
  end

  ## Variants

  def variant_request do
    %Schema{
      type: :object,
      properties: %{
        sku: %Schema{type: :string},
        option_values: @option_values,
        price: %Schema{type: :integer, description: "Minor units"},
        low_stock_threshold: %Schema{type: :integer, nullable: true},
        active: %Schema{type: :boolean}
      },
      required: [:sku, :price]
    }
  end

  def variant do
    %Schema{
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid},
        product_id: %Schema{type: :string, format: :uuid},
        sku: %Schema{type: :string},
        option_values: @option_values,
        price: %Schema{type: :integer},
        low_stock_threshold: %Schema{type: :integer, nullable: true},
        active: %Schema{type: :boolean},
        inserted_at: %Schema{type: :string, format: :"date-time", nullable: true},
        updated_at: %Schema{type: :string, format: :"date-time", nullable: true}
      },
      required: [:id, :product_id, :sku, :price, :active]
    }
  end

  def variant_list, do: list(variant())

  ## Stock

  def stock_receive_request do
    %Schema{
      type: :object,
      properties: %{
        quantity: %Schema{type: :integer},
        note: %Schema{type: :string, nullable: true}
      },
      required: [:quantity]
    }
  end

  def stock_adjust_request do
    %Schema{
      type: :object,
      properties: %{
        delta: %Schema{type: :integer, description: "Signed change to on-hand"},
        reason: %Schema{type: :string}
      },
      required: [:delta, :reason]
    }
  end

  def stock_level do
    %Schema{
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid},
        variant_id: %Schema{type: :string, format: :uuid},
        on_hand: %Schema{type: :integer},
        reserved: %Schema{type: :integer},
        available: %Schema{type: :integer},
        venue_id: %Schema{type: :string, format: :uuid, nullable: true},
        inserted_at: %Schema{type: :string, format: :"date-time", nullable: true},
        updated_at: %Schema{type: :string, format: :"date-time", nullable: true}
      },
      required: [:id, :variant_id, :on_hand, :reserved, :available]
    }
  end

  def stock_level_list, do: list(stock_level())

  def stock_movement do
    %Schema{
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid},
        variant_id: %Schema{type: :string, format: :uuid},
        delta: %Schema{type: :integer},
        kind: %Schema{
          type: :string,
          enum: ["received", "sold", "adjusted", "returned", "reserved", "released"]
        },
        order_id: %Schema{type: :string, format: :uuid, nullable: true},
        actor_type: %Schema{type: :string, nullable: true},
        actor_id: %Schema{type: :string, format: :uuid, nullable: true},
        note: %Schema{type: :string, nullable: true},
        inserted_at: %Schema{type: :string, format: :"date-time", nullable: true}
      },
      required: [:id, :variant_id, :delta, :kind]
    }
  end

  def stock_movement_list, do: list(stock_movement())

  ## Fulfillments

  def fulfillment do
    %Schema{
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid},
        order_line_id: %Schema{type: :string, format: :uuid},
        variant_id: %Schema{type: :string, format: :uuid, nullable: true},
        status: %Schema{
          type: :string,
          enum: ["pending", "ready_for_pickup", "picked_up", "cancelled"]
        },
        pickup_venue_id: %Schema{type: :string, format: :uuid, nullable: true},
        picked_up_at: %Schema{type: :string, format: :"date-time", nullable: true},
        picked_up_by: %Schema{type: :string, format: :uuid, nullable: true},
        inserted_at: %Schema{type: :string, format: :"date-time", nullable: true},
        updated_at: %Schema{type: :string, format: :"date-time", nullable: true}
      },
      required: [:id, :order_line_id, :status]
    }
  end

  def fulfillment_list, do: list(fulfillment())

  ## Portal shop

  def public_product do
    %Schema{
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid},
        name: %Schema{type: :string},
        description: %Schema{type: :string, nullable: true},
        image_urls: %Schema{type: :array, items: %Schema{type: :string}},
        availability: %Schema{type: :string, enum: ["in stock", "low stock", "sold out"]},
        variants: %Schema{
          type: :array,
          nullable: true,
          items: %Schema{
            type: :object,
            properties: %{
              id: %Schema{type: :string, format: :uuid},
              sku: %Schema{type: :string},
              option_values: @option_values,
              price: %Schema{type: :integer},
              availability: %Schema{type: :string, enum: ["in stock", "low stock", "sold out"]}
            }
          }
        }
      },
      required: [:id, :name, :availability]
    }
  end

  def public_product_list, do: list(public_product())

  def pickup do
    %Schema{
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid},
        order_line_id: %Schema{type: :string, format: :uuid},
        status: %Schema{
          type: :string,
          enum: ["pending", "ready_for_pickup", "picked_up", "cancelled"]
        },
        product_name: %Schema{type: :string, nullable: true},
        option_values: @option_values,
        pickup_venue_id: %Schema{type: :string, format: :uuid, nullable: true},
        picked_up_at: %Schema{type: :string, format: :"date-time", nullable: true},
        inserted_at: %Schema{type: :string, format: :"date-time", nullable: true}
      },
      required: [:id, :order_line_id, :status]
    }
  end

  def pickup_list, do: list(pickup())
end
