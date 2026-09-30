defmodule SportsCoachBookingsWeb.Schemas.Commerce do
  @moduledoc """
  Inline OpenApiSpex schemas for the WP-13 commerce endpoints, in the style of
  `SportsCoachBookingsWeb.Schemas.Api`.
  """

  alias OpenApiSpex.Schema
  alias SportsCoachBookings.Commerce.Order

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

  def cart_line do
    %Schema{
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid},
        cart_id: %Schema{type: :string, format: :uuid},
        type: %Schema{type: :string, enum: ["package", "product", "drop_in"]},
        ref_id: %Schema{type: :string, format: :uuid},
        quantity: %Schema{type: :integer}
      },
      required: [:id, :cart_id, :type, :ref_id, :quantity]
    }
  end

  def priced_line do
    %Schema{
      type: :object,
      properties: %{
        type: %Schema{type: :string, enum: ["package", "product", "drop_in"]},
        ref_id: %Schema{type: :string, format: :uuid},
        description: %Schema{type: :string, nullable: true},
        unit_price: %Schema{type: :integer},
        quantity: %Schema{type: :integer},
        amount: %Schema{type: :integer},
        discount_amount: %Schema{type: :integer},
        tax_amount: %Schema{type: :integer},
        line_total: %Schema{type: :integer},
        taxable: %Schema{type: :boolean},
        available: %Schema{type: :integer, nullable: true}
      }
    }
  end

  def pricing do
    %Schema{
      type: :object,
      properties: %{
        lines: %Schema{type: :array, items: priced_line()},
        subtotal: %Schema{type: :integer},
        discount_total: %Schema{type: :integer},
        tax_total: %Schema{type: :integer},
        total: %Schema{type: :integer}
      },
      required: [:lines, :subtotal, :discount_total, :tax_total, :total]
    }
  end

  def cart do
    %Schema{
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid},
        household_id: %Schema{type: :string, format: :uuid},
        discount_code: %Schema{type: :string, nullable: true},
        expires_at: %Schema{type: :string, format: :"date-time", nullable: true},
        lines: %Schema{type: :array, items: cart_line()},
        pricing: %Schema{allOf: [pricing()], nullable: true}
      },
      required: [:id, :household_id, :lines]
    }
  end

  def cart_line_request do
    %Schema{
      type: :object,
      properties: %{
        type: %Schema{type: :string, enum: ["package", "product", "drop_in"]},
        ref_id: %Schema{type: :string, format: :uuid},
        quantity: %Schema{type: :integer, minimum: 1, default: 1}
      },
      required: [:type, :ref_id]
    }
  end

  def quantity_request do
    %Schema{
      type: :object,
      properties: %{quantity: %Schema{type: :integer, minimum: 0}},
      required: [:quantity]
    }
  end

  def discount_request do
    %Schema{
      type: :object,
      properties: %{code: %Schema{type: :string}},
      required: [:code]
    }
  end

  def order_line do
    %Schema{
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid},
        order_id: %Schema{type: :string, format: :uuid},
        type: %Schema{type: :string, enum: ["package", "product", "drop_in"]},
        ref_id: %Schema{type: :string, format: :uuid},
        booking_id: %Schema{type: :string, format: :uuid, nullable: true},
        description: %Schema{type: :string},
        unit_price: %Schema{type: :integer},
        quantity: %Schema{type: :integer},
        discount_amount: %Schema{type: :integer},
        tax_amount: %Schema{type: :integer},
        line_total: %Schema{type: :integer},
        refunded_amount: %Schema{type: :integer},
        taxable: %Schema{type: :boolean}
      }
    }
  end

  def order do
    %Schema{
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid},
        number: %Schema{type: :string},
        household_id: %Schema{type: :string, format: :uuid},
        status: %Schema{type: :string, enum: enum_strings(statuses())},
        currency: %Schema{type: :string},
        subtotal: %Schema{type: :integer},
        discount_total: %Schema{type: :integer},
        tax_total: %Schema{type: :integer},
        total: %Schema{type: :integer},
        refunded_total: %Schema{type: :integer},
        discount_id: %Schema{type: :string, format: :uuid, nullable: true},
        payment_method: %Schema{type: :string, enum: ["online", "offline"], nullable: true},
        payment_id: %Schema{type: :string, format: :uuid, nullable: true},
        expires_at: %Schema{type: :string, format: :"date-time", nullable: true},
        paid_at: %Schema{type: :string, format: :"date-time", nullable: true},
        inserted_at: %Schema{type: :string, format: :"date-time", nullable: true},
        lines: %Schema{type: :array, items: order_line()}
      },
      required: [:id, :number, :household_id, :status, :currency, :total]
    }
  end

  def order_list, do: list(order())

  def checkout_result do
    %Schema{
      type: :object,
      properties: %{
        order: order(),
        redirect_url: %Schema{
          type: :string,
          format: :uri,
          nullable: true,
          description: "Hosted provider checkout URL; null for zero-total orders"
        }
      },
      required: [:order]
    }
  end

  def refund_request do
    %Schema{
      type: :object,
      properties: %{
        order_line_id: %Schema{
          type: :string,
          format: :uuid,
          nullable: true,
          description: "Line to refund; omit to refund every open line"
        },
        amount: %Schema{
          type: :integer,
          nullable: true,
          description: "Minor units; defaults to the line's refundable balance"
        },
        reason: %Schema{type: :string, nullable: true},
        force: %Schema{
          type: :boolean,
          nullable: true,
          description: "Refund a package line even if its credits were used (audited)"
        }
      }
    }
  end

  def offline_order_line_request do
    %Schema{
      type: :object,
      properties: %{
        type: %Schema{type: :string, enum: ["package", "product", "drop_in"]},
        ref_id: %Schema{type: :string, format: :uuid},
        quantity: %Schema{type: :integer, minimum: 1, default: 1}
      },
      required: [:type, :ref_id]
    }
  end

  def offline_order_request do
    %Schema{
      type: :object,
      properties: %{
        household_id: %Schema{type: :string, format: :uuid},
        discount_code: %Schema{type: :string, nullable: true},
        note: %Schema{type: :string, nullable: true},
        lines: %Schema{type: :array, items: offline_order_line_request()}
      },
      required: [:household_id, :lines]
    }
  end

  def refund_result do
    %Schema{
      type: :object,
      properties: %{
        line: order_line(),
        payment_refunded: %Schema{type: :boolean},
        status: %Schema{type: :string}
      }
    }
  end

  def refund_response do
    %Schema{
      type: :object,
      properties: %{refunds: %Schema{type: :array, items: refund_result()}},
      required: [:refunds]
    }
  end

  defp statuses, do: Order.statuses()

  defp enum_strings(atoms), do: Enum.map(atoms, &Atom.to_string/1)
end
