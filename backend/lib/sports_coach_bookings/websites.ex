defmodule SportsCoachBookings.Websites do
  @moduledoc "Hosted marketing sites and their contact inboxes."

  import Ecto.Query

  alias SportsCoachBookings.Core.Audit
  alias SportsCoachBookings.Core.Pagination
  alias SportsCoachBookings.Core.TenantContext
  alias SportsCoachBookings.Events
  alias SportsCoachBookings.Repo
  alias SportsCoachBookings.Tenancy.Storage
  alias SportsCoachBookings.Websites.ContactSubmission
  alias SportsCoachBookings.Websites.Site

  @default_content %{
    "announcement" => "",
    "hero" => %{
      "eyebrow" => "Coaching for every player",
      "title" => "Develop your game.",
      "body" =>
        "Book private and small-group coaching with a team that cares about your progress.",
      "primary_cta_label" => "Book a session",
      "primary_cta_url" => "/schedule",
      "secondary_cta_label" => "Our story",
      "secondary_cta_url" => "/about"
    },
    "stats" => [],
    "story" => %{"title" => "More than coaching.", "body" => ""},
    "features" => [],
    "testimonials" => [],
    "coaches" => [],
    "gallery" => [],
    "sponsors" => [],
    "faqs" => [],
    "contact" => %{},
    "footer" => %{},
    "seo" => %{}
  }

  @doc "Returns the current site for staff, creating an unsaved default when absent."
  @spec get_site() :: Site.t()
  def get_site do
    Repo.with_tenant_tx(fn -> Repo.one(from s in Site, limit: 1) || default_site() end)
    |> unwrap()
  end

  @doc "Updates the draft website content."
  @spec update_draft(term(), map()) :: {:ok, Site.t()} | {:error, Ecto.Changeset.t()}
  def update_draft(actor, attrs) do
    Repo.with_tenant_tx(fn ->
      site = Repo.one(from s in Site, limit: 1) || default_site()

      site
      |> Site.changeset(%{
        tenant_id: TenantContext.get_tenant_id(),
        enabled: Map.get(attrs, "enabled", Map.get(attrs, :enabled, site.enabled)),
        draft_content: Map.get(attrs, "content", Map.get(attrs, :content, site.draft_content))
      })
      |> Repo.insert_or_update()
      |> audit_result(actor, "website.draft.updated")
    end)
    |> unwrap()
  end

  @doc "Publishes the current draft atomically."
  @spec publish(term()) :: {:ok, Site.t()} | {:error, term()}
  def publish(actor) do
    Repo.with_tenant_tx(fn ->
      site = Repo.one(from s in Site, limit: 1) || default_site()
      now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

      with {:ok, site} <-
             site
             |> Site.changeset(%{
               tenant_id: TenantContext.get_tenant_id(),
               published_content: site.draft_content,
               published_at: now
             })
             |> Repo.insert_or_update(),
           {:ok, _job} <- Events.publish("website.published", %{site_id: site.id}),
           {:ok, _audit} <- Audit.record(actor, "website.published", site, %{}) do
        {:ok, site}
      end
    end)
    |> unwrap()
  end

  @doc "Returns enabled published content with public asset URLs."
  @spec published_site() :: map() | nil
  def published_site do
    Repo.with_tenant_tx(fn ->
      case Repo.one(from s in Site, where: s.enabled == true, limit: 1) do
        %Site{published_at: %DateTime{}} = site -> public_site(site)
        _site -> nil
      end
    end)
    |> unwrap()
  end

  @doc "Creates a public contact submission and transactional event."
  @spec create_contact_submission(map()) ::
          {:ok, ContactSubmission.t()} | {:error, Ecto.Changeset.t()}
  def create_contact_submission(attrs) do
    Repo.with_tenant_tx(fn ->
      changeset =
        ContactSubmission.create_changeset(
          %ContactSubmission{},
          Map.put(attrs, "tenant_id", TenantContext.get_tenant_id())
        )

      with {:ok, submission} <- Repo.insert(changeset),
           {:ok, _job} <-
             Events.publish("website.contact_submitted", %{submission_id: submission.id}) do
        {:ok, submission}
      end
    end)
    |> unwrap()
  end

  @doc "Lists contact submissions newest first."
  @spec page_contact_submissions(map()) :: %{
          data: [ContactSubmission.t()],
          next_cursor: binary() | nil
        }
  def page_contact_submissions(params \\ %{}) do
    Repo.with_tenant_tx(fn ->
      query = from(s in ContactSubmission)

      query =
        case Map.get(params, "status") do
          status when status in ["new", "read", "resolved"] ->
            where(query, [s], s.status == ^status)

          _status ->
            query
        end

      {data, next_cursor} = Pagination.paginate(query, params)
      %{data: data, next_cursor: next_cursor}
    end)
    |> unwrap()
  end

  @doc "Gets one contact submission for an event subscriber."
  @spec get_contact_submission(binary()) :: ContactSubmission.t() | nil
  def get_contact_submission(id) do
    Repo.with_tenant_tx(fn -> Repo.get(ContactSubmission, id) end)
    |> unwrap()
  end

  @doc "Marks a contact submission read or resolved."
  @spec update_contact_submission(term(), binary(), map()) ::
          {:ok, ContactSubmission.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def update_contact_submission(actor, id, attrs) do
    Repo.with_tenant_tx(fn ->
      case Repo.get(ContactSubmission, id) do
        nil ->
          {:error, :not_found}

        submission ->
          submission
          |> ContactSubmission.status_changeset(attrs)
          |> Repo.update()
          |> audit_result(actor, "website.contact.reviewed")
      end
    end)
    |> unwrap()
  end

  @doc "Presigns a hosted-site image upload."
  @spec presign_upload(map()) :: {:ok, Storage.presigned()} | {:error, term()}
  def presign_upload(attrs), do: Storage.presign_put(attrs, TenantContext.get_tenant_id())

  @doc "Adds public URLs beside asset keys for staff previews."
  @spec preview_content(map()) :: map()
  def preview_content(content) when is_map(content), do: asset_urls(content)

  defp default_site do
    %Site{
      tenant_id: TenantContext.get_tenant_id(),
      enabled: true,
      draft_content: @default_content,
      published_content: %{}
    }
  end

  defp public_site(site) do
    %{
      enabled: site.enabled,
      published_at: site.published_at,
      content: asset_urls(site.published_content)
    }
  end

  defp asset_urls(value) when is_list(value), do: Enum.map(value, &asset_urls/1)

  defp asset_urls(value) when is_map(value) do
    Enum.reduce(value, %{}, fn {key, child}, acc ->
      acc = Map.put(acc, key, asset_urls(child))

      if is_binary(key) and String.ends_with?(key, "_key") and is_binary(child) do
        Map.put(acc, String.replace_suffix(key, "_key", "_url"), Storage.public_url(child))
      else
        acc
      end
    end)
  end

  defp asset_urls(value), do: value

  defp audit_result({:ok, record}, actor, action) do
    case Audit.record(actor, action, record, %{}) do
      {:ok, _audit} -> {:ok, record}
      {:error, reason} -> {:error, reason}
    end
  end

  defp audit_result(error, _actor, _action), do: error

  defp unwrap({:ok, value}), do: value
  defp unwrap({:error, reason}), do: {:error, reason}
end
