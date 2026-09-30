defmodule SportsCoachBookings.Notifications.Suppressions do
  @moduledoc """
  Suppression store for hard bounces and complaints. All functions run inside a
  tenant transaction (see `SportsCoachBookings.Repo.with_tenant_tx/2`).
  """

  import Ecto.Query

  alias SportsCoachBookings.Core.TenantContext
  alias SportsCoachBookings.Notifications.Suppression
  alias SportsCoachBookings.Repo

  @doc "Whether `email` is suppressed for the tenant in context."
  @spec suppressed?(binary() | nil, binary()) :: boolean()
  def suppressed?(tenant_id, email) when is_binary(email) do
    tenant_id = tenant_id || TenantContext.get_tenant_id()

    Repo.exists?(from s in Suppression, where: s.tenant_id == ^tenant_id and s.email == ^email)
  end

  def suppressed?(_tenant_id, _email), do: false

  @doc """
  Adds `email` to the suppression list. Idempotent: re-suppressing is a no-op.
  """
  @spec suppress(binary() | nil, binary(), atom()) ::
          {:ok, Suppression.t()} | {:error, Ecto.Changeset.t()}
  def suppress(tenant_id, email, reason) when reason in [:bounce, :complaint] do
    tenant_id = tenant_id || TenantContext.get_tenant_id()

    %Suppression{}
    |> Suppression.changeset(%{tenant_id: tenant_id, email: email, reason: reason})
    |> Repo.insert(on_conflict: :nothing, conflict_target: [:tenant_id, :email])
  end

  @doc "Removes `email` from the suppression list (admin recovery path)."
  @spec unsuppress(binary() | nil, binary()) :: :ok
  def unsuppress(tenant_id, email) when is_binary(email) do
    tenant_id = tenant_id || TenantContext.get_tenant_id()

    Repo.delete_all(from s in Suppression, where: s.tenant_id == ^tenant_id and s.email == ^email)

    :ok
  end

  @doc "Lists the tenant's suppression entries, newest first."
  @spec list() :: [Suppression.t()]
  def list do
    Repo.all(from s in Suppression, order_by: [desc: s.inserted_at])
  end
end
