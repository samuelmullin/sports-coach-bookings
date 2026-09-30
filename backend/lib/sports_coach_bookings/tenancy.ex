defmodule SportsCoachBookings.Tenancy do
  @moduledoc """
  Tenant signup, settings, and branding. Owned by WP-01.

  `tenants` is a platform table (no RLS). `branding` is tenant-owned. Signup
  orchestrates a global staff user, a tenant, its owner membership, default
  branding, and the `tenant.created` event in a single transaction.
  """

  import Ecto.Query

  alias SportsCoachBookings.Commerce
  alias SportsCoachBookings.Core.Audit
  alias SportsCoachBookings.Core.Tenant
  alias SportsCoachBookings.Core.TenantContext
  alias SportsCoachBookings.Core.TenantDomain
  alias SportsCoachBookings.Events
  alias SportsCoachBookings.Repo
  alias SportsCoachBookings.Staff
  alias SportsCoachBookings.Tenancy.Branding
  alias SportsCoachBookings.Tenancy.Contrast
  alias SportsCoachBookings.Tenancy.Storage

  @slug_format ~r/^[a-z0-9](?:[a-z0-9-]{1,61}[a-z0-9])?$/
  @default_timezone "America/Toronto"
  @default_currency "CAD"

  ## Tenants

  @doc "Fetches a tenant by id, raising when absent."
  @spec get_tenant!(binary()) :: Tenant.t()
  def get_tenant!(id), do: Repo.get!(Tenant, id, skip_tenant: true)

  @doc "Fetches a tenant by id, or `nil`."
  @spec get_tenant(binary()) :: Tenant.t() | nil
  def get_tenant(id), do: Repo.get(Tenant, id, skip_tenant: true)

  @doc "Fetches a tenant by slug, or `nil`."
  @spec get_tenant_by_slug(binary()) :: Tenant.t() | nil
  def get_tenant_by_slug(slug) when is_binary(slug), do: Repo.get_by(Tenant, slug: slug)

  @doc """
  Whether `slug` is available: well-formed, not reserved, and unused.

  Returns `:ok` or `{:error, reason}` where reason is one of `:invalid_slug`,
  `:reserved_slug`, `:slug_taken`.
  """
  @spec validate_slug(binary()) :: :ok | {:error, atom()}
  def validate_slug(slug) do
    with :ok <- validate_slug_format(slug),
         :ok <- validate_reserved(slug) do
      if Repo.get_by(Tenant, slug: slug), do: {:error, :slug_taken}, else: :ok
    end
  end

  @doc "Boolean form of `validate_slug/1`."
  @spec slug_available?(binary()) :: boolean()
  def slug_available?(slug), do: validate_slug(slug) == :ok

  @doc """
  Creates a tenant (and its owner membership and default branding).

  `opts[:staff_user]` uses the logged-in user; otherwise a new staff user is
  registered from `attrs` (`email`, `password`). Publishes `tenant.created`.
  """
  @spec signup(map(), keyword()) ::
          {:ok,
           %{
             tenant: Tenant.t(),
             staff_user: term(),
             membership: term(),
             branding: Branding.t()
           }}
          | {:error, atom() | Ecto.Changeset.t()}
  def signup(attrs, opts \\ []) do
    attrs = normalize(attrs)
    slug = attrs["slug"]

    with :ok <- validate_slug(slug) do
      Repo.transaction(fn -> create_tenant(attrs, slug, opts) end)
    end
  end

  defp create_tenant(attrs, slug, opts) do
    with {:ok, staff_user} <- resolve_signup_user(attrs, opts),
         {:ok, tenant} <- Repo.insert(tenant_changeset(attrs, slug)),
         {:ok, _domain} <- insert_domain(tenant),
         :ok <- put_tenant_context(tenant),
         {:ok, membership} <-
           Staff.upsert_membership(tenant.id, staff_user.id, :owner, display_name: attrs["name"]),
         {:ok, branding} <- insert_branding(tenant),
         {:ok, _event} <-
           Events.publish("tenant.created", %{tenant_id: tenant.id, slug: tenant.slug}) do
      %{tenant: tenant, staff_user: staff_user, membership: membership, branding: branding}
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  ## Settings

  @doc """
  Tenant settings for the resolved tenant, including the derived
  `currency_locked` flag (see `Commerce.any_paid_orders?/0`).
  """
  @spec tenant_settings(Tenant.t() | binary()) ::
          %{tenant: Tenant.t(), currency_locked: boolean()}
  def tenant_settings(tenant_or_id) do
    tenant =
      case tenant_or_id do
        %Tenant{} = tenant -> tenant
        id -> get_tenant!(id)
      end

    %{tenant: tenant, currency_locked: Commerce.any_paid_orders?()}
  end

  @doc """
  Updates name/contact_email/timezone, and currency when not locked.
  """
  @spec update_settings(term(), map()) ::
          {:ok, Tenant.t()} | {:error, :currency_locked | Ecto.Changeset.t()}
  def update_settings(actor, attrs) do
    attrs = normalize(attrs)
    tenant = TenantContext.get_tenant!()

    if currency_change?(tenant, attrs) and Commerce.any_paid_orders?() do
      {:error, :currency_locked}
    else
      persist_settings(actor, tenant, attrs)
    end
  end

  defp persist_settings(actor, tenant, attrs) do
    result =
      Repo.with_tenant_tx(fn ->
        with {:ok, updated} <-
               tenant |> Tenant.changeset(take_settings(attrs)) |> Repo.update(),
             {:ok, _} <- Audit.record(actor, "tenancy.settings.updated", updated, %{}) do
          {:ok, updated}
        end
      end)

    unwrap(result)
  end

  @doc "Soft-deletes the resolved tenant (marks it `deleted`, blocking access)."
  @spec delete_tenant(term()) :: {:ok, Tenant.t()} | {:error, Ecto.Changeset.t()}
  def delete_tenant(actor) do
    tenant = TenantContext.get_tenant!()

    result =
      Repo.with_tenant_tx(fn ->
        with {:ok, updated} <-
               tenant |> Tenant.changeset(%{status: :deleted}) |> Repo.update(),
             {:ok, _} <- Audit.record(actor, "tenancy.tenant.deleted", updated, %{}) do
          {:ok, updated}
        end
      end)

    unwrap(result)
  end

  ## Branding

  @doc "The resolved tenant's branding, or an unsaved default."
  @spec get_branding(Tenant.t()) :: Branding.t()
  def get_branding(%Tenant{} = tenant) do
    case read(fn ->
           Repo.one(from b in Branding, where: b.tenant_id == ^tenant.id, limit: 1)
         end) do
      %Branding{} = branding -> branding
      nil -> %Branding{tenant_id: tenant.id, social_links: %{}}
    end
  end

  @doc """
  Upserts the resolved tenant's branding.

  Returns `{:ok, branding, warnings}` where warnings are WCAG AA contrast
  warnings (never errors).
  """
  @spec update_branding(term(), map()) ::
          {:ok, Branding.t(), [String.t()]} | {:error, Ecto.Changeset.t()}
  def update_branding(actor, attrs) do
    tenant = TenantContext.get_tenant!()
    attrs = normalize(attrs)

    result =
      Repo.with_tenant_tx(fn ->
        branding = existing_or_new_branding(tenant)

        with {:ok, updated} <-
               branding
               |> Branding.changeset(Map.put(attrs, "tenant_id", tenant.id))
               |> Repo.insert_or_update(),
             {:ok, _} <- Audit.record(actor, "tenancy.branding.updated", updated, %{}) do
          {:ok, updated}
        end
      end)

    case unwrap(result) do
      {:ok, branding} -> {:ok, branding, Contrast.warnings(branding)}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Public theme payload for the cached portal branding endpoint."
  @spec public_branding(Tenant.t()) :: map()
  def public_branding(%Tenant{} = tenant) do
    branding = get_branding(tenant)

    %{
      tenant: %{name: tenant.name, slug: tenant.slug},
      theme: %{
        primary_color: branding.primary_color,
        secondary_color: branding.secondary_color,
        accent_color: branding.accent_color,
        background_color: branding.background_color,
        text_color: branding.text_color,
        font_family: branding.font_family
      },
      assets: %{
        logo_url: Branding.asset_url(branding.logo_key),
        favicon_url: Branding.asset_url(branding.favicon_key)
      },
      social_links: branding.social_links,
      email_footer_text: branding.email_footer_text
    }
  end

  @doc """
  Branding for transactional email rendering (used by WP-05).

  Safe to call outside a request: it sets the tenant context for the read.
  """
  @spec branding_for_email(binary()) :: map()
  def branding_for_email(tenant_id) do
    tenant = get_tenant!(tenant_id)

    TenantContext.with_tenant(tenant, fn ->
      branding = get_branding(tenant)

      %{
        tenant_name: tenant.name,
        logo_url: Branding.asset_url(branding.logo_key),
        primary_color: branding.primary_color,
        secondary_color: branding.secondary_color,
        accent_color: branding.accent_color,
        background_color: branding.background_color,
        text_color: branding.text_color,
        font_family: branding.font_family,
        email_footer_text: branding.email_footer_text,
        social_links: branding.social_links
      }
    end)
  end

  @doc "Presigns a branding asset upload after validating type and size."
  @spec presign_upload(term(), map()) ::
          {:ok, Storage.presigned()} | {:error, term()}
  def presign_upload(_actor, attrs) do
    Storage.presign_put(attrs, TenantContext.get_tenant_id())
  end

  ## Private helpers

  defp resolve_signup_user(attrs, opts) do
    case opts[:staff_user] do
      %{} = staff_user ->
        {:ok, staff_user}

      nil ->
        Staff.register_staff_user(%{email: attrs["email"], password: attrs["password"]})
    end
  end

  defp tenant_changeset(attrs, slug) do
    Tenant.changeset(%Tenant{}, %{
      name: attrs["name"],
      slug: slug,
      timezone: attrs["timezone"] || @default_timezone,
      currency: attrs["currency"] || @default_currency,
      contact_email: attrs["contact_email"]
    })
  end

  defp insert_domain(tenant) do
    host = "#{tenant.slug}.#{base_domain()}"

    case Repo.get_by(TenantDomain, host: host) do
      nil -> Repo.insert(%TenantDomain{tenant_id: tenant.id, host: host, primary: true})
      existing -> {:ok, existing}
    end
  end

  defp put_tenant_context(tenant) do
    TenantContext.put_tenant(tenant)
    Repo.set_tenant_guc(tenant.id)
    :ok
  end

  defp insert_branding(tenant) do
    %Branding{}
    |> Branding.changeset(%{tenant_id: tenant.id})
    |> Repo.insert()
  end

  defp existing_or_new_branding(tenant) do
    case Repo.one(from b in Branding, where: b.tenant_id == ^tenant.id, limit: 1) do
      %Branding{} = branding -> branding
      nil -> %Branding{tenant_id: tenant.id, social_links: %{}}
    end
  end

  defp validate_slug_format(slug) when is_binary(slug) do
    if Regex.match?(@slug_format, slug), do: :ok, else: {:error, :invalid_slug}
  end

  defp validate_slug_format(_slug), do: {:error, :invalid_slug}

  defp validate_reserved(slug) do
    reserved = Application.get_env(:sports_coach_bookings, :reserved_slugs, [])
    if slug in reserved, do: {:error, :reserved_slug}, else: :ok
  end

  defp currency_change?(tenant, attrs) do
    case attrs["currency"] do
      nil -> false
      value -> value != tenant.currency
    end
  end

  defp take_settings(attrs) do
    attrs
    |> Map.take(["name", "contact_email", "timezone", "currency"])
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  defp read(fun) do
    case Repo.with_tenant_tx(fun) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  defp unwrap({:ok, result}), do: result
  defp unwrap({:error, reason}), do: {:error, reason}

  defp normalize(attrs), do: Map.new(attrs, fn {k, v} -> {to_string(k), v} end)

  defp base_domain,
    do: Application.get_env(:sports_coach_bookings, :base_domain, "sportscoachbookings.com")
end
