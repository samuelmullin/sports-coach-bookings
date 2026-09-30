defmodule SportsCoachBookings.Legal do
  @moduledoc """
  Tenant-owned, versioned legal documents: Terms of Service, Privacy Policy, and
  any future kinds. Owned by the portal legal-documents work.

  Each `(tenant, kind)` has at most one `active` version. Publishing a new
  version (`publish_document/2`) supersedes the previous one in the same
  transaction, so reads of the active document are never inconsistent with a
  publish in flight.

  All functions are tenant-scoped: callers place the tenant in context (via
  `SportsCoachBookingsWeb.Plugs.ResolveTenant` in requests or
  `SportsCoachBookings.DataCase.put_tenant/1` in tests) and every function runs
  inside `SportsCoachBookings.Repo.with_tenant_tx/2` so RLS applies.
  """

  import Ecto.Query

  alias SportsCoachBookings.Core.Audit
  alias SportsCoachBookings.Core.Policy
  alias SportsCoachBookings.Core.TenantContext
  alias SportsCoachBookings.Legal.LegalDocument
  alias SportsCoachBookings.Notifications.Broadcasts.Markdown
  alias SportsCoachBookings.Repo

  @kinds ["terms", "privacy"]
  @actor_action "legal.document.published"

  @doc "The default kinds seeded for a tenant."
  @spec kinds() :: [String.t()]
  def kinds, do: @kinds

  ## Reads

  @doc "Lists every version of `kind`, newest first. `kind` may be `nil` for all."
  @spec list_documents(String.t() | atom() | nil) :: [LegalDocument.t()]
  def list_documents(kind \\ nil) do
    read(fn ->
      LegalDocument
      |> where_kind(kind)
      |> order_by([d], desc: d.kind, desc: d.version)
      |> Repo.all()
    end)
  end

  @doc "Lists the active document for every kind, ordered by kind."
  @spec list_active_documents() :: [LegalDocument.t()]
  def list_active_documents do
    read(fn ->
      Repo.all(
        from d in LegalDocument,
          where: d.active == true,
          order_by: [asc: d.kind]
      )
    end)
  end

  @doc "Fetches the active document of `kind`."
  @spec active_document(String.t() | atom()) ::
          {:ok, LegalDocument.t()} | {:error, :not_found}
  def active_document(kind) do
    read(fn ->
      case Repo.one(
             from d in LegalDocument,
               where: d.kind == ^normalize_kind(kind) and d.active == true,
               limit: 1
           ) do
        nil -> {:error, :not_found}
        document -> {:ok, document}
      end
    end)
  end

  @doc "Fetches a specific version of `kind`."
  @spec get_document(String.t() | atom(), integer()) ::
          {:ok, LegalDocument.t()} | {:error, :not_found}
  def get_document(kind, version) when is_integer(version) do
    read(fn ->
      case Repo.one(
             from d in LegalDocument,
               where: d.kind == ^normalize_kind(kind) and d.version == ^version,
               limit: 1
           ) do
        nil -> {:error, :not_found}
        document -> {:ok, document}
      end
    end)
  end

  @doc "Fetches a document by id, raising when it is absent for this tenant."
  @spec get_document!(binary()) :: LegalDocument.t()
  def get_document!(id), do: read(fn -> Repo.get!(LegalDocument, id) end)

  ## Writes

  @doc """
  Publishes a new version of a document and records an audit event.

  Accepts `:kind`, `:title`, `:body_markdown`, and an optional `:active`
  (default `true`). The new version number is `max(version) + 1` for the
  `(tenant, kind)`. When the new version is active the previous active version
  is deactivated atomically.
  """
  @spec publish_document(Policy.actor(), map() | keyword()) ::
          {:ok, LegalDocument.t()} | {:error, Ecto.Changeset.t()}
  def publish_document(actor, attrs) do
    attrs = normalize_attrs(attrs)

    case Repo.with_tenant_tx(fn -> do_publish(actor, attrs) end) do
      {:ok, {:ok, document}} -> {:ok, document}
      {:ok, {:error, changeset}} -> {:error, changeset}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Idempotently seeds the default Terms of Service and Privacy Policy for the
  tenant in context. Does nothing for a kind that already has an active
  document.
  """
  @spec seed_defaults() :: :ok | {:error, term()}
  def seed_defaults do
    Enum.reduce_while(@kinds, :ok, fn kind, :ok ->
      case seed_kind(kind) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  @doc "Idempotently seeds the defaults for `tenant_id` (used by `tenant.created`)."
  @spec seed_defaults(binary()) :: :ok | {:error, term()}
  def seed_defaults(tenant_id) when is_binary(tenant_id) do
    TenantContext.with_tenant(tenant_id, fn -> seed_defaults() end)
  end

  @doc """
  The default document attributes for `kind`, used when seeding a tenant.
  """
  @spec default_attrs(String.t() | atom()) :: map()
  def default_attrs(kind) do
    kind = normalize_kind(kind)

    %{
      "kind" => kind,
      "title" => default_title(kind),
      "body_markdown" => default_body(kind),
      "active" => true
    }
  end

  @doc """
  Notification assigns for a document body: plain text plus rendered HTML.

  Used by the "email me a copy" endpoints for both legal documents and waivers.
  """
  @spec render_assigns(String.t(), String.t()) :: %{
          title: String.t(),
          body: String.t(),
          body_html: String.t()
        }
  def render_assigns(title, body_markdown) do
    %{
      title: title,
      body: to_plain_text(body_markdown),
      body_html: Markdown.to_html(body_markdown)
    }
  end

  @doc "Notification assigns for a `LegalDocument`."
  @spec document_assigns(LegalDocument.t()) :: %{
          title: String.t(),
          body: String.t(),
          body_html: String.t()
        }
  def document_assigns(%LegalDocument{} = document) do
    render_assigns(document.title, document.body_markdown)
  end

  @doc """
  A conservative markdown-to-plain-text rendering for the email text part.

  Strips heading markers, list bullets, emphasis markers, and link syntax while
  keeping the words and line breaks.
  """
  @spec to_plain_text(String.t() | nil) :: String.t()
  def to_plain_text(nil), do: ""

  def to_plain_text(markdown) when is_binary(markdown) do
    markdown
    |> String.replace("\r\n", "\n")
    |> String.split("\n")
    |> Enum.map_join("\n", &plain_line/1)
    |> String.trim()
  end

  defp plain_line(line) do
    line
    |> String.replace(~r/^\s{0,3}\#{1,6}\s+/, "")
    |> String.replace(~r/^\s*[-*+]\s+/, "- ")
    |> String.replace(~r/\[([^\]]*)\]\(([^)\s]+)\)/, "\\1 (\\2)")
    |> String.replace("**", "")
    |> String.replace("__", "")
    |> String.replace("`", "")
    |> String.replace(~r/(?<!\*)\*(?!\*)/, "")
  end

  ## Private

  defp seed_kind(kind) do
    case active_document(kind) do
      {:ok, _document} -> :ok
      {:error, :not_found} -> publish_or_error(default_attrs(kind))
    end
  end

  defp publish_or_error(attrs) do
    case publish_document(nil, attrs) do
      {:ok, _document} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp do_publish(actor, attrs) do
    kind = normalize_kind(fetch_attr(attrs, :kind))
    active = active?(fetch_attr(attrs, :active))

    if active, do: deactivate_kind(kind)

    changes =
      attrs
      |> tenant_attrs()
      |> Map.put("kind", kind)
      |> Map.put("version", next_version(kind))
      |> Map.put("active", active)

    case %LegalDocument{} |> LegalDocument.changeset(changes) |> Repo.insert() do
      {:ok, document} ->
        Audit.record(actor, @actor_action, document, %{kind: kind, version: document.version})
        {:ok, document}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  defp deactivate_kind(kind) do
    now = DateTime.utc_now()

    Repo.update_all(
      from(d in LegalDocument, where: d.kind == ^kind and d.active == true),
      set: [active: false, updated_at: now]
    )
  end

  defp next_version(kind) do
    max =
      Repo.one(
        from d in LegalDocument,
          where: d.kind == ^kind,
          select: max(d.version)
      )

    (max || 0) + 1
  end

  defp where_kind(query, nil), do: query
  defp where_kind(query, kind), do: where(query, [d], d.kind == ^normalize_kind(kind))

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

  defp normalize_attrs(attrs), do: Enum.into(attrs, %{})

  defp fetch_attr(attrs, key) do
    attrs = Enum.into(attrs, %{})
    Map.get(attrs, key) || Map.get(attrs, to_string(key))
  end

  defp active?(nil), do: true
  defp active?(value), do: value in [true, "true", "1", 1]

  defp normalize_kind(nil), do: nil
  defp normalize_kind(kind) when is_atom(kind), do: Atom.to_string(kind)
  defp normalize_kind(kind) when is_binary(kind), do: kind

  defp default_title("terms"), do: "Terms of Service"
  defp default_title("privacy"), do: "Privacy Policy"

  defp default_title(kind),
    do: kind |> to_string() |> String.replace("_", " ") |> String.capitalize()

  defp default_body("terms") do
    """
    # Terms of Service

    Welcome to SportsCoachBookings. By creating an account and using the
    service you agree to these terms.

    ## Using the service

    - You must provide accurate information about yourself and the players you
      register.
    - You are responsible for keeping your account password secure.
    - You must be the parent or legal guardian of any player you register.

    ## Bookings and payments

    - Bookings are subject to the cancellation policy shown at checkout.
    - Prices are shown in the provider's currency and include applicable taxes.
    - Credits are non-transferable and may expire as described at purchase.

    ## Acceptable use

    Do not misuse the service, interfere with other users, or upload unlawful
    content. We may suspend accounts that break these rules.

    ## Changes

    We may update these terms. When we publish a new version you will be asked to
    review it the next time you sign in.
    """
  end

  defp default_body("privacy") do
    """
    # Privacy Policy

    This policy explains what personal information SportsCoachBookings
    collects, why we collect it, and the choices you have.

    ## What we collect

    - Account details such as your name, email address, and phone number.
    - Information about the players in your household, including emergency
      contacts and medical notes you choose to provide.
    - Booking, payment, and waiver records needed to run the service.

    ## How we use it

    We use your information to operate bookings, take payments, meet our
    record-keeping duties, and send service messages. We do not sell your
    personal information.

    ## Sharing

    We share information only with service providers who help us run the
    platform, and where required by law. Medical information is limited to the
    coaches who need it.

    ## Your choices

    You can update your account details, request a copy of your data, or ask us
    to delete your account. Marketing emails can be turned off at any time.
    """
  end

  defp default_body(_kind), do: "# Document\n\nContent for this document has not been added yet."
end
