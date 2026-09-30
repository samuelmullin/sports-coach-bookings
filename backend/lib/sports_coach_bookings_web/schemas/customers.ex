defmodule SportsCoachBookingsWeb.Schemas.Customers do
  @moduledoc """
  Inline OpenApiSpex schema builders for the WP-02 customer and household
  endpoints.
  """

  alias OpenApiSpex.Schema

  @doc "A generic `{message: string}` acknowledgement."
  def message do
    %Schema{
      type: :object,
      properties: %{message: %Schema{type: :string}},
      required: [:message]
    }
  end

  def customer_user do
    %Schema{
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid},
        tenant_id: %Schema{type: :string, format: :uuid},
        email: %Schema{type: :string, format: :email},
        first_name: %Schema{type: :string},
        last_name: %Schema{type: :string},
        phone: %Schema{type: :string, nullable: true},
        confirmed: %Schema{type: :boolean},
        confirmed_at: %Schema{type: :string, nullable: true},
        active: %Schema{type: :boolean},
        terms_version: %Schema{type: :string, nullable: true},
        privacy_version: %Schema{type: :string, nullable: true},
        inserted_at: %Schema{type: :string, nullable: true}
      }
    }
  end

  def customer_list do
    %Schema{
      type: :object,
      properties: %{
        data: %Schema{type: :array, items: customer_user()},
        next_cursor: %Schema{type: :string, nullable: true}
      },
      required: [:data]
    }
  end

  def session_request do
    %Schema{
      type: :object,
      properties: %{
        email: %Schema{type: :string, format: :email},
        password: %Schema{type: :string, format: :password}
      },
      required: [:email, :password]
    }
  end

  def session_response do
    %Schema{
      type: :object,
      properties: %{customer_user: customer_user()},
      required: [:customer_user]
    }
  end

  def registration_request do
    %Schema{
      type: :object,
      properties: %{
        first_name: %Schema{type: :string},
        last_name: %Schema{type: :string},
        email: %Schema{type: :string, format: :email},
        phone: %Schema{
          type: :string,
          nullable: true,
          description: "E.164, or a national number with `phone_country`"
        },
        phone_country: %Schema{
          type: :string,
          nullable: true,
          description: "ISO 3166-1 alpha-2 country code for a national `phone`"
        },
        password: %Schema{type: :string, format: :password, minLength: 12},
        accept_terms: %Schema{type: :boolean},
        accept_privacy: %Schema{type: :boolean}
      },
      required: [
        :first_name,
        :last_name,
        :email,
        :password,
        :accept_terms,
        :accept_privacy
      ]
    }
  end

  def registration_response do
    %Schema{
      type: :object,
      properties: %{
        customer_user: customer_user(),
        household: household(),
        confirmation_token: %Schema{type: :string, nullable: true}
      },
      required: [:customer_user, :household]
    }
  end

  def token_request do
    %Schema{
      type: :object,
      properties: %{token: %Schema{type: :string}},
      required: [:token]
    }
  end

  def password_reset_request do
    %Schema{
      type: :object,
      properties: %{email: %Schema{type: :string, format: :email}},
      required: [:email]
    }
  end

  def password_reset_update_request do
    %Schema{
      type: :object,
      properties: %{
        token: %Schema{type: :string},
        password: %Schema{type: :string, format: :password, minLength: 12}
      },
      required: [:token, :password]
    }
  end

  def account_update_request do
    %Schema{
      type: :object,
      properties: %{
        first_name: %Schema{type: :string, nullable: true},
        last_name: %Schema{type: :string, nullable: true},
        phone: %Schema{type: :string, nullable: true},
        phone_country: %Schema{
          type: :string,
          nullable: true,
          description: "ISO 3166-1 alpha-2 country code for a national `phone`"
        }
      }
    }
  end

  def email_change_request do
    %Schema{
      type: :object,
      properties: %{email: %Schema{type: :string, format: :email}},
      required: [:email]
    }
  end

  def password_change_request do
    %Schema{
      type: :object,
      properties: %{password: %Schema{type: :string, format: :password, minLength: 12}},
      required: [:password]
    }
  end

  def notification_preferences do
    %Schema{
      type: :object,
      properties: %{
        marketing_opt_in: %Schema{type: :boolean},
        operational: %Schema{type: :boolean},
        transactional: %Schema{type: :boolean}
      },
      required: [:marketing_opt_in, :operational, :transactional]
    }
  end

  def notification_preferences_update do
    %Schema{
      type: :object,
      properties: %{marketing_opt_in: %Schema{type: :boolean, nullable: true}}
    }
  end

  def household do
    %Schema{
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid},
        tenant_id: %Schema{type: :string, format: :uuid},
        name: %Schema{type: :string, nullable: true},
        inserted_at: %Schema{type: :string, nullable: true}
      }
    }
  end

  def household_member do
    %Schema{
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid},
        tenant_id: %Schema{type: :string, format: :uuid},
        household_id: %Schema{type: :string, format: :uuid},
        customer_user_id: %Schema{type: :string, format: :uuid},
        role: %Schema{type: :string, enum: ["primary", "manager"]},
        relationship: %Schema{type: :string, nullable: true},
        customer_user: customer_user(),
        inserted_at: %Schema{type: :string, nullable: true}
      }
    }
  end

  def household_detail do
    %Schema{
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid},
        tenant_id: %Schema{type: :string, format: :uuid},
        name: %Schema{type: :string, nullable: true},
        inserted_at: %Schema{type: :string, nullable: true},
        members: %Schema{type: :array, items: household_member()}
      },
      required: [:id, :members]
    }
  end

  def household_list do
    %Schema{
      type: :object,
      properties: %{
        data: %Schema{type: :array, items: household()},
        next_cursor: %Schema{type: :string, nullable: true}
      },
      required: [:data]
    }
  end

  def invite_request do
    %Schema{
      type: :object,
      properties: %{
        email: %Schema{type: :string, format: :email},
        relationship: %Schema{type: :string, nullable: true}
      },
      required: [:email]
    }
  end

  def invite do
    %Schema{
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid},
        email: %Schema{type: :string, format: :email},
        relationship: %Schema{type: :string, nullable: true},
        expires_at: %Schema{type: :string},
        inserted_at: %Schema{type: :string, nullable: true}
      }
    }
  end

  def invite_response do
    %Schema{
      type: :object,
      properties: %{
        invite: invite(),
        token: %Schema{type: :string}
      },
      required: [:invite, :token]
    }
  end

  def invite_list do
    %Schema{
      type: :object,
      properties: %{data: %Schema{type: :array, items: invite()}},
      required: [:data]
    }
  end

  def invite_show do
    %Schema{
      type: :object,
      properties: %{
        email: %Schema{type: :string, format: :email},
        relationship: %Schema{type: :string, nullable: true},
        tenant_name: %Schema{type: :string},
        expired: %Schema{type: :boolean}
      }
    }
  end

  def accept_invite_request do
    %Schema{
      type: :object,
      properties: %{
        first_name: %Schema{type: :string, nullable: true},
        last_name: %Schema{type: :string, nullable: true},
        phone: %Schema{type: :string, nullable: true},
        phone_country: %Schema{
          type: :string,
          nullable: true,
          description: "ISO 3166-1 alpha-2 country code for a national `phone`"
        },
        password: %Schema{type: :string, format: :password, minLength: 12, nullable: true},
        accept_terms: %Schema{type: :boolean, nullable: true},
        accept_privacy: %Schema{type: :boolean, nullable: true}
      }
    }
  end

  def accept_invite_response do
    %Schema{
      type: :object,
      properties: %{
        customer_user: customer_user(),
        household: household(),
        member: household_member()
      },
      required: [:customer_user, :household, :member]
    }
  end

  def transfer_primary_request do
    %Schema{
      type: :object,
      properties: %{member_id: %Schema{type: :string, format: :uuid}},
      required: [:member_id]
    }
  end
end
