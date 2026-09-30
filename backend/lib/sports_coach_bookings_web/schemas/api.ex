defmodule SportsCoachBookingsWeb.Schemas.Api do
  @moduledoc """
  Inline OpenApiSpex schema builders for the WP-01 platform/staff/portal
  endpoints. Each function returns an `%OpenApiSpex.Schema{}` used directly in
  controller `operation/2` specs.
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

  def tenant do
    %Schema{
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid},
        name: %Schema{type: :string},
        slug: %Schema{type: :string},
        status: %Schema{type: :string},
        timezone: %Schema{type: :string},
        currency: %Schema{type: :string},
        contact_email: %Schema{type: :string, nullable: true}
      }
    }
  end

  def staff_user do
    %Schema{
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid},
        email: %Schema{type: :string, format: :email},
        confirmed: %Schema{type: :boolean},
        confirmed_at: %Schema{type: :string, nullable: true},
        inserted_at: %Schema{type: :string, nullable: true}
      }
    }
  end

  def membership do
    %Schema{
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid},
        tenant_id: %Schema{type: :string, format: :uuid},
        staff_user_id: %Schema{type: :string, format: :uuid},
        role: %Schema{type: :string, enum: ["owner", "admin", "coach"]},
        status: %Schema{type: :string, enum: ["active", "removed"]},
        display_name: %Schema{type: :string, nullable: true},
        bio: %Schema{type: :string, nullable: true},
        photo_key: %Schema{type: :string, nullable: true},
        inserted_at: %Schema{type: :string, nullable: true},
        staff_user: staff_user(),
        tenant: tenant()
      }
    }
  end

  def membership_list do
    %Schema{
      type: :object,
      properties: %{data: %Schema{type: :array, items: membership()}},
      required: [:data]
    }
  end

  def me do
    %Schema{
      type: :object,
      properties: %{
        staff_user: staff_user(),
        memberships: %Schema{type: :array, items: membership()}
      },
      required: [:staff_user, :memberships]
    }
  end

  def membership_result do
    %Schema{
      type: :object,
      properties: %{membership: membership(), staff_user: staff_user()},
      required: [:membership, :staff_user]
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
      properties: %{staff_user: staff_user()},
      required: [:staff_user]
    }
  end

  def registration_request do
    %Schema{
      type: :object,
      properties: %{
        email: %Schema{type: :string, format: :email},
        password: %Schema{type: :string, format: :password, minLength: 12}
      },
      required: [:email, :password]
    }
  end

  def signup_request do
    %Schema{
      type: :object,
      properties: %{
        name: %Schema{type: :string},
        slug: %Schema{type: :string},
        email: %Schema{type: :string, format: :email},
        password: %Schema{type: :string, format: :password, minLength: 12},
        timezone: %Schema{type: :string, nullable: true},
        currency: %Schema{type: :string, nullable: true},
        contact_email: %Schema{type: :string, format: :email, nullable: true}
      },
      required: [:name, :slug, :email, :password]
    }
  end

  def signup_response do
    %Schema{
      type: :object,
      properties: %{
        tenant: tenant(),
        staff_user: staff_user(),
        membership: membership()
      },
      required: [:tenant, :staff_user, :membership]
    }
  end

  def slug_response do
    %Schema{
      type: :object,
      properties: %{
        slug: %Schema{type: :string},
        available: %Schema{type: :boolean},
        reason: %Schema{type: :string, nullable: true}
      },
      required: [:slug, :available]
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

  def token_request do
    %Schema{
      type: :object,
      properties: %{token: %Schema{type: :string}},
      required: [:token]
    }
  end

  def invite_request do
    %Schema{
      type: :object,
      properties: %{
        email: %Schema{type: :string, format: :email},
        role: %Schema{type: :string, enum: ["owner", "admin", "coach"]}
      },
      required: [:email, :role]
    }
  end

  def invite do
    %Schema{
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid},
        email: %Schema{type: :string, format: :email},
        role: %Schema{type: :string, enum: ["owner", "admin", "coach"]},
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

  def accept_invite_request do
    %Schema{
      type: :object,
      properties: %{password: %Schema{type: :string, format: :password, minLength: 12}}
    }
  end

  def invite_show_response do
    %Schema{
      type: :object,
      properties: %{
        email: %Schema{type: :string, format: :email},
        role: %Schema{type: :string, enum: ["owner", "admin", "coach"]},
        tenant_name: %Schema{type: :string},
        expired: %Schema{type: :boolean}
      }
    }
  end

  def role_update_request do
    %Schema{
      type: :object,
      properties: %{
        role: %Schema{type: :string, enum: ["owner", "admin", "coach"]}
      },
      required: [:role]
    }
  end

  def transfer_ownership_request do
    %Schema{
      type: :object,
      properties: %{membership_id: %Schema{type: :string, format: :uuid}},
      required: [:membership_id]
    }
  end

  def settings do
    %Schema{
      type: :object,
      properties: %{
        tenant: tenant(),
        currency_locked: %Schema{type: :boolean}
      },
      required: [:tenant, :currency_locked]
    }
  end

  def settings_update_request do
    %Schema{
      type: :object,
      properties: %{
        name: %Schema{type: :string, nullable: true},
        contact_email: %Schema{type: :string, format: :email, nullable: true},
        timezone: %Schema{type: :string, nullable: true},
        currency: %Schema{type: :string, nullable: true}
      }
    }
  end

  def branding_update_request do
    %Schema{
      type: :object,
      properties: %{
        logo_key: %Schema{type: :string, nullable: true},
        favicon_key: %Schema{type: :string, nullable: true},
        primary_color: %Schema{type: :string, nullable: true},
        secondary_color: %Schema{type: :string, nullable: true},
        accent_color: %Schema{type: :string, nullable: true},
        background_color: %Schema{type: :string, nullable: true},
        text_color: %Schema{type: :string, nullable: true},
        font_family: %Schema{type: :string, nullable: true},
        email_footer_text: %Schema{type: :string, nullable: true},
        social_links: %Schema{type: :object, additionalProperties: true}
      }
    }
  end

  def branding do
    %Schema{
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid, nullable: true},
        logo_url: %Schema{type: :string, nullable: true},
        favicon_url: %Schema{type: :string, nullable: true},
        logo_key: %Schema{type: :string, nullable: true},
        favicon_key: %Schema{type: :string, nullable: true},
        primary_color: %Schema{type: :string, nullable: true},
        secondary_color: %Schema{type: :string, nullable: true},
        accent_color: %Schema{type: :string, nullable: true},
        background_color: %Schema{type: :string, nullable: true},
        text_color: %Schema{type: :string, nullable: true},
        font_family: %Schema{type: :string, nullable: true},
        email_footer_text: %Schema{type: :string, nullable: true},
        social_links: %Schema{type: :object, additionalProperties: true},
        warnings: %Schema{type: :array, items: %Schema{type: :string}, nullable: true}
      }
    }
  end

  def public_branding do
    %Schema{
      type: :object,
      properties: %{
        tenant: %Schema{
          type: :object,
          properties: %{
            name: %Schema{type: :string},
            slug: %Schema{type: :string}
          }
        },
        theme: %Schema{
          type: :object,
          properties: %{
            primary_color: %Schema{type: :string, nullable: true},
            secondary_color: %Schema{type: :string, nullable: true},
            accent_color: %Schema{type: :string, nullable: true},
            background_color: %Schema{type: :string, nullable: true},
            text_color: %Schema{type: :string, nullable: true},
            font_family: %Schema{type: :string, nullable: true}
          }
        },
        assets: %Schema{
          type: :object,
          properties: %{
            logo_url: %Schema{type: :string, nullable: true},
            favicon_url: %Schema{type: :string, nullable: true}
          }
        },
        social_links: %Schema{type: :object, additionalProperties: true},
        email_footer_text: %Schema{type: :string, nullable: true}
      }
    }
  end

  def upload_request do
    %Schema{
      type: :object,
      properties: %{
        filename: %Schema{type: :string},
        content_type: %Schema{
          type: :string,
          enum: ["image/png", "image/jpeg", "image/webp", "image/svg+xml"]
        },
        byte_size: %Schema{type: :integer}
      },
      required: [:filename, :content_type, :byte_size]
    }
  end

  def upload_response do
    %Schema{
      type: :object,
      properties: %{
        key: %Schema{type: :string},
        upload_url: %Schema{type: :string},
        method: %Schema{type: :string},
        headers: %Schema{type: :object, additionalProperties: true},
        expires_at: %Schema{type: :string}
      },
      required: [:key, :upload_url]
    }
  end
end
