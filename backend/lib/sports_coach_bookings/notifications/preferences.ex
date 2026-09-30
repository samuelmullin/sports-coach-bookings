defmodule SportsCoachBookings.Notifications.Preferences do
  @moduledoc """
  Notification preferences per customer user or staff user. Tenant-owned.

  `marketing_opt_in` defaults to `false` (CASL express consent); `operational`
  and `transactional` are always on and cannot be turned off. The subject is
  stored polymorphically, so this module never touches another context's schema.

  This is the implementation wp-02's `Customers.Preferences` seam delegates to
  when `config :sports_coach_bookings, :customer_preferences_module` is set.
  Every function manages its own tenant transaction, so it is safe to call from
  a request process with no tenant transaction already open.
  """

  alias SportsCoachBookings.Core.TenantContext
  alias SportsCoachBookings.Notifications.NotificationPreference
  alias SportsCoachBookings.Repo

  @defaults %{marketing_opt_in: false, operational: true, transactional: true}

  @doc "The default preference values."
  @spec defaults() :: map()
  def defaults, do: @defaults

  @doc """
  Returns the preferences for a subject.

  A subject is a `%CustomerUser{}` / `%StaffUser{}` struct, a
  `%{type: :customer_user | :staff_user, id: id}` map, or `{type, id}`. Returns
  the documented defaults when no row exists or the subject is unknown.
  """
  @spec get(term()) :: map()
  def get(subject) do
    case subject_key(subject) do
      {type, id, tenant_id} -> tx(tenant_id, fn -> fetch(type, id, tenant_id) end)
      nil -> @defaults
    end
  end

  @doc """
  Upserts preferences for a subject. Only `marketing_opt_in` is user-controlled;
  `operational` and `transactional` are forced to `true`.

  Returns `{:ok, preferences}`.
  """
  @spec update(term(), map()) :: {:ok, map()}
  def update(subject, attrs) do
    {type, id, tenant_id} = subject_key(subject) || raise ArgumentError, "unknown subject"
    tx(tenant_id, fn -> persist(type, id, tenant_id, attrs || %{}) end)
  end

  @doc """
  Whether a recipient may receive a message in `category`.

  Operational and transactional mail is always allowed. Marketing requires
  `marketing_opt_in`. Raw `:email` recipients have no stored preference, so
  marketing is allowed only when the recipient map carries
  `marketing_opt_in: true`.
  """
  @spec allowed?(map(), atom()) :: boolean()
  def allowed?(_recipient, category) when category in [:transactional, :operational], do: true

  def allowed?(%{type: :email} = recipient, :marketing),
    do: truthy?(Map.get(recipient, :marketing_opt_in))

  def allowed?(recipient, :marketing), do: truthy?(get(recipient)[:marketing_opt_in])

  @doc "Whether the subject has opted in to marketing email."
  @spec marketing_opt_in?(term()) :: boolean()
  def marketing_opt_in?(subject), do: truthy?(get(subject)[:marketing_opt_in])

  defp fetch(type, id, tenant_id) do
    case Repo.get_by(NotificationPreference,
           tenant_id: tenant_id,
           subject_type: type,
           subject_id: id
         ) do
      nil -> @defaults
      preference -> to_map(preference)
    end
  end

  defp persist(type, id, tenant_id, attrs) do
    marketing = truthy?(fetch(attrs, :marketing_opt_in))

    existing =
      Repo.get_by(NotificationPreference,
        tenant_id: tenant_id,
        subject_type: type,
        subject_id: id
      ) || %NotificationPreference{}

    changeset =
      NotificationPreference.changeset(existing, %{
        tenant_id: tenant_id,
        subject_type: type,
        subject_id: id,
        marketing_opt_in: marketing,
        operational: true,
        transactional: true
      })

    case Repo.insert_or_update(changeset) do
      {:ok, preference} -> {:ok, to_map(preference)}
      {:error, _changeset} -> {:ok, Map.put(@defaults, :marketing_opt_in, marketing)}
    end
  end

  defp to_map(%NotificationPreference{} = preference) do
    %{
      marketing_opt_in: preference.marketing_opt_in,
      operational: preference.operational,
      transactional: preference.transactional
    }
  end

  defp subject_key(%{__struct__: module} = struct) do
    case struct_type(module) do
      nil -> nil
      type -> {type, Map.get(struct, :id), Map.get(struct, :tenant_id) || tenant()}
    end
  end

  defp subject_key(%{type: type, id: id} = map) when type in [:customer_user, :staff_user],
    do: {type, id, Map.get(map, :tenant_id) || tenant()}

  defp subject_key({type, id}) when type in [:customer_user, :staff_user],
    do: {type, id, tenant()}

  defp subject_key(_), do: nil

  defp struct_type(SportsCoachBookings.Customers.CustomerUser), do: :customer_user
  defp struct_type(SportsCoachBookings.Staff.StaffUser), do: :staff_user
  defp struct_type(_), do: nil

  defp tenant, do: TenantContext.get_tenant_id()

  defp tx(tenant_id, fun) when is_binary(tenant_id) do
    TenantContext.with_tenant(tenant_id, fn ->
      case Repo.with_tenant_tx(fun) do
        {:ok, result} -> result
        {:error, reason} -> {:error, reason}
      end
    end)
  end

  defp tx(_tenant_id, fun), do: fun.()

  defp fetch(map, key), do: Map.get(map, key) || Map.get(map, to_string(key))

  defp truthy?(value), do: value in [true, "true", "1", 1]
end
