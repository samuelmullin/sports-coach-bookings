defmodule SportsCoachBookings.Waivers do
  @moduledoc """
  Versioned waivers, releases, and signatures. Owned by WP-07.

  Templates are scoped either to **all bookings** or to a set of **offerings**
  (via `waiver_template_offerings`). Each template has one or more versions; a
  version is a `:draft` until it is published, after which it is immutable. Only
  one version of a template is `:published` at a time; publishing a new one
  supersedes the previous.

  All functions are tenant-scoped: callers place the tenant in context (via
  `SportsCoachBookingsWeb.Plugs.ResolveTenant` in requests or
  `SportsCoachBookings.DataCase.put_tenant/1` in tests) and every function runs
  inside `SportsCoachBookings.Repo.with_tenant_tx/2` so the RLS GUC is set.

  The booking gate is `missing_for/2`, which WP-14 calls. `status_for_household/1`
  powers the portal's per-player required/signed matrix.
  """

  import Ecto.Query

  alias Ecto.Multi
  alias SportsCoachBookings.Catalog
  alias SportsCoachBookings.Core.Audit
  alias SportsCoachBookings.Core.CustomerActor
  alias SportsCoachBookings.Core.Pagination
  alias SportsCoachBookings.Core.Policy
  alias SportsCoachBookings.Core.TenantContext
  alias SportsCoachBookings.Events
  alias SportsCoachBookings.Players
  alias SportsCoachBookings.Repo
  alias SportsCoachBookings.Waivers.PdfCleanupWorker
  alias SportsCoachBookings.Waivers.PdfStore
  alias SportsCoachBookings.Waivers.PdfWorker
  alias SportsCoachBookings.Waivers.WaiverSignature
  alias SportsCoachBookings.Waivers.WaiverTemplate
  alias SportsCoachBookings.Waivers.WaiverTemplateOffering
  alias SportsCoachBookings.Waivers.WaiverVersion

  @doc "Lower-case hex SHA-256 of a waiver body."
  @spec hash_body(binary()) :: binary()
  def hash_body(body) when is_binary(body) do
    :sha256
    |> :crypto.hash(body)
    |> Base.encode16(case: :lower)
  end

  ## Templates

  @doc "Lists waiver templates, optionally filtered by `:active` and `:scope`."
  @spec list_templates(map() | keyword()) :: [WaiverTemplate.t()]
  def list_templates(filters \\ %{}) do
    filters = normalize_filters(filters)

    read(fn ->
      WaiverTemplate
      |> where_active(filters)
      |> where_scope(filters)
      |> order_by([t], asc: t.name)
      |> Repo.all()
    end)
  end

  @doc "Paginates waiver templates. Returns `%{data: [...], next_cursor: ...}`."
  @spec page_templates(map() | keyword(), map() | keyword()) ::
          %{data: [WaiverTemplate.t()], next_cursor: binary() | nil}
  def page_templates(filters \\ %{}, params \\ %{}) do
    filters = normalize_filters(filters)

    read(fn ->
      query =
        WaiverTemplate
        |> where_active(filters)
        |> where_scope(filters)

      {rows, cursor} = Pagination.paginate(query, params)
      %{data: rows, next_cursor: cursor}
    end)
  end

  @doc "Fetches a template, raising if it does not exist for this tenant."
  @spec get_template!(binary()) :: WaiverTemplate.t()
  def get_template!(id), do: read(fn -> Repo.get!(WaiverTemplate, id) end)

  @doc "Fetches a template, returning `{:error, :not_found}` when absent."
  @spec fetch_template(binary()) :: {:ok, WaiverTemplate.t()} | {:error, :not_found}
  def fetch_template(id), do: read(fn -> fetch_record(WaiverTemplate, id) end)

  @doc """
  Creates a waiver template and records an audit event.

  For `scope: :offerings`, pass `:offering_ids` to link the offerings; each id
  must reference an offering in this tenant.
  """
  @spec create_template(Policy.actor(), map() | keyword()) ::
          {:ok, WaiverTemplate.t()} | {:error, :not_found} | {:error, Ecto.Changeset.t()}
  def create_template(actor, attrs) do
    {offering_ids, attrs} = pop_offering_ids(attrs)

    Multi.new()
    |> Multi.insert(:template, WaiverTemplate.changeset(%WaiverTemplate{}, tenant_attrs(attrs)))
    |> Multi.run(:offerings, fn _repo, %{template: template} ->
      replace_offerings(template, offering_ids)
    end)
    |> Multi.run(:audit, fn _repo, %{template: template} ->
      Audit.record(actor, "waiver.template.created", template, %{})
    end)
    |> run_multi(:template)
  end

  @doc "Updates a template (replacing linked offerings when `:offering_ids` is given)."
  @spec update_template(Policy.actor(), binary(), map() | keyword()) ::
          {:ok, WaiverTemplate.t()}
          | {:error, :not_found}
          | {:error, Ecto.Changeset.t()}
  def update_template(actor, id, attrs) do
    {offering_ids, attrs} = pop_offering_ids(attrs)

    Multi.new()
    |> Multi.run(:template, fn _repo, _changes -> fetch_record(WaiverTemplate, id) end)
    |> Multi.run(:updated, fn _repo, %{template: template} ->
      do_update_template(template, attrs)
    end)
    |> Multi.run(:offerings, fn _repo, %{updated: template} ->
      replace_offerings(template, offering_ids)
    end)
    |> Multi.run(:audit, fn _repo, %{updated: template} ->
      Audit.record(actor, "waiver.template.updated", template, %{})
    end)
    |> run_multi(:updated)
  end

  @doc "Archives (deactivates) a template instead of deleting it."
  @spec archive_template(Policy.actor(), binary()) ::
          {:ok, WaiverTemplate.t()}
          | {:error, :not_found}
          | {:error, Ecto.Changeset.t()}
  def archive_template(actor, id), do: update_template(actor, id, %{"active" => false})

  @doc "The offering ids an `offerings`-scoped template is limited to."
  @spec template_offering_ids(binary()) :: [binary()]
  def template_offering_ids(template_id) do
    read(fn ->
      Repo.all(
        from o in WaiverTemplateOffering,
          where: o.waiver_template_id == ^template_id,
          order_by: [asc: o.inserted_at],
          select: o.offering_id
      )
    end)
  end

  ## Versions

  @doc "Lists a template's versions, newest first."
  @spec list_versions(binary()) :: [WaiverVersion.t()]
  def list_versions(template_id) do
    read(fn ->
      Repo.all(
        from v in WaiverVersion,
          where: v.waiver_template_id == ^template_id,
          order_by: [desc: v.version]
      )
    end)
  end

  @doc "Fetches a version, returning `{:error, :not_found}` when absent."
  @spec fetch_version(binary()) :: {:ok, WaiverVersion.t()} | {:error, :not_found}
  def fetch_version(id), do: read(fn -> fetch_record(WaiverVersion, id) end)

  @doc "Fetches a version, raising if it does not exist for this tenant."
  @spec get_version!(binary()) :: WaiverVersion.t()
  def get_version!(id), do: read(fn -> Repo.get!(WaiverVersion, id) end)

  @doc """
  Creates a new draft version for a template.

  The version number is the next integer for the template and `content_sha256`
  is derived from `body_markdown`. Records an audit event.
  """
  @spec create_version(Policy.actor(), binary(), map() | keyword()) ::
          {:ok, WaiverVersion.t()}
          | {:error, :not_found}
          | {:error, Ecto.Changeset.t()}
  def create_version(actor, template_id, attrs) do
    Multi.new()
    |> Multi.run(:template, fn _repo, _changes -> fetch_record(WaiverTemplate, template_id) end)
    |> Multi.run(:version, fn _repo, %{template: template} -> insert_version(template, attrs) end)
    |> Multi.run(:audit, fn _repo, %{version: version} ->
      Audit.record(actor, "waiver.version.created", version, %{})
    end)
    |> run_multi(:version)
  end

  @doc "Updates a draft version's body. Published/superseded versions are immutable."
  @spec update_version(Policy.actor(), binary(), map() | keyword()) ::
          {:ok, WaiverVersion.t()}
          | {:error, :not_found}
          | {:error, {:immutable_version, binary()}}
          | {:error, Ecto.Changeset.t()}
  def update_version(actor, version_id, attrs) do
    Multi.new()
    |> Multi.run(:version, fn _repo, _changes -> fetch_record(WaiverVersion, version_id) end)
    |> Multi.run(:updated, fn _repo, %{version: version} -> do_update_version(version, attrs) end)
    |> Multi.run(:audit, fn _repo, %{updated: version} ->
      Audit.record(actor, "waiver.version.updated", version, %{})
    end)
    |> run_multi(:updated)
  end

  @doc """
  Publishes a draft version, superseding the template's previous published
  version, and emits `waiver.published`.
  """
  @spec publish_version(Policy.actor(), binary()) ::
          {:ok, WaiverVersion.t()}
          | {:error, :not_found}
          | {:error, {:superseded_version, binary()}}
          | {:error, Ecto.Changeset.t()}
  def publish_version(actor, version_id) do
    Multi.new()
    |> Multi.run(:publish, fn _repo, _changes -> do_publish_version(version_id) end)
    |> Multi.run(:event, fn _repo, %{publish: %{version: version, template: template}} ->
      Events.publish("waiver.published", %{
        template_id: template.id,
        version_id: version.id,
        tenant_id: version.tenant_id,
        require_resign: template.require_resign_on_new_version
      })
    end)
    |> Multi.run(:audit, fn _repo, %{publish: %{version: version}} ->
      Audit.record(actor, "waiver.version.published", version, %{})
    end)
    |> run_multi(:publish)
    |> case do
      {:ok, %{version: version}} -> {:ok, version}
      other -> other
    end
  end

  @doc "Returns the published version body for preview/portal rendering."
  @spec preview_version(binary()) :: {:ok, WaiverVersion.t()} | {:error, :not_found}
  def preview_version(id), do: fetch_version(id)

  ## Signatures

  @doc "Lists signatures, filtered by `:template_id`, `:version_id`, and `:player_id`."
  @spec list_signatures(map() | keyword()) :: [WaiverSignature.t()]
  def list_signatures(filters \\ %{}) do
    read(fn ->
      filters
      |> signature_filters()
      |> signatures_query()
      |> order_by([s], desc: s.inserted_at)
      |> Repo.all()
    end)
  end

  @doc "Paginates signatures. Returns `%{data: [...], next_cursor: ...}`."
  @spec page_signatures(map() | keyword(), map() | keyword()) ::
          %{data: [WaiverSignature.t()], next_cursor: binary() | nil}
  def page_signatures(filters \\ %{}, params \\ %{}) do
    read(fn ->
      query = filters |> signature_filters() |> signatures_query()
      {rows, cursor} = Pagination.paginate(query, params)
      %{data: rows, next_cursor: cursor}
    end)
  end

  @doc "Fetches a signature, returning `{:error, :not_found}` when absent."
  @spec fetch_signature(binary()) :: {:ok, WaiverSignature.t()} | {:error, :not_found}
  def fetch_signature(id), do: read(fn -> fetch_record(WaiverSignature, id) end)

  @doc """
  Returns the signature's PDF bytes from private storage.

  Renders on demand when the background job has not produced the file yet (or
  the stored object is missing), so a download never has to wait on the queue.
  """
  @spec pdf_binary(WaiverSignature.t()) :: {:ok, binary()} | {:error, term()}
  def pdf_binary(%WaiverSignature{} = signature) do
    read(fn ->
      with {:ok, signature} <- ensure_pdf_key(signature) do
        fetch_or_rerender(signature)
      end
    end)
  end

  defp fetch_or_rerender(signature) do
    case PdfStore.get(signature.pdf_key) do
      {:error, :not_found} -> rerender_and_get(signature)
      result -> result
    end
  end

  defp ensure_pdf_key(%WaiverSignature{pdf_key: nil} = signature), do: PdfWorker.render(signature)
  defp ensure_pdf_key(signature), do: {:ok, signature}

  defp rerender_and_get(signature) do
    with {:ok, signature} <- PdfWorker.render(signature) do
      PdfStore.get(signature.pdf_key)
    end
  end

  @doc """
  Signs a published waiver version for a player.

  Requires the client-supplied `content_sha256` to equal the current published
  version's hash; otherwise returns `{:error, {:stale_waiver, message}}`.
  Records the signature, enqueues the PDF snapshot job, and emits
  `waiver.signed` — all in one transaction.
  """
  @spec sign(Policy.actor(), binary(), binary(), map() | keyword()) ::
          {:ok, WaiverSignature.t()}
          | {:error, :not_found}
          | {:error, :conflict}
          | {:error, {:stale_waiver | :waiver_not_published, binary()}}
          | {:error, Ecto.Changeset.t()}
  def sign(actor, player_id, version_id, attrs) do
    Multi.new()
    |> Multi.run(:check, fn _repo, _changes -> check_signable(player_id, version_id, attrs) end)
    |> Multi.run(:signature, fn _repo, %{check: %{version: version}} ->
      insert_signature(actor, player_id, version, attrs)
    end)
    |> Multi.run(:pdf_job, fn _repo, %{signature: signature} -> enqueue_pdf(signature) end)
    |> Multi.run(:event, fn _repo, %{signature: signature} ->
      Events.publish("waiver.signed", %{
        signature_id: signature.id,
        player_id: signature.player_id,
        waiver_version_id: signature.waiver_version_id,
        template_id: template_id_for_version(signature.waiver_version_id),
        tenant_id: signature.tenant_id
      })
    end)
    |> run_multi(:signature)
  end

  @doc "Exports signatures matching `filters` as CSV."
  @spec export_signatures_csv(map() | keyword()) :: binary()
  def export_signatures_csv(filters \\ %{}) do
    read(fn ->
      rows =
        filters
        |> signature_filters()
        |> signatures_export_query()
        |> order_by([s], desc: s.inserted_at)
        |> Repo.all()

      header = [
        "template",
        "version",
        "player_id",
        "signer_name",
        "signer_relationship",
        "signed_at",
        "content_sha256"
      ]

      lines =
        Enum.map(rows, fn row ->
          [
            row.template_name,
            row.version,
            row.player_id,
            row.signer_name_typed,
            row.signer_relationship,
            datetime(row.signed_at),
            row.content_sha256
          ]
          |> Enum.map_join(",", &csv_field/1)
        end)

      Enum.join([Enum.join(header, ",") | lines], "\r\n") <> "\r\n"
    end)
  end

  ## Booking gate + portal status

  @doc """
  Lists the waivers a player must still sign before booking `offering_id`.

  Returns a list of `%{template_id, version_id, name}`. Uses at most two
  queries. A template is required when it is active and either:

    * `scope == :all_bookings`, or
    * `scope == :offerings` and it is linked to `offering_id`.

  The player is *not* missing a template when they have signed the current
  published version. When the template does **not** require re-signing on a new
  version, a signature on any earlier version of the same template also
  satisfies it.
  """
  @spec missing_for(binary(), binary()) :: [map()]
  def missing_for(player_id, offering_id) do
    read(fn ->
      required = required_versions_for_offering(offering_id)
      signed = signed_templates_for_player(player_id)

      signed_version_ids = MapSet.new(signed, & &1.version_id)
      signed_template_ids = MapSet.new(signed, & &1.template_id)

      required
      |> Enum.reject(&satisfied?(&1, signed_version_ids, signed_template_ids))
      |> Enum.map(&Map.take(&1, [:template_id, :version_id, :name]))
    end)
  end

  @doc """
  Per-player matrix of active published templates for a household.

  Returns `%{players: [%{player_id: id, waivers: [...]}]}` where each waiver has
  `template_id`, `name`, `version_id`, `required`, `signed`, `signed_version_id`,
  and `signed_at`.
  """
  @spec status_for_household(binary()) :: %{players: [map()]}
  def status_for_household(household_id) do
    player_ids =
      household_id
      |> Players.list_for_household()
      |> Enum.map(& &1.id)

    %{players: build_status(player_ids)}
  end

  @doc "The status matrix for a single player (see `status_for_household/1`)."
  @spec status_for_player(binary()) :: map()
  def status_for_player(player_id) do
    player_id |> List.wrap() |> build_status() |> List.first()
  end

  ## Private helpers

  defp build_status(player_ids) do
    read(fn ->
      templates = Repo.all(published_templates_query())

      signatures =
        if player_ids == [] do
          []
        else
          Repo.all(
            from s in WaiverSignature,
              join: v in WaiverVersion,
              on: v.id == s.waiver_version_id,
              where: s.player_id in ^player_ids,
              select: %{
                player_id: s.player_id,
                template_id: v.waiver_template_id,
                version_id: s.waiver_version_id,
                signed_at: s.signed_at
              }
          )
        end

      by_player = Enum.group_by(signatures, & &1.player_id)

      Enum.map(player_ids, fn player_id ->
        per_template = Enum.group_by(Map.get(by_player, player_id, []), & &1.template_id)

        %{
          player_id: player_id,
          waivers: Enum.map(templates, &template_status(&1, per_template))
        }
      end)
    end)
  end

  defp required_versions_for_offering(offering_id) do
    Repo.all(
      from t in WaiverTemplate,
        join: v in WaiverVersion,
        on: v.waiver_template_id == t.id and v.status == :published,
        left_join: o in WaiverTemplateOffering,
        on: o.waiver_template_id == t.id and o.offering_id == ^offering_id,
        where: t.active == true,
        where: t.scope == :all_bookings or (t.scope == :offerings and not is_nil(o.id)),
        select: %{
          template_id: t.id,
          version_id: v.id,
          name: t.name,
          require_resign: t.require_resign_on_new_version
        }
    )
  end

  defp signed_templates_for_player(player_id) do
    Repo.all(
      from s in WaiverSignature,
        join: v in WaiverVersion,
        on: v.id == s.waiver_version_id,
        where: s.player_id == ^player_id,
        select: %{version_id: s.waiver_version_id, template_id: v.waiver_template_id}
    )
  end

  defp satisfied?(%{require_resign: true, version_id: version_id}, version_ids, _template_ids),
    do: MapSet.member?(version_ids, version_id)

  defp satisfied?(%{template_id: template_id}, _version_ids, template_ids),
    do: MapSet.member?(template_ids, template_id)

  defp published_templates_query do
    from t in WaiverTemplate,
      join: v in WaiverVersion,
      on: v.waiver_template_id == t.id and v.status == :published,
      where: t.active == true,
      order_by: [asc: t.name],
      select: %{
        template_id: t.id,
        version_id: v.id,
        name: t.name,
        require_resign: t.require_resign_on_new_version
      }
  end

  defp template_status(template, per_template) do
    signatures = Map.get(per_template, template.template_id, [])
    current = Enum.find(signatures, &(&1.version_id == template.version_id))
    latest = Enum.max_by(signatures, & &1.signed_at, fn -> nil end)

    base = %{
      template_id: template.template_id,
      name: template.name,
      version_id: template.version_id,
      required: true
    }

    cond do
      current ->
        Map.merge(base, %{
          signed: true,
          signed_version_id: current.version_id,
          signed_at: current.signed_at
        })

      not template.require_resign and latest != nil ->
        Map.merge(base, %{
          signed: true,
          signed_version_id: latest.version_id,
          signed_at: latest.signed_at
        })

      true ->
        Map.merge(base, %{signed: false, signed_version_id: nil, signed_at: nil})
    end
  end

  defp signatures_query(filters) do
    from(s in WaiverSignature,
      join: v in WaiverVersion,
      on: v.id == s.waiver_version_id,
      join: t in WaiverTemplate,
      on: t.id == v.waiver_template_id
    )
    |> filter_signatures(filters)
  end

  defp signatures_export_query(filters) do
    from(s in WaiverSignature,
      join: v in WaiverVersion,
      on: v.id == s.waiver_version_id,
      join: t in WaiverTemplate,
      on: t.id == v.waiver_template_id,
      select: %{
        template_name: t.name,
        version: v.version,
        player_id: s.player_id,
        signer_name_typed: s.signer_name_typed,
        signer_relationship: s.signer_relationship,
        signed_at: s.signed_at,
        content_sha256: s.content_sha256
      }
    )
    |> filter_signatures(filters)
  end

  defp filter_signatures(query, filters) do
    Enum.reduce(filters, query, fn
      {:player_id, nil}, q -> q
      {:player_id, value}, q -> where(q, [s], s.player_id == ^value)
      {:version_id, nil}, q -> q
      {:version_id, value}, q -> where(q, [s], s.waiver_version_id == ^value)
      {:template_id, nil}, q -> q
      {:template_id, value}, q -> where(q, [s, v], v.waiver_template_id == ^value)
      _, q -> q
    end)
  end

  defp signature_filters(filters) do
    filters = normalize_filters(filters)

    %{
      player_id: filter_value(filters, :player_id),
      version_id: filter_value(filters, :version_id),
      template_id: filter_value(filters, :template_id)
    }
  end

  defp insert_version(template, attrs) do
    body = fetch_attr(attrs, :body_markdown)

    attrs =
      attrs
      |> tenant_attrs()
      |> Map.merge(%{
        "waiver_template_id" => template.id,
        "version" => next_version(template.id),
        "status" => :draft,
        "content_sha256" => hash_body(body || "")
      })

    %WaiverVersion{}
    |> WaiverVersion.changeset(attrs)
    |> Repo.insert()
  end

  defp next_version(template_id) do
    max =
      Repo.one(
        from v in WaiverVersion,
          where: v.waiver_template_id == ^template_id,
          select: max(v.version)
      )

    (max || 0) + 1
  end

  defp do_update_version(version, attrs) do
    if WaiverVersion.immutable?(version) do
      {:error, {:immutable_version, "Published waiver versions cannot be edited"}}
    else
      attrs =
        case fetch_attr(attrs, :body_markdown) do
          nil -> attrs
          body -> put_sha(attrs, body)
        end

      version
      |> WaiverVersion.changeset(tenant_attrs(attrs))
      |> Repo.update()
    end
  end

  defp do_publish_version(version_id) do
    with {:ok, version, template} <- load_version_with_template(version_id),
         :ok <- ensure_publishable(version) do
      now = DateTime.utc_now()

      Repo.update_all(
        from(v in WaiverVersion,
          where:
            v.waiver_template_id == ^template.id and v.status == :published and
              v.id != ^version.id
        ),
        set: [status: :superseded, updated_at: now]
      )

      changeset =
        WaiverVersion.changeset(version, %{
          status: :published,
          published_at: now,
          content_sha256: hash_body(version.body_markdown)
        })

      case Repo.update(changeset) do
        {:ok, published} -> {:ok, %{version: published, template: template}}
        {:error, changeset} -> {:error, changeset}
      end
    end
  end

  defp load_version_with_template(version_id) do
    case Repo.one(
           from v in WaiverVersion,
             join: t in WaiverTemplate,
             on: t.id == v.waiver_template_id,
             where: v.id == ^version_id,
             select: {v, t}
         ) do
      nil -> {:error, :not_found}
      {version, template} -> {:ok, version, template}
    end
  end

  defp ensure_publishable(%{status: :draft}), do: :ok
  defp ensure_publishable(%{status: :published}), do: :ok

  defp ensure_publishable(%{status: :superseded}),
    do: {:error, {:superseded_version, "A superseded waiver version cannot be published"}}

  defp check_signable(player_id, version_id, attrs) do
    case fetch_record(WaiverVersion, version_id) do
      {:error, :not_found} ->
        {:error, :not_found}

      {:ok, %{status: status}} when status != :published ->
        {:error, {:waiver_not_published, "This waiver version is not open for signing"}}

      {:ok, version} ->
        cond do
          fetch_attr(attrs, :content_sha256) != version.content_sha256 ->
            {:error, {:stale_waiver, "Waiver text has changed; reload and sign again"}}

          Repo.exists?(
            from s in WaiverSignature,
              where: s.waiver_version_id == ^version_id and s.player_id == ^player_id
          ) ->
            {:error, :conflict}

          true ->
            {:ok, %{version: version}}
        end
    end
  end

  defp insert_signature(actor, player_id, version, attrs) do
    attrs =
      attrs
      |> tenant_attrs()
      |> Map.merge(%{
        "waiver_version_id" => version.id,
        "player_id" => player_id,
        "customer_user_id" => customer_user_id(actor, attrs),
        "signed_at" => DateTime.utc_now(),
        "content_sha256" => version.content_sha256
      })

    %WaiverSignature{}
    |> WaiverSignature.changeset(attrs)
    |> Repo.insert()
  end

  defp enqueue_pdf(signature) do
    args = %{"signature_id" => signature.id, "tenant_id" => signature.tenant_id}

    case Oban.insert(PdfWorker.new(args)) do
      {:ok, job} -> {:ok, job}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp template_id_for_version(version_id) do
    Repo.one(from v in WaiverVersion, where: v.id == ^version_id, select: v.waiver_template_id)
  end

  defp customer_user_id(%CustomerActor{customer_user_id: id}, _attrs), do: id
  defp customer_user_id(_actor, attrs), do: fetch_attr(attrs, :customer_user_id)

  defp do_update_template(template, attrs) do
    template
    |> WaiverTemplate.changeset(attrs)
    |> Repo.update()
  end

  defp replace_offerings(_template, nil), do: {:ok, []}

  defp replace_offerings(%{scope: :all_bookings} = template, _offering_ids) do
    Repo.delete_all(from o in WaiverTemplateOffering, where: o.waiver_template_id == ^template.id)

    {:ok, []}
  end

  defp replace_offerings(template, offering_ids) do
    Repo.delete_all(from o in WaiverTemplateOffering, where: o.waiver_template_id == ^template.id)

    Enum.reduce_while(offering_ids, {:ok, []}, fn offering_id, {:ok, acc} ->
      case insert_offering(template, offering_id) do
        {:ok, record} -> {:cont, {:ok, [record | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp insert_offering(template, offering_id) do
    with {:ok, _offering} <- Catalog.fetch_offering(offering_id) do
      %WaiverTemplateOffering{}
      |> WaiverTemplateOffering.changeset(
        tenant_attrs(%{waiver_template_id: template.id, offering_id: offering_id})
      )
      |> Repo.insert()
    end
  end

  defp run_multi(multi, key) do
    # `Repo.with_tenant_tx/1`'s `Ecto.Multi` clause appends its GUC step *after*
    # the caller's operations, so the tenant GUC is not set while the writes
    # run (RLS rejects them outside tests). Prepend the GUC step ourselves and
    # run the Multi in a single transaction so failed steps keep their reason.
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

  ## Privacy erasure

  @doc """
  Anonymizes the waiver signatures of the given players.

  The signature rows are kept (they evidence that a version was accepted and
  when) but the signer's typed name, relationship, IP address, and user agent
  are scrubbed and the signed PDF reference is dropped. Returns the PDF storage
  keys that were referenced so the caller can delete the stored files.
  """
  @spec anonymize_signatures([binary()]) :: [binary()]
  def anonymize_signatures([]), do: []

  def anonymize_signatures(player_ids) do
    read(fn ->
      query = from s in WaiverSignature, where: s.player_id in ^player_ids

      keys = Repo.all(from s in query, where: not is_nil(s.pdf_key), select: s.pdf_key)
      tenant_id = TenantContext.get_tenant_id()

      Repo.update_all(query,
        set: [
          signer_name_typed: "[erased]",
          signer_relationship: nil,
          ip: %Postgrex.INET{address: {0, 0, 0, 0}, netmask: 32},
          user_agent: "[erased]",
          pdf_key: nil
        ]
      )

      if keys != [] do
        {:ok, _job} =
          Oban.insert(PdfCleanupWorker.new(%{"keys" => keys, "tenant_id" => tenant_id}))
      end

      keys
    end)
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

  defp put_sha(attrs, body) do
    attrs
    |> Enum.into(%{})
    |> Map.put(:content_sha256, hash_body(body))
  end

  defp pop_offering_ids(attrs) do
    attrs = Enum.into(attrs, %{})

    {
      Map.get(attrs, :offering_ids) || Map.get(attrs, "offering_ids"),
      Map.drop(attrs, [:offering_ids, "offering_ids"])
    }
  end

  defp fetch_attr(attrs, key) do
    attrs = Enum.into(attrs, %{})
    Map.get(attrs, key) || Map.get(attrs, to_string(key))
  end

  defp normalize_filters(filters), do: Enum.into(filters, %{})

  defp filter_value(filters, key),
    do: Map.get(filters, key) || Map.get(filters, to_string(key))

  defp where_active(query, filters) do
    case filter_value(filters, :active) do
      nil -> query
      value -> where(query, [t], t.active == ^value)
    end
  end

  defp where_scope(query, filters) do
    case filter_value(filters, :scope) do
      nil -> query
      value -> where(query, [t], t.scope == ^value)
    end
  end

  defp csv_field(nil), do: ""

  defp csv_field(value) do
    value = to_string(value)

    if String.contains?(value, [",", "\"", "\n", "\r"]) do
      "\"" <> String.replace(value, "\"", "\"\"") <> "\""
    else
      value
    end
  end

  defp datetime(nil), do: nil
  defp datetime(%DateTime{} = value), do: DateTime.to_iso8601(value)
end
