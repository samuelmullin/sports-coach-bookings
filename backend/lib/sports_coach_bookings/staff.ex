defmodule SportsCoachBookings.Staff do
  @moduledoc """
  Staff identity, memberships, and team management. Owned by WP-01.

  Staff identity is **global** (`staff_users`): one login works across every
  tenant a person belongs to. A `membership` links that identity to a tenant with
  a role (`owner | admin | coach`).

  Auth is JSON-only and hand-written because `mix phx.gen.auth` refuses to run in
  this HTML-less app; the token/password behaviour mirrors what the generator
  produces. See `docs/rfcs/20260928-tenancy-staff-json-auth.md`.
  """

  import Ecto.Query

  alias SportsCoachBookings.Core.Audit
  alias SportsCoachBookings.Core.StaffActor
  alias SportsCoachBookings.Core.TenantContext
  alias SportsCoachBookings.Events
  alias SportsCoachBookings.Repo
  alias SportsCoachBookings.Staff.Membership
  alias SportsCoachBookings.Staff.Notifier
  alias SportsCoachBookings.Staff.Password
  alias SportsCoachBookings.Staff.StaffInvite
  alias SportsCoachBookings.Staff.StaffUser
  alias SportsCoachBookings.Staff.StaffUserToken

  @type membership_result :: %{membership: Membership.t(), staff_user: StaffUser.t()}

  ## Identity

  @doc "Registers a new global staff user (email + password)."
  @spec register_staff_user(map()) :: {:ok, StaffUser.t()} | {:error, Ecto.Changeset.t()}
  def register_staff_user(attrs) do
    %StaffUser{}
    |> StaffUser.registration_changeset(attrs)
    |> Repo.insert()
  end

  @doc "Fetches a staff user by id."
  @spec get_staff_user(binary()) :: StaffUser.t() | nil
  def get_staff_user(id), do: Repo.get(StaffUser, id)

  @doc "Fetches a staff user by case-insensitive email."
  @spec get_staff_user_by_email(binary()) :: StaffUser.t() | nil
  def get_staff_user_by_email(email) when is_binary(email),
    do: Repo.get_by(StaffUser, email: email)

  @doc "Authenticates a staff user by email + password."
  @spec authenticate(binary(), binary()) ::
          {:ok, StaffUser.t()} | {:error, :invalid_credentials}
  def authenticate(email, password) do
    case get_staff_user_by_email(email) do
      %StaffUser{} = user ->
        if StaffUser.valid_password?(user, password) do
          {:ok, user}
        else
          {:error, :invalid_credentials}
        end

      nil ->
        # Run a hash anyway to keep timing comparable for unknown emails.
        _ = Password.verify(password, "pbkdf2_sha256$1$AA==$AA==")
        {:error, :invalid_credentials}
    end
  end

  ## Session tokens

  @doc "Creates a session token for `staff_user`. Returns `{plaintext, token}`."
  @spec create_session_token(StaffUser.t()) :: {binary(), StaffUserToken.t()}
  def create_session_token(%StaffUser{} = staff_user) do
    {plaintext, changeset} = StaffUserToken.build(staff_user, "session")
    {:ok, token} = Repo.insert(changeset)
    {plaintext, token}
  end

  @doc "Resolves a session token to its staff user, or `:error`."
  @spec get_staff_user_by_session_token(binary()) :: {:ok, StaffUser.t()} | :error
  def get_staff_user_by_session_token(plaintext) when is_binary(plaintext) do
    hash = StaffUserToken.hash(plaintext)

    case Repo.one(
           from t in StaffUserToken,
             where: t.token == ^hash and t.context == "session",
             preload: [:staff_user],
             limit: 1
         ) do
      nil -> :error
      token -> if StaffUserToken.expired?(token), do: :error, else: {:ok, token.staff_user}
    end
  end

  def get_staff_user_by_session_token(_plaintext), do: :error

  @doc "Deletes the session token identified by `plaintext`."
  @spec delete_session_token(binary()) :: :ok
  def delete_session_token(plaintext) when is_binary(plaintext) do
    hash = StaffUserToken.hash(plaintext)

    Repo.delete_all(from t in StaffUserToken, where: t.token == ^hash and t.context == "session")
    :ok
  end

  def delete_session_token(_plaintext), do: :ok

  ## Confirmation

  @doc "Creates a confirmation token (plaintext returned for testing)."
  @spec create_confirm_token(StaffUser.t()) :: binary()
  def create_confirm_token(%StaffUser{} = staff_user) do
    {plaintext, changeset} =
      StaffUserToken.build(staff_user, "confirm", sent_to: staff_user.email)

    {:ok, _} = Repo.insert(changeset)
    plaintext
  end

  @doc "Emails confirmation instructions."
  @spec deliver_confirmation_instructions(StaffUser.t()) :: :ok
  def deliver_confirmation_instructions(%StaffUser{} = staff_user) do
    plaintext = create_confirm_token(staff_user)
    Notifier.deliver_confirmation_instructions(staff_user, plaintext)
    :ok
  end

  @doc "Confirms the staff user owning `plaintext`."
  @spec confirm_staff_user(binary()) ::
          {:ok, StaffUser.t()} | {:error, :invalid_token}
  def confirm_staff_user(plaintext) when is_binary(plaintext) do
    hash = StaffUserToken.hash(plaintext)

    case Repo.one(
           from t in StaffUserToken,
             where: t.token == ^hash and t.context == "confirm",
             preload: [:staff_user],
             limit: 1
         ) do
      nil ->
        {:error, :invalid_token}

      token ->
        if StaffUserToken.expired?(token) do
          {:error, :invalid_token}
        else
          {:ok, staff_user} =
            token.staff_user
            |> StaffUser.confirm_changeset()
            |> Repo.update()

          delete_context_tokens(token.staff_user_id, "confirm")
          {:ok, staff_user}
        end
    end
  end

  def confirm_staff_user(_), do: {:error, :invalid_token}

  ## Password reset

  @doc "Emails password-reset instructions; always `:ok` to avoid leaking emails."
  @spec deliver_reset_password_instructions(binary()) :: :ok
  def deliver_reset_password_instructions(email) when is_binary(email) do
    case get_staff_user_by_email(email) do
      %StaffUser{} = staff_user ->
        {plaintext, changeset} = StaffUserToken.build(staff_user, "reset_password")
        {:ok, _} = Repo.insert(changeset)
        Notifier.deliver_reset_password_instructions(staff_user, plaintext)

      nil ->
        :noop
    end

    :ok
  end

  @doc "Resets a password from a reset token."
  @spec reset_password(binary(), map()) ::
          {:ok, StaffUser.t()} | {:error, :invalid_token} | {:error, Ecto.Changeset.t()}
  def reset_password(plaintext, attrs) when is_binary(plaintext) do
    hash = StaffUserToken.hash(plaintext)

    case Repo.one(
           from t in StaffUserToken,
             where: t.token == ^hash and t.context == "reset_password",
             preload: [:staff_user],
             limit: 1
         ) do
      nil -> {:error, :invalid_token}
      token -> maybe_reset_password(token, attrs)
    end
  end

  def reset_password(_plaintext, _attrs), do: {:error, :invalid_token}

  defp maybe_reset_password(token, attrs) do
    if StaffUserToken.expired?(token) do
      {:error, :invalid_token}
    else
      apply_password_reset(token, attrs)
    end
  end

  defp apply_password_reset(token, attrs) do
    case token.staff_user |> StaffUser.password_changeset(attrs) |> Repo.update() do
      {:ok, staff_user} ->
        delete_context_tokens(token.staff_user_id, "reset_password")
        {:ok, staff_user}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  ## Memberships (tenant-scoped)

  @doc """
  Lists the caller's active memberships across **all** tenants.

  Runs on the platform host, so it sets `app.staff_user_id` and relies on the
  additive `memberships_self_read` RLS policy. Used by `GET /api/platform/me`.
  """
  @spec list_memberships(StaffUser.t()) :: [Membership.t()]
  def list_memberships(%StaffUser{id: id}) do
    case Repo.transaction(fn ->
           set_staff_guc(id)

           Repo.all(
             from(m in Membership,
               where: m.staff_user_id == ^id and m.status == :active,
               order_by: [asc: m.inserted_at]
             ),
             skip_tenant: true
           )
         end) do
      {:ok, memberships} -> memberships
      {:error, _} -> []
    end
  end

  @doc "Lists a tenant's active memberships."
  @spec list_team() :: [Membership.t()]
  def list_team do
    read(fn ->
      Membership
      |> where([m], m.status == :active)
      |> order_by([m], asc: m.inserted_at)
      |> preload(:staff_user)
      |> Repo.all()
    end)
  end

  @doc "Lists a tenant's active coaches (for scheduling pickers)."
  @spec list_coaches() :: [Membership.t()]
  def list_coaches do
    read(fn ->
      Membership
      |> where([m], m.role == :coach and m.status == :active)
      |> order_by([m], asc: m.inserted_at)
      |> preload(:staff_user)
      |> Repo.all()
    end)
  end

  @doc "Fetches a membership by id for the resolved tenant."
  @spec get_membership!(binary()) :: Membership.t()
  def get_membership!(id), do: read(fn -> Repo.get!(Membership, id) end)

  @doc "Fetches the active membership for `staff_user_id` in the resolved tenant."
  @spec get_active_membership(binary()) :: Membership.t() | nil
  def get_active_membership(staff_user_id) when is_binary(staff_user_id) do
    read(fn ->
      Repo.one(
        from m in Membership,
          where: m.staff_user_id == ^staff_user_id and m.status == :active,
          limit: 1
      )
    end)
  end

  @doc """
  Adds (or reactivates) a membership. Must run with a tenant in context.

  Used by tenant signup to create the owner membership.
  """
  @spec upsert_membership(binary(), binary(), atom(), keyword()) ::
          {:ok, Membership.t()} | {:error, Ecto.Changeset.t()}
  def upsert_membership(tenant_id, staff_user_id, role, opts \\ []) do
    read(fn ->
      attrs = %{
        tenant_id: tenant_id,
        staff_user_id: staff_user_id,
        role: role,
        status: :active,
        display_name: opts[:display_name]
      }

      case Repo.get_by(Membership, tenant_id: tenant_id, staff_user_id: staff_user_id) do
        nil -> Repo.insert(Membership.changeset(%Membership{}, attrs))
        existing -> existing |> Membership.changeset(attrs) |> Repo.update()
      end
    end)
  end

  ## Invitations

  @doc """
  Invites `email` to the resolved tenant with `role`.

  The policy check for the requested role is done by the controller; the context
  additionally enforces it so it cannot be bypassed.
  """
  @spec invite_staff(StaffActor.t(), map()) ::
          {:ok, %{invite: StaffInvite.t(), token: binary()}}
          | {:error, :forbidden | :already_member | :invalid_role | Ecto.Changeset.t()}
  def invite_staff(%StaffActor{} = actor, attrs) do
    email = attrs[:email] || attrs["email"]
    role = attrs[:role] || attrs["role"]

    with {:ok, role} <- normalize_role(role),
         :ok <- authorize_invite(actor, role),
         :error <- find_active_membership_by_email(email) do
      do_invite(actor, email, role)
    else
      {:ok, _membership} -> {:error, :already_member}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Fetches a pending invite by id for the resolved tenant."
  @spec get_invite(binary()) :: StaffInvite.t() | nil
  def get_invite(id), do: read(fn -> Repo.get(StaffInvite, id) end)

  @doc "Lists pending (unaccepted, unexpired) invites for the resolved tenant."
  @spec list_invites() :: [StaffInvite.t()]
  def list_invites do
    now = now()

    read(fn ->
      Repo.all(
        from i in StaffInvite,
          where: is_nil(i.accepted_at) and i.expires_at > ^now,
          order_by: [desc: i.inserted_at]
      )
    end)
  end

  @doc "Fetches a pending invite by its plaintext token for the resolved tenant."
  @spec get_invite_by_token(binary()) :: StaffInvite.t() | nil
  def get_invite_by_token(token) when is_binary(token) do
    hash = StaffUserToken.hash(token)

    read(fn ->
      Repo.one(
        from i in StaffInvite,
          where: i.token_hash == ^hash and is_nil(i.accepted_at),
          limit: 1
      )
    end)
  end

  @doc """
  Accepts an invite.

  `opts[:staff_user]` is the logged-in user, when there is one. With no logged-in
  user the invite email is trusted (it proves control of the address) and a new,
  pre-confirmed staff user is created from `params`.
  """
  @spec accept_invite(binary(), map(), keyword()) ::
          {:ok, membership_result()}
          | {:error, :invalid_invite | :expired_invite | :already_member | Ecto.Changeset.t()}
  def accept_invite(token, params, opts \\ []) do
    hash = StaffUserToken.hash(token)
    read(fn -> find_and_accept_invite(hash, params, opts) end)
  end

  defp find_and_accept_invite(hash, params, opts) do
    case Repo.one(
           from i in StaffInvite,
             where: i.token_hash == ^hash and is_nil(i.accepted_at),
             limit: 1
         ) do
      nil -> {:error, :invalid_invite}
      %StaffInvite{} = invite -> accept_found_invite(invite, params, opts)
    end
  end

  defp accept_found_invite(invite, params, opts) do
    if StaffInvite.expired?(invite) do
      {:error, :expired_invite}
    else
      do_accept_invite(invite, params, opts)
    end
  end

  ## Role changes / removal / ownership

  @doc "Changes a member's role. Enforces last-owner and inviter rules."
  @spec change_role(StaffActor.t(), binary(), atom() | binary()) ::
          {:ok, Membership.t()}
          | {:error, :forbidden | :not_found | :last_owner | :invalid_role}
  def change_role(%StaffActor{} = actor, membership_id, role) do
    with {:ok, role} <- normalize_role(role),
         :ok <- authorize_mutation(actor, role) do
      read(fn -> load_and_change_role(actor, membership_id, role) end)
    end
  end

  defp load_and_change_role(actor, membership_id, role) do
    case Repo.get(Membership, membership_id) do
      nil -> {:error, :not_found}
      %Membership{} = membership -> apply_role_change(actor, membership, role)
    end
  end

  defp apply_role_change(actor, membership, role) do
    cond do
      actor.role == :admin and membership.role == :owner ->
        {:error, :forbidden}

      membership.role == :owner and role != :owner and last_owner?(membership) ->
        {:error, :last_owner}

      true ->
        persist_role_change(actor, membership, role)
    end
  end

  defp persist_role_change(actor, membership, role) do
    with {:ok, updated} <- membership |> Membership.changeset(%{role: role}) |> Repo.update(),
         {:ok, _} <-
           Audit.record(actor, "staff.role_changed", updated, %{
             from: to_string(membership.role),
             to: to_string(role)
           }) do
      {:ok, updated}
    end
  end

  @doc "Soft-removes a member. Enforces last-owner and removal rules."
  @spec remove_membership(StaffActor.t(), binary()) ::
          {:ok, Membership.t()} | {:error, :forbidden | :not_found | :last_owner}
  def remove_membership(%StaffActor{} = actor, membership_id) do
    read(fn -> load_and_remove_membership(actor, membership_id) end)
  end

  defp load_and_remove_membership(actor, membership_id) do
    case Repo.get(Membership, membership_id) do
      nil -> {:error, :not_found}
      %Membership{} = membership -> do_remove_membership(actor, membership)
    end
  end

  defp do_remove_membership(actor, membership) do
    with :ok <- authorize_removal(actor, membership),
         :ok <- ensure_not_last_owner(membership),
         {:ok, updated} <-
           membership |> Membership.changeset(%{status: :removed}) |> Repo.update(),
         {:ok, _} <- Audit.record(actor, "staff.removed", updated, %{}),
         {:ok, _} <-
           Events.publish("staff.removed", %{
             tenant_id: updated.tenant_id,
             membership_id: updated.id,
             staff_user_id: updated.staff_user_id,
             role: to_string(updated.role)
           }) do
      {:ok, updated}
    end
  end

  @doc """
  Transfers ownership to `membership_id`: promotes it to owner and demotes every
  other active owner to admin. Owner-only (checked by the policy).
  """
  @spec transfer_ownership(StaffActor.t(), binary()) ::
          {:ok, Membership.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def transfer_ownership(%StaffActor{} = actor, membership_id) do
    read(fn -> load_and_transfer_ownership(actor, membership_id) end)
  end

  defp load_and_transfer_ownership(actor, membership_id) do
    case Repo.get(Membership, membership_id) do
      nil -> {:error, :not_found}
      %Membership{status: :removed} -> {:error, :not_found}
      %Membership{} = target -> promote_owner(actor, target)
    end
  end

  defp promote_owner(actor, target) do
    with :ok <- demote_other_owners(target),
         {:ok, promoted} <-
           target |> Membership.changeset(%{role: :owner, status: :active}) |> Repo.update(),
         {:ok, _} <- Audit.record(actor, "tenant.ownership_transferred", promoted, %{}) do
      {:ok, promoted}
    end
  end

  ## Private helpers

  defp do_invite(actor, email, role) do
    plaintext = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
    tenant_id = TenantContext.get_tenant_id()
    expires_at = DateTime.add(now(), StaffInvite.validity_days(), :day)

    changeset =
      StaffInvite.changeset(%StaffInvite{}, %{
        tenant_id: tenant_id,
        email: email,
        role: role,
        token_hash: StaffUserToken.hash(plaintext),
        invited_by: actor.membership && actor.membership.id,
        expires_at: expires_at
      })

    with {:ok, invite} <- Repo.insert(changeset),
         {:ok, _} <-
           Events.publish("staff.invited", %{
             tenant_id: tenant_id,
             invite_id: invite.id,
             email: email,
             role: to_string(role)
           }) do
      Notifier.deliver_staff_invite(invite, plaintext, TenantContext.get_tenant())
      {:ok, %{invite: invite, token: plaintext}}
    end
  end

  defp do_accept_invite(invite, params, opts) do
    with {:ok, staff_user} <- resolve_invite_user(invite, params, opts),
         :error <- existing_active_membership(invite, staff_user) do
      attrs = %{
        tenant_id: invite.tenant_id,
        staff_user_id: staff_user.id,
        role: invite.role,
        status: :active
      }

      existing =
        Repo.get_by(Membership, tenant_id: invite.tenant_id, staff_user_id: staff_user.id)

      with {:ok, membership} <-
             upsert_existing_membership(existing, attrs),
           {:ok, _} <-
             invite |> StaffInvite.changeset(%{accepted_at: now()}) |> Repo.update(),
           {:ok, _} <-
             Events.publish("staff.joined", %{
               tenant_id: invite.tenant_id,
               membership_id: membership.id,
               staff_user_id: staff_user.id,
               role: to_string(membership.role)
             }) do
        {:ok, %{membership: membership, staff_user: staff_user}}
      end
    else
      {:ok, _membership} -> {:error, :already_member}
      {:error, reason} -> {:error, reason}
    end
  end

  defp resolve_invite_user(invite, params, opts) do
    case opts[:staff_user] do
      %StaffUser{} = staff_user ->
        {:ok, staff_user}

      nil ->
        case get_staff_user_by_email(invite.email) do
          %StaffUser{} = staff_user ->
            {:ok, staff_user}

          nil ->
            register_invited_user(invite, params)
        end
    end
  end

  defp register_invited_user(invite, params) do
    attrs = %{
      email: invite.email,
      password: params[:password] || params["password"]
    }

    case register_staff_user(attrs) do
      {:ok, staff_user} ->
        {:ok, _} = staff_user |> change_confirmed() |> Repo.update()
        {:ok, %{staff_user | confirmed_at: now()}}

      {:error, changeset} ->
        # Already-registered race: fall back to the existing account.
        case get_staff_user_by_email(invite.email) do
          %StaffUser{} = staff_user -> {:ok, staff_user}
          nil -> {:error, changeset}
        end
    end
  end

  defp change_confirmed(staff_user), do: Ecto.Changeset.change(staff_user, confirmed_at: now())

  defp upsert_existing_membership(nil, attrs),
    do: %Membership{} |> Membership.changeset(attrs) |> Repo.insert()

  defp upsert_existing_membership(%Membership{} = membership, attrs),
    do: membership |> Membership.changeset(attrs) |> Repo.update()

  defp existing_active_membership(invite, staff_user) do
    case Repo.get_by(Membership, tenant_id: invite.tenant_id, staff_user_id: staff_user.id) do
      %Membership{status: :active} -> {:ok, :already_member}
      _ -> :error
    end
  end

  defp find_active_membership_by_email(email) do
    case get_staff_user_by_email(email) do
      nil -> :error
      %StaffUser{id: id} -> active_membership_for(id)
    end
  end

  defp active_membership_for(staff_user_id) do
    case read(fn ->
           Repo.one(
             from m in Membership,
               where: m.staff_user_id == ^staff_user_id and m.status == :active,
               limit: 1
           )
         end) do
      %Membership{} = membership -> {:ok, membership}
      _ -> :error
    end
  end

  defp last_owner?(%Membership{tenant_id: tenant_id}) do
    read(fn ->
      Repo.one(
        from m in Membership,
          where: m.tenant_id == ^tenant_id and m.role == :owner and m.status == :active,
          select: count(m.id)
      )
    end) <= 1
  end

  defp ensure_not_last_owner(%Membership{role: :owner} = membership) do
    if last_owner?(membership), do: {:error, :last_owner}, else: :ok
  end

  defp ensure_not_last_owner(%Membership{}), do: :ok

  defp demote_other_owners(%Membership{id: id, tenant_id: tenant_id}) do
    Repo.update_all(
      from(m in Membership,
        where:
          m.tenant_id == ^tenant_id and m.role == :owner and m.status == :active and m.id != ^id
      ),
      set: [role: :admin, updated_at: now()]
    )

    :ok
  end

  defp authorize_invite(%StaffActor{role: :owner}, _role), do: :ok
  defp authorize_invite(%StaffActor{role: :admin}, role) when role in [:admin, :coach], do: :ok
  defp authorize_invite(_actor, _role), do: {:error, :forbidden}

  defp authorize_mutation(%StaffActor{role: :owner}, _role), do: :ok
  defp authorize_mutation(%StaffActor{role: :admin}, role) when role in [:admin, :coach], do: :ok
  defp authorize_mutation(_actor, _role), do: {:error, :forbidden}

  defp authorize_removal(%StaffActor{role: :owner}, _membership), do: :ok

  defp authorize_removal(%StaffActor{role: :admin}, %Membership{role: role}) when role != :owner,
    do: :ok

  defp authorize_removal(_actor, _membership), do: {:error, :forbidden}

  defp normalize_role(role) when role in [:owner, :admin, :coach], do: {:ok, role}

  defp normalize_role(role) when is_binary(role) do
    case role do
      "owner" -> {:ok, :owner}
      "admin" -> {:ok, :admin}
      "coach" -> {:ok, :coach}
      _ -> {:error, :invalid_role}
    end
  end

  defp normalize_role(_role), do: {:error, :invalid_role}

  defp delete_context_tokens(staff_user_id, context) do
    Repo.delete_all(
      from t in StaffUserToken,
        where: t.staff_user_id == ^staff_user_id and t.context == ^context
    )
  end

  defp set_staff_guc(staff_user_id) do
    Repo.query!("SELECT set_config('app.staff_user_id', $1, true)", [staff_user_id])
    :ok
  end

  defp read(fun) do
    case Repo.with_tenant_tx(fun) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:microsecond)
end
