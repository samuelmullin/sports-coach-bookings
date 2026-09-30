defmodule SportsCoachBookings.Policies do
  @moduledoc """
  Cancellation & rebooking policies. Owned by WP-10.

  A tenant configures named `CancellationPolicy` rows, exactly one of which is
  the default. A policy may be assigned to individual offerings via
  `OfferingPolicyAssignment`; an assignment overrides the default.

  `snapshot_for/1` returns the JSON-serialisable snapshot WP-14 stores on every
  booking. The snapshot is self-contained — it carries the policy id, version,
  customer-facing summary, and the full rules — so the pure
  `Policies.Engine.evaluate/2` can compute an outcome later without touching the
  database. Editing a policy bumps its version; existing bookings keep their
  snapshot.

  All functions are tenant-scoped: callers place the tenant in context (via
  `SportsCoachBookingsWeb.Plugs.ResolveTenant` in requests or
  `SportsCoachBookings.DataCase.put_tenant/1` in tests) and every function runs
  inside `SportsCoachBookings.Repo.with_tenant_tx/2` so RLS applies.
  """

  import Ecto.Query

  alias Ecto.Multi
  alias SportsCoachBookings.Catalog
  alias SportsCoachBookings.Core.Audit
  alias SportsCoachBookings.Core.Money
  alias SportsCoachBookings.Core.Pagination
  alias SportsCoachBookings.Core.Policy, as: PolicyBehaviour
  alias SportsCoachBookings.Core.TenantContext
  alias SportsCoachBookings.Policies.CancellationPolicy
  alias SportsCoachBookings.Policies.Engine
  alias SportsCoachBookings.Policies.OfferingPolicyAssignment
  alias SportsCoachBookings.Policies.Rules
  alias SportsCoachBookings.Repo

  @default_name "Standard Cancellation Policy"

  ## Policies

  @doc "Lists cancellation policies, optionally filtered by `:active` / `:is_default`."
  @spec list_policies(map() | keyword()) :: [CancellationPolicy.t()]
  def list_policies(filters \\ %{}) do
    filters = normalize_filters(filters)

    read(fn ->
      CancellationPolicy
      |> where_active(filters)
      |> where_default(filters)
      |> order_by([p], desc: p.is_default, asc: p.name)
      |> Repo.all()
    end)
  end

  @doc "Paginates cancellation policies. Returns `%{data: [...], next_cursor: ...}`."
  @spec page_policies(map() | keyword(), map() | keyword()) ::
          %{data: [CancellationPolicy.t()], next_cursor: binary() | nil}
  def page_policies(filters \\ %{}, params \\ %{}) do
    filters = normalize_filters(filters)

    read(fn ->
      query =
        CancellationPolicy
        |> where_active(filters)
        |> where_default(filters)

      {rows, cursor} = Pagination.paginate(query, params)
      %{data: rows, next_cursor: cursor}
    end)
  end

  @doc "Fetches a policy, raising if it does not exist for this tenant."
  @spec get_policy!(binary()) :: CancellationPolicy.t()
  def get_policy!(id), do: read(fn -> Repo.get!(CancellationPolicy, id) end)

  @doc "Fetches a policy, returning `{:error, :not_found}` when absent."
  @spec fetch_policy(binary()) :: {:ok, CancellationPolicy.t()} | {:error, :not_found}
  def fetch_policy(id), do: read(fn -> fetch_record(CancellationPolicy, id) end)

  @doc "Returns the tenant's active default policy, or `nil`."
  @spec get_default_policy() :: CancellationPolicy.t() | nil
  def get_default_policy, do: read(fn -> current_default() end)

  @doc """
  Creates a policy.

  The first policy created for a tenant becomes the default automatically; later
  policies may opt in with `is_default: true`.
  """
  @spec create_policy(PolicyBehaviour.actor(), map() | keyword()) ::
          {:ok, CancellationPolicy.t()} | {:error, Ecto.Changeset.t()}
  def create_policy(actor, attrs) do
    Multi.new()
    |> Multi.run(:policy, fn _repo, _changes -> do_create_policy(attrs) end)
    |> Multi.run(:audit, fn _repo, %{policy: policy} ->
      Audit.record(actor, "policies.policy.created", policy, %{})
    end)
    |> run_multi(:policy)
  end

  @doc """
  Updates a policy, incrementing its `version`. Existing bookings keep their
  snapshot.
  """
  @spec update_policy(PolicyBehaviour.actor(), binary(), map() | keyword()) ::
          {:ok, CancellationPolicy.t()}
          | {:error, :not_found}
          | {:error, Ecto.Changeset.t()}
  def update_policy(actor, id, attrs) do
    Multi.new()
    |> Multi.run(:policy, fn _repo, _changes -> fetch_record(CancellationPolicy, id) end)
    |> Multi.run(:updated, fn _repo, %{policy: policy} -> do_update_policy(policy, attrs) end)
    |> Multi.run(:audit, fn _repo, %{updated: policy} ->
      Audit.record(actor, "policies.policy.updated", policy, %{version: policy.version})
    end)
    |> run_multi(:updated)
  end

  @doc "Archives (deactivates and un-defaults) a policy."
  @spec archive_policy(PolicyBehaviour.actor(), binary()) ::
          {:ok, CancellationPolicy.t()}
          | {:error, :not_found}
          | {:error, Ecto.Changeset.t()}
  def archive_policy(actor, id) do
    Multi.new()
    |> Multi.run(:policy, fn _repo, _changes -> fetch_record(CancellationPolicy, id) end)
    |> Multi.run(:updated, fn _repo, %{policy: policy} -> do_archive_policy(policy) end)
    |> Multi.run(:audit, fn _repo, %{updated: policy} ->
      Audit.record(actor, "policies.policy.archived", policy, %{})
    end)
    |> run_multi(:updated)
  end

  @doc "Makes `id` the tenant's default policy."
  @spec set_default(PolicyBehaviour.actor(), binary()) ::
          {:ok, CancellationPolicy.t()}
          | {:error, :not_found}
          | {:error, Ecto.Changeset.t()}
  def set_default(actor, id) do
    Multi.new()
    |> Multi.run(:policy, fn _repo, _changes -> fetch_record(CancellationPolicy, id) end)
    |> Multi.run(:updated, fn _repo, %{policy: policy} -> do_set_default(policy) end)
    |> Multi.run(:audit, fn _repo, %{updated: policy} ->
      Audit.record(actor, "policies.policy.default_set", policy, %{})
    end)
    |> run_multi(:updated)
  end

  ## Assignments

  @doc "Assigns one offering to a policy (overriding the default)."
  @spec assign_offering(PolicyBehaviour.actor(), binary(), binary()) ::
          {:ok, OfferingPolicyAssignment.t()}
          | {:error, :not_found}
          | {:error, Ecto.Changeset.t()}
  def assign_offering(actor, policy_id, offering_id) do
    case assign_offerings(actor, policy_id, [offering_id]) do
      {:ok, [assignment]} -> {:ok, assignment}
      other -> other
    end
  end

  @doc "Assigns a list of offerings to a policy."
  @spec assign_offerings(PolicyBehaviour.actor(), binary(), [binary()]) ::
          {:ok, [OfferingPolicyAssignment.t()]}
          | {:error, :not_found}
          | {:error, Ecto.Changeset.t()}
  def assign_offerings(actor, policy_id, offering_ids) do
    Multi.new()
    |> Multi.run(:policy, fn _repo, _changes -> fetch_record(CancellationPolicy, policy_id) end)
    |> Multi.run(:assignments, fn _repo, %{policy: policy} ->
      do_assign(policy, offering_ids)
    end)
    |> Multi.run(:audit, fn _repo, %{policy: policy} ->
      Audit.record(actor, "policies.assignment.updated", policy, %{offering_ids: offering_ids})
    end)
    |> run_multi(:assignments)
  end

  @doc "Removes any policy assignment for an offering."
  @spec unassign_offering(PolicyBehaviour.actor(), binary()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def unassign_offering(actor, offering_id) do
    Multi.new()
    |> Multi.run(:delete, fn _repo, _changes ->
      {count, _} =
        Repo.delete_all(from a in OfferingPolicyAssignment, where: a.offering_id == ^offering_id)

      {:ok, count}
    end)
    |> Multi.run(:audit, fn _repo, %{delete: count} ->
      Audit.record(actor, "policies.assignment.removed", nil, %{
        offering_id: offering_id,
        removed: count
      })
    end)
    |> run_multi(:delete)
  end

  @doc "The offering ids currently assigned to a policy."
  @spec assigned_offering_ids(binary()) :: [binary()]
  def assigned_offering_ids(policy_id) do
    read(fn ->
      Repo.all(
        from a in OfferingPolicyAssignment,
          where: a.cancellation_policy_id == ^policy_id,
          order_by: [asc: a.inserted_at],
          select: a.offering_id
      )
    end)
  end

  @doc "The policy that applies to an offering (its assignment, else the default), or `nil`."
  @spec policy_for_offering(binary()) :: CancellationPolicy.t() | nil
  def policy_for_offering(offering_id) do
    case read(fn -> do_policy_for_offering(offering_id) end) do
      {:error, _reason} -> nil
      policy -> policy
    end
  end

  ## Snapshot + engine

  @doc """
  Returns the JSON-serialisable policy snapshot to store on a booking.

  Resolves the offering's assigned policy (falling back to the tenant default,
  then to a built-in default) and embeds the rules, policy id, version, and
  customer-facing summary.
  """
  @spec snapshot_for(binary()) :: map()
  def snapshot_for(offering_id) do
    case Repo.with_tenant_tx(fn -> do_policy_for_offering(offering_id) end) do
      {:ok, nil} -> default_snapshot()
      {:ok, policy} -> snapshot(policy)
      _ -> default_snapshot()
    end
  end

  @doc "Builds the JSON-serialisable snapshot for a policy struct."
  @spec snapshot(CancellationPolicy.t()) :: map()
  def snapshot(%CancellationPolicy{} = policy) do
    %{
      "policy_id" => policy.id,
      "policy_name" => policy.name,
      "policy_version" => policy.version,
      "summary" => policy.customer_facing_summary,
      "rules" => Rules.to_map(policy.rules)
    }
  end

  @doc "The built-in default snapshot used when a tenant has no policy configured."
  @spec default_snapshot() :: map()
  def default_snapshot do
    %{
      "policy_id" => nil,
      "policy_name" => @default_name,
      "policy_version" => 0,
      "summary" => Rules.default_summary(),
      "rules" => Rules.default_map()
    }
  end

  @doc """
  The customer-facing policy summary for an offering (portal, before a booking).
  """
  @spec summary_for_offering(binary()) :: map()
  def summary_for_offering(offering_id) do
    snapshot = snapshot_for(offering_id)

    %{
      offering_id: offering_id,
      policy_id: snapshot["policy_id"],
      policy_name: snapshot["policy_name"],
      policy_version: snapshot["policy_version"],
      summary: snapshot["summary"]
    }
  end

  @doc """
  Simulates an outcome from request params (the admin UI "what happens if…").

  Accepts `policy_id` or `offering_id` (default policy when neither is given),
  `action`, `hours_before`, `payment_method`, `amount_paid`, `currency`,
  `rebook_count`, and the offering ids for rebooking. The current time is read
  here (never inside the engine) and turned into `session_starts_at`.
  """
  @spec simulate(binary() | nil, map() | keyword()) :: %{
          snapshot: map(),
          outcome: SportsCoachBookings.Policies.Outcome.t()
        }
  def simulate(policy_id, params) do
    snapshot = snapshot_for_simulation(policy_id, params)
    now = DateTime.utc_now()
    hours_before = number(params, :hours_before, 0)

    facts = %{
      action: fetch_param(params, :action) || :cancel,
      session_starts_at: DateTime.add(now, round(hours_before * 3600), :second),
      now: now,
      payment_method: fetch_param(params, :payment_method) || :credits,
      amount_paid: amount_paid(params),
      rebook_count: number(params, :rebook_count, 0),
      target_offering_id: fetch_param(params, :target_offering_id),
      source_offering_id: fetch_param(params, :source_offering_id)
    }

    %{snapshot: snapshot, outcome: Engine.evaluate(snapshot, facts)}
  end

  ## Tenant created subscriber entry point

  @doc """
  Idempotently seeds the default policy for `tenant_id`. Called by the
  `tenant.created` subscriber.
  """
  @spec seed_default_policy(binary()) :: {:ok, :seeded | :already_seeded} | {:error, term()}
  def seed_default_policy(tenant_id) when is_binary(tenant_id) do
    TenantContext.with_tenant(tenant_id, fn ->
      case Repo.with_tenant_tx(fn -> ensure_default_policy() end) do
        {:ok, result} -> result
        {:error, reason} -> {:error, reason}
      end
    end)
  end

  @doc "Idempotently seeds the default policy for the tenant already in context."
  @spec ensure_default_policy() :: {:ok, :seeded | :already_seeded}
  def ensure_default_policy do
    case current_default() do
      nil ->
        attrs = %{
          name: @default_name,
          is_default: true,
          active: true,
          customer_facing_summary: Rules.default_summary(),
          rules: Rules.default_map()
        }

        case %CancellationPolicy{}
             |> CancellationPolicy.changeset(tenant_attrs(attrs))
             |> Repo.insert() do
          {:ok, _policy} -> {:ok, :seeded}
          {:error, changeset} -> {:error, changeset}
        end

      _policy ->
        {:ok, :already_seeded}
    end
  end

  ## Private helpers

  defp do_create_policy(attrs) do
    attrs = normalize_filters(attrs)
    existing_default = current_default()
    make_default = truthy?(fetch_attr(attrs, :is_default)) or is_nil(existing_default)

    if make_default and existing_default, do: clear_default(existing_default.id)

    attrs =
      attrs
      |> tenant_attrs()
      |> Map.put("is_default", make_default)
      |> Map.put("version", 1)

    %CancellationPolicy{}
    |> CancellationPolicy.changeset(attrs)
    |> Repo.insert()
  end

  defp do_update_policy(policy, attrs) do
    attrs = normalize_filters(attrs)

    if truthy?(fetch_attr(attrs, :is_default)) do
      clear_default(policy.id)
    end

    changeset =
      policy
      |> CancellationPolicy.changeset(tenant_attrs(attrs))
      |> Ecto.Changeset.put_change(:version, policy.version + 1)

    case Repo.update(changeset) do
      {:ok, updated} -> {:ok, updated}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp do_archive_policy(policy) do
    now = DateTime.utc_now()

    Repo.update_all(
      from(p in CancellationPolicy, where: p.id == ^policy.id),
      set: [active: false, is_default: false, updated_at: now]
    )

    {:ok, Repo.get!(CancellationPolicy, policy.id)}
  end

  defp do_set_default(policy) do
    clear_default(policy.id)
    now = DateTime.utc_now()

    Repo.update_all(
      from(p in CancellationPolicy, where: p.id == ^policy.id),
      set: [is_default: true, active: true, updated_at: now]
    )

    {:ok, Repo.get!(CancellationPolicy, policy.id)}
  end

  defp do_assign(policy, offering_ids) do
    offering_ids
    |> Enum.uniq()
    |> Enum.reduce_while({:ok, []}, fn offering_id, {:ok, acc} ->
      case upsert_assignment(policy, offering_id) do
        {:ok, assignment} -> {:cont, {:ok, [assignment | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, assignments} -> {:ok, Enum.reverse(assignments)}
      other -> other
    end
  end

  defp upsert_assignment(policy, offering_id) do
    with {:ok, _offering} <- Catalog.fetch_offering(offering_id) do
      case Repo.one(
             from a in OfferingPolicyAssignment,
               where: a.offering_id == ^offering_id,
               limit: 1
           ) do
        nil ->
          %OfferingPolicyAssignment{}
          |> OfferingPolicyAssignment.changeset(
            tenant_attrs(%{
              offering_id: offering_id,
              cancellation_policy_id: policy.id
            })
          )
          |> Repo.insert()

        assignment ->
          assignment
          |> OfferingPolicyAssignment.changeset(%{cancellation_policy_id: policy.id})
          |> Repo.update()
      end
    end
  end

  defp do_policy_for_offering(nil), do: current_default()

  defp do_policy_for_offering(offering_id) do
    case Repo.one(
           from a in OfferingPolicyAssignment,
             where: a.offering_id == ^offering_id,
             preload: [:cancellation_policy],
             limit: 1
         ) do
      %OfferingPolicyAssignment{cancellation_policy: %CancellationPolicy{active: true} = policy} ->
        policy

      _ ->
        current_default()
    end
  end

  defp snapshot_for_simulation(policy_id, params) do
    cond do
      is_binary(policy_id) and policy_id != "" ->
        case fetch_policy(policy_id) do
          {:ok, policy} -> snapshot(policy)
          {:error, _} -> default_snapshot()
        end

      offering_id = fetch_param(params, :offering_id) ->
        snapshot_for(offering_id)

      true ->
        case read(fn -> current_default() end) do
          %CancellationPolicy{} = policy -> snapshot(policy)
          _ -> default_snapshot()
        end
    end
  end

  defp current_default do
    Repo.one(
      from p in CancellationPolicy,
        where: p.is_default == true,
        order_by: [desc: p.updated_at],
        limit: 1
    )
  end

  defp clear_default(nil) do
    {count, _} =
      Repo.update_all(
        from(p in CancellationPolicy, where: p.is_default == true),
        set: [is_default: false, updated_at: DateTime.utc_now()]
      )

    count
  end

  defp clear_default(except_id) do
    {count, _} =
      Repo.update_all(
        from(p in CancellationPolicy, where: p.is_default == true and p.id != ^except_id),
        set: [is_default: false, updated_at: DateTime.utc_now()]
      )

    count
  end

  defp amount_paid(params) do
    case fetch_param(params, :amount_paid) do
      nil ->
        nil

      amount when is_integer(amount) ->
        Money.new(amount, fetch_param(params, :currency) || "CAD")

      _ ->
        nil
    end
  end

  defp number(params, key, default) do
    case fetch_param(params, key) do
      nil -> default
      value when is_integer(value) -> value
      value when is_float(value) -> value
      value when is_binary(value) -> parse_number(value, default)
      _ -> default
    end
  end

  defp parse_number(value, default) do
    case Float.parse(value) do
      {number, _} -> number
      :error -> default
    end
  end

  defp run_multi(multi, key) do
    # `Repo.with_tenant_tx/1`'s Multi clause is broken in the current core
    # (it calls `Ecto.Multi.append/2` with a list instead of a Multi). Prepend
    # the tenant GUC step ourselves and run a single transaction so the GUC is
    # set before the writes and failed-step reasons survive. See
    # docs/rfcs/20260928-waivers-tenant-multi-ordering.md.
    set_tenant =
      Ecto.Multi.run(Ecto.Multi.new(), :__set_tenant__, fn _repo, _changes ->
        Repo.set_tenant_guc(TenantContext.get_tenant_id())
        {:ok, :ok}
      end)

    multi = Ecto.Multi.prepend(multi, set_tenant)

    case Repo.transaction(multi) do
      {:ok, changes} -> {:ok, Map.fetch!(changes, key)}
      {:error, ^key, %Ecto.Changeset{} = changeset, _changes} -> {:error, changeset}
      {:error, _step, reason, _changes} -> {:error, reason}
    end
  end

  defp read(fun) do
    case Repo.with_tenant_tx(fun) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  defp fetch_record(schema, id) do
    case Repo.get(schema, id) do
      nil -> {:error, :not_found}
      record -> {:ok, record}
    end
  end

  defp tenant_attrs(attrs) do
    attrs
    |> Enum.into(%{})
    |> Enum.map(fn {key, value} -> {to_string(key), value} end)
    |> Map.new()
    |> Map.drop(["tenant_id", "id"])
    |> Map.put("tenant_id", TenantContext.get_tenant_id())
  end

  defp truthy?(value), do: value in [true, "true", "1", 1]

  defp normalize_filters(filters), do: Enum.into(filters, %{})

  defp fetch_attr(attrs, key) do
    attrs = Enum.into(attrs, %{})
    Map.get(attrs, key) || Map.get(attrs, to_string(key))
  end

  defp fetch_param(params, key) do
    params = Enum.into(params, %{})
    Map.get(params, key) || Map.get(params, to_string(key))
  end

  defp where_active(query, filters) do
    case boolean_param(filter_value(filters, :active)) do
      nil -> query
      value -> where(query, [p], p.active == ^value)
    end
  end

  defp where_default(query, filters) do
    case boolean_param(filter_value(filters, :is_default)) do
      nil -> query
      value -> where(query, [p], p.is_default == ^value)
    end
  end

  defp filter_value(filters, key),
    do: Map.get(filters, key) || Map.get(filters, to_string(key))

  defp boolean_param(value) when is_boolean(value), do: value
  defp boolean_param("true"), do: true
  defp boolean_param("false"), do: false
  defp boolean_param(_), do: nil
end
