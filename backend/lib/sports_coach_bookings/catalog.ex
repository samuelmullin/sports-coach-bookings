defmodule SportsCoachBookings.Catalog do
  @moduledoc """
  Venues, offerings, packages, discounts, and tax rates. Owned by WP-03.

  All reads and writes are tenant-scoped: callers place the tenant in context
  (via `SportsCoachBookingsWeb.Plugs.ResolveTenant` in requests,
  `SportsCoachBookings.DataCase.put_tenant/1` in tests) and every function here
  runs inside `SportsCoachBookings.Repo.with_tenant_tx/2` so the RLS GUC is set.

  Write functions take the acting `actor` first so they can record an audit
  entry in the same transaction as the change.
  """

  import Ecto.Query

  alias Ecto.Multi
  alias SportsCoachBookings.Catalog.Discount
  alias SportsCoachBookings.Catalog.DiscountTarget
  alias SportsCoachBookings.Catalog.Offering
  alias SportsCoachBookings.Catalog.Package
  alias SportsCoachBookings.Catalog.PackageOffering
  alias SportsCoachBookings.Catalog.TaxRate
  alias SportsCoachBookings.Catalog.Venue
  alias SportsCoachBookings.Core.Audit
  alias SportsCoachBookings.Core.Pagination
  alias SportsCoachBookings.Core.Policy
  alias SportsCoachBookings.Core.TenantContext
  alias SportsCoachBookings.Repo

  ## Venues

  @doc "Lists venues, optionally filtered by `:active`."
  @spec list_venues(map() | keyword()) :: [Venue.t()]
  def list_venues(filters \\ %{}) do
    read(fn ->
      Venue
      |> where_active(filters)
      |> order_by([v], asc: v.name)
      |> Repo.all()
    end)
  end

  @doc "Fetches a venue by id, raising if it does not exist for this tenant."
  @spec get_venue!(binary()) :: Venue.t()
  def get_venue!(id), do: read(fn -> Repo.get!(Venue, id) end)

  @doc "Fetches a venue by id, returning `{:error, :not_found}` when absent."
  @spec fetch_venue(binary()) :: {:ok, Venue.t()} | {:error, :not_found}
  def fetch_venue(id), do: read(fn -> fetch_record(Venue, id) end)

  @doc "Creates a venue."
  @spec create_venue(Policy.actor(), map()) :: {:ok, Venue.t()} | {:error, Ecto.Changeset.t()}
  def create_venue(actor, attrs) do
    attrs
    |> tenant_attrs()
    |> then(&Venue.changeset(%Venue{}, &1))
    |> insert_with_audit(actor, "catalog.venue.created", :venue)
  end

  @doc "Updates a venue."
  @spec update_venue(Policy.actor(), binary(), map()) ::
          {:ok, Venue.t()} | {:error, :not_found} | {:error, Ecto.Changeset.t()}
  def update_venue(actor, id, attrs) do
    with_loaded(Venue, id, fn venue ->
      venue
      |> Venue.changeset(attrs)
      |> update_with_audit(actor, "catalog.venue.updated", :venue)
    end)
  end

  @doc "Archives (deactivates) a venue instead of deleting it."
  @spec archive_venue(Policy.actor(), binary()) ::
          {:ok, Venue.t()} | {:error, :not_found} | {:error, Ecto.Changeset.t()}
  def archive_venue(actor, id), do: update_venue(actor, id, %{active: false})

  ## Offerings

  @doc """
  Lists offerings.

  Filters: `:active` (boolean), `:format` (`:private | :semi_private | :group`),
  `:age` (returns offerings bookable for that age).
  """
  @spec list_offerings(map() | keyword()) :: [Offering.t()]
  def list_offerings(filters \\ %{}) do
    filters = normalize_filters(filters)

    read(fn ->
      Offering
      |> where_active(filters)
      |> where_format(filters)
      |> where_age(filters)
      |> order_by([o], asc: o.position, asc: o.name)
      |> Repo.all()
    end)
  end

  @doc "Fetches an offering by id, raising if it does not exist for this tenant."
  @spec get_offering!(binary()) :: Offering.t()
  def get_offering!(id), do: read(fn -> Repo.get!(Offering, id) end)

  @doc "Fetches an offering by id, returning `{:error, :not_found}` when absent."
  @spec fetch_offering(binary()) :: {:ok, Offering.t()} | {:error, :not_found}
  def fetch_offering(id), do: read(fn -> fetch_record(Offering, id) end)

  @doc "Creates an offering."
  @spec create_offering(Policy.actor(), map()) ::
          {:ok, Offering.t()} | {:error, Ecto.Changeset.t()}
  def create_offering(actor, attrs) do
    attrs
    |> tenant_attrs()
    |> then(&Offering.changeset(%Offering{}, &1))
    |> insert_with_audit(actor, "catalog.offering.created", :offering)
  end

  @doc "Updates an offering."
  @spec update_offering(Policy.actor(), binary(), map()) ::
          {:ok, Offering.t()} | {:error, :not_found} | {:error, Ecto.Changeset.t()}
  def update_offering(actor, id, attrs) do
    with_loaded(Offering, id, fn offering ->
      offering
      |> Offering.changeset(attrs)
      |> update_with_audit(actor, "catalog.offering.updated", :offering)
    end)
  end

  @doc "Archives (deactivates) an offering. Packages stay valid; the portal hides it."
  @spec archive_offering(Policy.actor(), binary()) ::
          {:ok, Offering.t()} | {:error, :not_found} | {:error, Ecto.Changeset.t()}
  def archive_offering(actor, id), do: update_offering(actor, id, %{active: false})

  @doc "Reorders offerings by assigning `position` from the given id order."
  @spec reorder_offerings(Policy.actor(), [binary()]) ::
          {:ok, [Offering.t()]} | {:error, :not_found}
  def reorder_offerings(actor, ids),
    do: reorder(Offering, actor, ids, "catalog.offering.reordered")

  ## Packages

  @doc "Lists packages, optionally filtered by `:active` and `:visible_in_portal`."
  @spec list_packages(map() | keyword()) :: [Package.t()]
  def list_packages(filters \\ %{}) do
    filters = normalize_filters(filters)

    read(fn ->
      Package
      |> where_active(filters)
      |> where_visible(filters)
      |> order_by([p], asc: p.position, asc: p.name)
      |> Repo.all()
    end)
  end

  @doc """
  Lists active, portal-visible packages a customer can buy for `offering_id`.

  A package is eligible when it is global (no eligible offerings) or lists
  `offering_id`. Ordered by `credit_quantity` so the smallest pack comes first.
  """
  @spec list_packages_for_offering(binary(), map() | keyword()) :: [Package.t()]
  def list_packages_for_offering(offering_id, filters \\ %{}) when is_binary(offering_id) do
    filters =
      filters
      |> normalize_filters()
      |> Map.put(:active, true)
      |> Map.put(:visible_in_portal, true)

    read(fn ->
      Package
      |> where_active(filters)
      |> where_visible(filters)
      |> where_offering_scope(offering_id)
      |> order_by([p], asc: p.credit_quantity, asc: p.position, asc: p.name)
      |> Repo.all()
    end)
  end

  @doc "Fetches a package by id, raising if it does not exist for this tenant."
  @spec get_package!(binary()) :: Package.t()
  def get_package!(id), do: read(fn -> Repo.get!(Package, id) end)

  @doc "Fetches a package by id, returning `{:error, :not_found}` when absent."
  @spec fetch_package(binary()) :: {:ok, Package.t()} | {:error, :not_found}
  def fetch_package(id), do: read(fn -> fetch_record(Package, id) end)

  @doc "Creates a package, optionally with an `:offering_ids` list of offerings."
  @spec create_package(Policy.actor(), map()) ::
          {:ok, Package.t()} | {:error, :not_found} | {:error, Ecto.Changeset.t()}
  def create_package(actor, attrs) do
    {offering_ids, attrs} = pop_offering_ids(attrs)

    Multi.new()
    |> Multi.insert(:package, Package.changeset(%Package{}, tenant_attrs(attrs)))
    |> Multi.run(:offerings, fn _repo, %{package: package} ->
      replace_package_offerings(package, offering_ids)
    end)
    |> Multi.run(:audit, fn _repo, %{package: package} ->
      Audit.record(actor, "catalog.package.created", package, %{})
    end)
    |> run_multi(:package)
  end

  @doc "Updates a package, replacing its eligible offerings when `:offering_ids` is given."
  @spec update_package(Policy.actor(), binary(), map()) ::
          {:ok, Package.t()} | {:error, :not_found} | {:error, Ecto.Changeset.t()}
  def update_package(actor, id, attrs) do
    {offering_ids, attrs} = pop_offering_ids(attrs)

    with_loaded(Package, id, fn package ->
      Multi.new()
      |> Multi.update(:package, Package.changeset(package, attrs))
      |> Multi.run(:offerings, fn _repo, %{package: package} ->
        replace_package_offerings(package, offering_ids)
      end)
      |> Multi.run(:audit, fn _repo, %{package: package} ->
        Audit.record(actor, "catalog.package.updated", package, %{})
      end)
      |> run_multi(:package)
    end)
  end

  @doc "Archives (deactivates) a package instead of deleting it."
  @spec archive_package(Policy.actor(), binary()) ::
          {:ok, Package.t()} | {:error, :not_found} | {:error, Ecto.Changeset.t()}
  def archive_package(actor, id), do: update_package(actor, id, %{active: false})

  @doc "Reorders packages by assigning `position` from the given id order."
  @spec reorder_packages(Policy.actor(), [binary()]) ::
          {:ok, [Package.t()]} | {:error, :not_found}
  def reorder_packages(actor, ids), do: reorder(Package, actor, ids, "catalog.package.reordered")

  @doc "Replaces the eligible offerings for a package."
  @spec set_package_offerings(Policy.actor(), binary(), [binary()]) ::
          {:ok, Package.t()} | {:error, :not_found} | {:error, Ecto.Changeset.t()}
  def set_package_offerings(actor, package_id, offering_ids) do
    with_loaded(Package, package_id, fn package ->
      Multi.new()
      |> Multi.run(:offerings, fn _repo, _changes ->
        replace_package_offerings(package, offering_ids)
      end)
      |> Multi.run(:audit, fn _repo, _changes ->
        Audit.record(actor, "catalog.package.offerings_changed", package, %{
          offering_ids: offering_ids
        })
      end)
      |> Multi.run(:package, fn _repo, _changes -> {:ok, package} end)
      |> run_multi(:package)
    end)
  end

  @doc "The offering ids a package is restricted to, or `:all` when unrestricted."
  @spec package_eligible_offering_ids(binary()) :: :all | [binary()]
  def package_eligible_offering_ids(package_id) do
    ids =
      read(fn ->
        Repo.all(
          from po in PackageOffering,
            where: po.package_id == ^package_id,
            order_by: [asc: po.inserted_at],
            select: po.offering_id
        )
      end)

    if ids == [], do: :all, else: ids
  end

  @doc """
  Returns a `%{package_id => [offering_id]}` map for the given package ids.

  Packages with no join rows are absent; an empty list means the package is
  valid for all offerings. Index endpoints use this to serialise `offering_ids`
  without an N+1 query per row.
  """
  @spec package_offering_ids([binary()]) :: %{binary() => [binary()]}
  def package_offering_ids(package_ids) when is_list(package_ids) do
    read(fn ->
      from(po in PackageOffering,
        where: po.package_id in ^package_ids,
        order_by: [asc: po.inserted_at, asc: po.offering_id],
        select: {po.package_id, po.offering_id}
      )
      |> Repo.all()
      |> Enum.reduce(%{}, fn {package_id, offering_id}, acc ->
        Map.update(acc, package_id, [offering_id], &(&1 ++ [offering_id]))
      end)
    end)
  end

  ## Discounts

  @doc "Lists discounts, optionally filtered by `:active`."
  @spec list_discounts(map() | keyword()) :: [Discount.t()]
  def list_discounts(filters \\ %{}) do
    read(fn ->
      Discount
      |> where_active(filters)
      |> order_by([d], desc: d.inserted_at)
      |> Repo.all()
    end)
  end

  @doc "Fetches a discount by id, returning `{:error, :not_found}` when absent."
  @spec fetch_discount(binary()) :: {:ok, Discount.t()} | {:error, :not_found}
  def fetch_discount(id), do: read(fn -> fetch_record(Discount, id) end)

  @doc "Fetches a discount by code, returning `{:error, :not_found}` when absent."
  @spec fetch_discount_by_code(binary()) :: {:ok, Discount.t()} | {:error, :not_found}
  def fetch_discount_by_code(code) when is_binary(code) do
    read(fn ->
      case Repo.one(from d in Discount, where: d.code == ^code, limit: 1) do
        nil -> {:error, :not_found}
        discount -> {:ok, discount}
      end
    end)
  end

  @doc "Creates a discount, optionally with `:targets` (`[%{target_type, target_id}]`)."
  @spec create_discount(Policy.actor(), map()) ::
          {:ok, Discount.t()} | {:error, Ecto.Changeset.t()}
  def create_discount(actor, attrs) do
    {targets, attrs} = pop_targets(attrs)

    Multi.new()
    |> Multi.insert(:discount, Discount.changeset(%Discount{}, tenant_attrs(attrs)))
    |> Multi.run(:targets, fn _repo, %{discount: discount} ->
      replace_discount_targets(discount, targets)
    end)
    |> Multi.run(:audit, fn _repo, %{discount: discount} ->
      Audit.record(actor, "catalog.discount.created", discount, %{})
    end)
    |> run_multi(:discount)
  end

  @doc "Updates a discount, replacing targets when `:targets` is given."
  @spec update_discount(Policy.actor(), binary(), map()) ::
          {:ok, Discount.t()} | {:error, :not_found} | {:error, Ecto.Changeset.t()}
  def update_discount(actor, id, attrs) do
    {targets, attrs} = pop_targets(attrs)

    with_loaded(Discount, id, fn discount ->
      Multi.new()
      |> Multi.update(:discount, Discount.changeset(discount, attrs))
      |> Multi.run(:targets, fn _repo, %{discount: discount} ->
        replace_discount_targets(discount, targets)
      end)
      |> Multi.run(:audit, fn _repo, %{discount: discount} ->
        Audit.record(actor, "catalog.discount.updated", discount, %{})
      end)
      |> run_multi(:discount)
    end)
  end

  @doc "Archives (deactivates) a discount instead of deleting it."
  @spec archive_discount(Policy.actor(), binary()) ::
          {:ok, Discount.t()} | {:error, :not_found} | {:error, Ecto.Changeset.t()}
  def archive_discount(actor, id), do: update_discount(actor, id, %{active: false})

  ## Tax rates

  @doc "Lists tax rates, optionally filtered by `:active`."
  @spec list_tax_rates(map() | keyword()) :: [TaxRate.t()]
  def list_tax_rates(filters \\ %{}) do
    read(fn ->
      TaxRate
      |> where_active(filters)
      |> order_by([t], desc: t.inserted_at)
      |> Repo.all()
    end)
  end

  @doc "Fetches a tax rate by id, returning `{:error, :not_found}` when absent."
  @spec fetch_tax_rate(binary()) :: {:ok, TaxRate.t()} | {:error, :not_found}
  def fetch_tax_rate(id), do: read(fn -> fetch_record(TaxRate, id) end)

  @doc "Returns the tenant's active tax rate, or `nil`."
  @spec active_tax_rate() :: TaxRate.t() | nil
  def active_tax_rate do
    read(fn -> Repo.one(from t in TaxRate, where: t.active == true, limit: 1) end)
  end

  @doc "Creates a tax rate. Activating one deactivates the tenant's others."
  @spec create_tax_rate(Policy.actor(), map()) ::
          {:ok, TaxRate.t()} | {:error, Ecto.Changeset.t()}
  def create_tax_rate(actor, attrs) do
    changeset = TaxRate.changeset(%TaxRate{}, tenant_attrs(attrs))

    Multi.new()
    |> Multi.run(:deactivate, fn _repo, _changes ->
      maybe_deactivate_others(changeset, nil)
    end)
    |> Multi.insert(:tax_rate, changeset)
    |> Multi.run(:audit, fn _repo, %{tax_rate: tax_rate} ->
      Audit.record(actor, "catalog.tax_rate.created", tax_rate, %{})
    end)
    |> run_multi(:tax_rate)
  end

  @doc "Updates a tax rate. Activating one deactivates the tenant's others."
  @spec update_tax_rate(Policy.actor(), binary(), map()) ::
          {:ok, TaxRate.t()} | {:error, :not_found} | {:error, Ecto.Changeset.t()}
  def update_tax_rate(actor, id, attrs) do
    with_loaded(TaxRate, id, fn tax_rate ->
      changeset = TaxRate.changeset(tax_rate, attrs)

      Multi.new()
      |> Multi.run(:deactivate, fn _repo, _changes ->
        maybe_deactivate_others(changeset, tax_rate.id)
      end)
      |> Multi.update(:tax_rate, changeset)
      |> Multi.run(:audit, fn _repo, %{tax_rate: tax_rate} ->
        Audit.record(actor, "catalog.tax_rate.updated", tax_rate, %{})
      end)
      |> run_multi(:tax_rate)
    end)
  end

  @doc "Archives (deactivates) a tax rate."
  @spec archive_tax_rate(Policy.actor(), binary()) ::
          {:ok, TaxRate.t()} | {:error, :not_found} | {:error, Ecto.Changeset.t()}
  def archive_tax_rate(actor, id), do: update_tax_rate(actor, id, %{active: false})

  ## Paginated listings (cursor pagination for HTTP endpoints)

  @doc "Paginates venues. Returns `%{data: [Venue.t()], next_cursor: binary | nil}`."
  @spec page_venues(map() | keyword(), map()) :: %{data: [Venue.t()], next_cursor: binary() | nil}
  def page_venues(filters \\ %{}, params \\ %{}) do
    filters = normalize_filters(filters)
    paginate(Venue |> where_active(filters), params)
  end

  @doc "Paginates offerings."
  @spec page_offerings(map() | keyword(), map()) ::
          %{data: [Offering.t()], next_cursor: binary() | nil}
  def page_offerings(filters \\ %{}, params \\ %{}) do
    filters = normalize_filters(filters)

    query =
      Offering
      |> where_active(filters)
      |> where_format(filters)
      |> where_age(filters)

    paginate(query, params)
  end

  @doc "Paginates packages."
  @spec page_packages(map() | keyword(), map()) ::
          %{data: [Package.t()], next_cursor: binary() | nil}
  def page_packages(filters \\ %{}, params \\ %{}) do
    filters = normalize_filters(filters)
    query = Package |> where_active(filters) |> where_visible(filters)
    paginate(query, params)
  end

  @doc "Paginates discounts."
  @spec page_discounts(map() | keyword(), map()) ::
          %{data: [Discount.t()], next_cursor: binary() | nil}
  def page_discounts(filters \\ %{}, params \\ %{}) do
    filters = normalize_filters(filters)
    paginate(Discount |> where_active(filters), params)
  end

  @doc "Paginates tax rates."
  @spec page_tax_rates(map() | keyword(), map()) ::
          %{data: [TaxRate.t()], next_cursor: binary() | nil}
  def page_tax_rates(filters \\ %{}, params \\ %{}) do
    filters = normalize_filters(filters)
    paginate(TaxRate |> where_active(filters), params)
  end

  ## Private helpers

  defp paginate(query, params) do
    read(fn ->
      {rows, next_cursor} = Pagination.paginate(query, params)
      %{data: rows, next_cursor: next_cursor}
    end)
  end

  defp insert_with_audit(changeset, actor, action, key) do
    Multi.new()
    |> Multi.insert(key, changeset)
    |> Multi.run(:audit, fn _repo, changes ->
      Audit.record(actor, action, Map.fetch!(changes, key))
    end)
    |> run_multi(key)
  end

  defp update_with_audit(changeset, actor, action, key) do
    Multi.new()
    |> Multi.update(key, changeset)
    |> Multi.run(:audit, fn _repo, changes ->
      Audit.record(actor, action, Map.fetch!(changes, key))
    end)
    |> run_multi(key)
  end

  defp reorder(schema, actor, ids, action) when is_list(ids) do
    result =
      ids
      |> Enum.with_index()
      |> Enum.reduce_while({:ok, []}, fn {id, position}, {:ok, acc} ->
        case reposition(schema, id, position) do
          {:ok, updated} -> {:cont, {:ok, [updated | acc]}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)

    case result do
      {:ok, records} ->
        {:ok, _} = Audit.record(actor, action, nil, %{ids: ids})
        {:ok, Enum.reverse(records)}

      other ->
        other
    end
  end

  defp reposition(schema, id, position) do
    case Repo.get(schema, id) do
      nil -> {:error, :not_found}
      record -> record |> Ecto.Changeset.change(position: position) |> Repo.update()
    end
  end

  defp with_loaded(schema, id, fun) do
    case Repo.get(schema, id) do
      nil -> {:error, :not_found}
      record -> fun.(record)
    end
  end

  defp fetch_record(schema, id) do
    case Repo.get(schema, id) do
      nil -> {:error, :not_found}
      record -> {:ok, record}
    end
  end

  defp replace_package_offerings(_package, nil), do: {:ok, []}

  defp replace_package_offerings(package, offering_ids) do
    Repo.delete_all(from po in PackageOffering, where: po.package_id == ^package.id)

    Enum.reduce_while(offering_ids, {:ok, []}, fn offering_id, {:ok, acc} ->
      case insert_package_offering(package, offering_id) do
        {:ok, record} -> {:cont, {:ok, [record | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp insert_package_offering(package, offering_id) do
    case Repo.get(Offering, offering_id) do
      nil ->
        {:error, :not_found}

      _offering ->
        attrs = %{package_id: package.id, offering_id: offering_id}

        %PackageOffering{}
        |> PackageOffering.changeset(tenant_attrs(attrs))
        |> Repo.insert()
    end
  end

  defp replace_discount_targets(_discount, nil), do: {:ok, []}

  defp replace_discount_targets(discount, targets) do
    Repo.delete_all(from t in DiscountTarget, where: t.discount_id == ^discount.id)

    Enum.reduce_while(targets, {:ok, []}, fn target, {:ok, acc} ->
      attrs = target |> Enum.into(%{}) |> Map.put(:discount_id, discount.id)

      case %DiscountTarget{} |> DiscountTarget.changeset(tenant_attrs(attrs)) |> Repo.insert() do
        {:ok, record} -> {:cont, {:ok, [record | acc]}}
        {:error, changeset} -> {:halt, {:error, changeset}}
      end
    end)
  end

  defp maybe_deactivate_others(changeset, keep_id) do
    if Ecto.Changeset.get_field(changeset, :active) do
      deactivate_other_tax_rates(keep_id)
    else
      {:ok, nil}
    end
  end

  defp deactivate_other_tax_rates(nil) do
    Repo.update_all(from(t in TaxRate, where: t.active == true), set: [active: false])
    {:ok, nil}
  end

  defp deactivate_other_tax_rates(keep_id) do
    Repo.update_all(
      from(t in TaxRate, where: t.active == true and t.id != ^keep_id),
      set: [active: false]
    )

    {:ok, nil}
  end

  defp run_multi(multi, key) do
    # `Repo.with_tenant_tx/1`'s `Ecto.Multi` clause is currently unusable (its
    # internal `:__set_tenant__` step returns `:ok` instead of `{:ok, _}`); see
    # docs/rfcs for the core bug. Run the multi in a nested transaction instead.
    case Repo.with_tenant_tx(fn -> Repo.transaction(multi) end) do
      {:ok, {:ok, changes}} -> {:ok, Map.fetch!(changes, key)}
      {:ok, {:error, ^key, %Ecto.Changeset{} = changeset, _changes}} -> {:error, changeset}
      {:ok, {:error, _step, reason, _changes}} -> {:error, reason}
      {:error, reason} -> {:error, reason}
    end
  end

  defp read(fun) do
    case Repo.with_tenant_tx(fun) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
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

  defp pop_offering_ids(attrs) do
    attrs = Enum.into(attrs, %{})

    {
      Map.get(attrs, :offering_ids) || Map.get(attrs, "offering_ids"),
      Map.drop(attrs, [:offering_ids, "offering_ids"])
    }
  end

  defp pop_targets(attrs) do
    attrs = Enum.into(attrs, %{})

    {
      Map.get(attrs, :targets) || Map.get(attrs, "targets"),
      Map.drop(attrs, [:targets, "targets"])
    }
  end

  defp normalize_filters(filters), do: Enum.into(filters, %{})

  defp filter_value(filters, key), do: Map.get(filters, key) || Map.get(filters, to_string(key))

  defp where_active(query, filters) do
    case filter_value(filters, :active) do
      nil -> query
      value -> where(query, [r], r.active == ^value)
    end
  end

  defp where_visible(query, filters) do
    case filter_value(filters, :visible_in_portal) do
      nil -> query
      value -> where(query, [r], r.visible_in_portal == ^value)
    end
  end

  defp where_offering_scope(query, offering_id) do
    where(
      query,
      [p],
      fragment(
        "NOT EXISTS (SELECT 1 FROM package_offerings po WHERE po.package_id = ?) OR EXISTS (SELECT 1 FROM package_offerings po WHERE po.package_id = ? AND po.offering_id = ?)",
        p.id,
        p.id,
        type(^offering_id, :binary_id)
      )
    )
  end

  defp where_format(query, filters) do
    case filter_value(filters, :format) do
      nil -> query
      value -> where(query, [r], r.format == ^value)
    end
  end

  defp where_age(query, filters) do
    case filter_value(filters, :age) do
      nil ->
        query

      age ->
        where(
          query,
          [r],
          (is_nil(r.min_age) or r.min_age <= ^age) and (is_nil(r.max_age) or r.max_age >= ^age)
        )
    end
  end
end
