defmodule SportsCoachBookings.Customers do
  @moduledoc """
  Customer accounts and households. Owned by WP-02.

  Customer identity is **per tenant**: the same email at two tenants is two
  independent accounts. Every tenant-owned read/write runs inside
  `SportsCoachBookings.Repo.with_tenant_tx/2` so the RLS GUC is set, and the
  tenant must be in process context (resolved from the host by
  `SportsCoachBookingsWeb.Plugs.ResolveTenant`).

  Registration creates the customer user plus a household and a `primary`
  household member in one transaction and publishes `customer.registered`.
  Invitations publish `household.member_invited` / `household.member_joined`.
  """

  import Ecto.Query

  alias Ecto.Multi
  alias SportsCoachBookings.Core.Audit
  alias SportsCoachBookings.Core.CustomerActor
  alias SportsCoachBookings.Core.Pagination
  alias SportsCoachBookings.Core.TenantContext
  alias SportsCoachBookings.Customers.CustomerUser
  alias SportsCoachBookings.Customers.CustomerUserToken
  alias SportsCoachBookings.Customers.Household
  alias SportsCoachBookings.Customers.HouseholdInvite
  alias SportsCoachBookings.Customers.HouseholdMember
  alias SportsCoachBookings.Customers.Notifier
  alias SportsCoachBookings.Customers.Preferences
  alias SportsCoachBookings.Events
  alias SportsCoachBookings.Repo
  alias SportsCoachBookings.Staff.Password

  @type registration_result :: %{
          customer_user: CustomerUser.t(),
          household: Household.t(),
          member: HouseholdMember.t(),
          confirmation_token: binary()
        }

  ## Identity

  @doc """
  Registers a customer for the tenant in context.

  Creates the customer user, a household, and a `primary` household member in a
  single transaction; publishes `customer.registered`; creates a confirmation
  token and emails it (stubbed until WP-05). Returns the created records and the
  plaintext confirmation token.
  """
  @spec register_customer(map()) :: {:ok, registration_result()} | {:error, Ecto.Changeset.t()}
  def register_customer(attrs) do
    tenant_id = TenantContext.get_tenant_id()
    attrs = stringify(attrs)

    multi =
      Multi.new()
      |> Multi.insert(
        :customer_user,
        CustomerUser.registration_changeset(%CustomerUser{tenant_id: tenant_id}, attrs)
      )
      |> Multi.insert(:household, fn %{customer_user: user} ->
        Household.changeset(%Household{}, %{
          tenant_id: tenant_id,
          name: household_name(user)
        })
      end)
      |> Multi.insert(:member, fn %{customer_user: user, household: household} ->
        HouseholdMember.changeset(%HouseholdMember{}, %{
          tenant_id: tenant_id,
          household_id: household.id,
          customer_user_id: user.id,
          role: :primary,
          relationship: "self"
        })
      end)
      |> Multi.run(:confirmation_token, fn _repo, %{customer_user: user} ->
        {plaintext, changeset} = CustomerUserToken.build(user, "confirm", sent_to: user.email)
        {:ok, _} = Repo.insert(changeset)
        {:ok, plaintext}
      end)
      |> Multi.run(:event, fn _repo, %{customer_user: user, household: household} ->
        Events.publish("customer.registered", %{
          tenant_id: tenant_id,
          customer_user_id: user.id,
          household_id: household.id
        })
      end)

    with {:ok, changes} <- multi_tx(multi) do
      Notifier.deliver_confirmation_instructions(
        changes.customer_user,
        changes.confirmation_token
      )

      {:ok, Map.take(changes, [:customer_user, :household, :member, :confirmation_token])}
    end
  end

  @doc """
  Authenticates a customer by email + password in the tenant in context.

  Deactivated accounts are rejected with `{:error, :deactivated}` even when the
  password is correct (they can no longer log in).
  """
  @spec authenticate(binary(), binary()) ::
          {:ok, CustomerUser.t()} | {:error, :invalid_credentials | :deactivated}
  def authenticate(email, password) do
    case get_customer_user_by_email(email) do
      %CustomerUser{} = user -> check_password(user, password)
      nil -> invalid_credentials(password)
    end
  end

  @doc "Fetches a customer user by id."
  @spec get_customer_user(binary()) :: CustomerUser.t() | nil
  def get_customer_user(id), do: read(fn -> Repo.get(CustomerUser, id) end)

  @doc "Fetches a customer user by id, raising if absent."
  @spec get_customer_user!(binary()) :: CustomerUser.t()
  def get_customer_user!(id), do: read(fn -> Repo.get!(CustomerUser, id) end)

  @doc "Fetches a customer user by case-insensitive email in the tenant in context."
  @spec get_customer_user_by_email(binary()) :: CustomerUser.t() | nil
  def get_customer_user_by_email(email) when is_binary(email),
    do: read(fn -> Repo.get_by(CustomerUser, email: email) end)

  @doc """
  Returns `:ok` when the customer's email is confirmed, else
  `{:error, :email_unconfirmed}`.

  Exported for the purchase/booking guard paths (WP-13/WP-14), which must refuse
  an unconfirmed customer with a `403 email_unconfirmed`.
  """
  @spec require_confirmed(CustomerUser.t()) :: :ok | {:error, :email_unconfirmed}
  def require_confirmed(%CustomerUser{} = customer_user) do
    if CustomerUser.confirmed?(customer_user), do: :ok, else: {:error, :email_unconfirmed}
  end

  ## Session tokens

  @doc "Creates a session token for `customer_user`. Returns `{plaintext, token}`."
  @spec create_session_token(CustomerUser.t()) :: {binary(), CustomerUserToken.t()}
  def create_session_token(%CustomerUser{} = customer_user) do
    {plaintext, changeset} = CustomerUserToken.build(customer_user, "session")
    {:ok, token} = read(fn -> Repo.insert(changeset) end)
    {plaintext, token}
  end

  @doc "Resolves a session token to an active customer user, or `:error`."
  @spec get_customer_user_by_session_token(binary()) :: {:ok, CustomerUser.t()} | :error
  def get_customer_user_by_session_token(plaintext) when is_binary(plaintext) do
    hash = CustomerUserToken.hash(plaintext)

    case read(fn ->
           Repo.one(
             from t in CustomerUserToken,
               where: t.token == ^hash and t.context == "session",
               preload: [:customer_user],
               limit: 1
           )
         end) do
      %CustomerUserToken{} = token -> session_user(token)
      _ -> :error
    end
  end

  def get_customer_user_by_session_token(_plaintext), do: :error

  @doc "Deletes the session token identified by `plaintext`."
  @spec delete_session_token(binary()) :: :ok
  def delete_session_token(plaintext) when is_binary(plaintext) do
    hash = CustomerUserToken.hash(plaintext)

    read(fn ->
      Repo.delete_all(
        from t in CustomerUserToken, where: t.token == ^hash and t.context == "session"
      )
    end)

    :ok
  end

  def delete_session_token(_plaintext), do: :ok

  ## Confirmation

  @doc "Creates a confirmation token (plaintext returned for testing)."
  @spec create_confirm_token(CustomerUser.t()) :: binary()
  def create_confirm_token(%CustomerUser{} = customer_user) do
    {plaintext, changeset} =
      CustomerUserToken.build(customer_user, "confirm", sent_to: customer_user.email)

    {:ok, _} = read(fn -> Repo.insert(changeset) end)
    plaintext
  end

  @doc "Emails confirmation instructions (stubbed until WP-05 is merged)."
  @spec deliver_confirmation_instructions(CustomerUser.t()) :: :ok
  def deliver_confirmation_instructions(%CustomerUser{} = customer_user) do
    plaintext = create_confirm_token(customer_user)
    Notifier.deliver_confirmation_instructions(customer_user, plaintext)
    :ok
  end

  @doc "Confirms the customer user owning `plaintext`."
  @spec confirm_customer_user(binary()) ::
          {:ok, CustomerUser.t()} | {:error, :invalid_token}
  def confirm_customer_user(plaintext) when is_binary(plaintext) do
    hash = CustomerUserToken.hash(plaintext)

    read(fn ->
      case Repo.one(
             from t in CustomerUserToken,
               where: t.token == ^hash and t.context == "confirm",
               preload: [:customer_user],
               limit: 1
           ) do
        nil ->
          {:error, :invalid_token}

        %CustomerUserToken{} = token ->
          confirm_found_token(token)
      end
    end)
  end

  def confirm_customer_user(_plaintext), do: {:error, :invalid_token}

  ## Password reset

  @doc "Emails password-reset instructions; always `:ok` to avoid leaking emails."
  @spec deliver_reset_password_instructions(binary()) :: :ok
  def deliver_reset_password_instructions(email) when is_binary(email) do
    result =
      read(fn ->
        case Repo.get_by(CustomerUser, email: email) do
          %CustomerUser{} = user ->
            {plaintext, changeset} = CustomerUserToken.build(user, "reset_password")
            {:ok, _} = Repo.insert(changeset)
            {:ok, {user, plaintext}}

          nil ->
            :noop
        end
      end)

    if match?({:ok, {_user, _plaintext}}, result) do
      {:ok, {user, plaintext}} = result
      Notifier.deliver_reset_password_instructions(user, plaintext)
    end

    :ok
  end

  @doc "Resets a password from a reset token."
  @spec reset_password(binary(), map()) ::
          {:ok, CustomerUser.t()} | {:error, :invalid_token} | {:error, Ecto.Changeset.t()}
  def reset_password(plaintext, attrs) when is_binary(plaintext) do
    hash = CustomerUserToken.hash(plaintext)

    read(fn ->
      case Repo.one(
             from t in CustomerUserToken,
               where: t.token == ^hash and t.context == "reset_password",
               preload: [:customer_user],
               limit: 1
           ) do
        nil -> {:error, :invalid_token}
        %CustomerUserToken{} = token -> maybe_reset_password(token, attrs)
      end
    end)
  end

  def reset_password(_plaintext, _attrs), do: {:error, :invalid_token}

  ## Account self-service

  @doc "Updates the customer's own name and phone."
  @spec update_profile(CustomerUser.t(), map()) ::
          {:ok, CustomerUser.t()} | {:error, Ecto.Changeset.t()}
  def update_profile(%CustomerUser{} = customer_user, attrs) do
    read(fn -> customer_user |> CustomerUser.profile_changeset(attrs) |> Repo.update() end)
  end

  @doc "Changes the customer's password."
  @spec update_password(CustomerUser.t(), map()) ::
          {:ok, CustomerUser.t()} | {:error, Ecto.Changeset.t()}
  def update_password(%CustomerUser{} = customer_user, attrs) do
    read(fn -> customer_user |> CustomerUser.password_changeset(attrs) |> Repo.update() end)
  end

  @doc """
  Changes the customer's email and starts re-confirmation.

  Clears `confirmed_at`, creates a confirmation token sent to the new address,
  and returns the updated user plus the plaintext token.
  """
  @spec change_email(CustomerUser.t(), map()) ::
          {:ok, %{customer_user: CustomerUser.t(), confirmation_token: binary()}}
          | {:error, Ecto.Changeset.t()}
  def change_email(%CustomerUser{} = customer_user, attrs) do
    result =
      read(fn ->
        Multi.new()
        |> Multi.update(:customer_user, CustomerUser.email_changeset(customer_user, attrs))
        |> Multi.run(:confirmation_token, fn _repo, %{customer_user: user} ->
          {plaintext, changeset} =
            CustomerUserToken.build(user, "change_email", sent_to: user.email)

          {:ok, _} = Repo.insert(changeset)
          {:ok, plaintext}
        end)
        |> Repo.transaction()
      end)

    case result do
      {:ok, changes} ->
        Notifier.deliver_email_change_instructions(
          changes.customer_user,
          changes.customer_user.email,
          changes.confirmation_token
        )

        {:ok, Map.take(changes, [:customer_user, :confirmation_token])}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "The customer's notification preferences (defaults until WP-05 is merged)."
  @spec notification_preferences(CustomerUser.t()) :: map()
  def notification_preferences(%CustomerUser{} = customer_user),
    do: Preferences.get(customer_user)

  @doc "Updates the customer's notification preferences."
  @spec update_notification_preferences(CustomerUser.t(), map()) :: {:ok, map()}
  def update_notification_preferences(%CustomerUser{} = customer_user, attrs),
    do: Preferences.update(customer_user, attrs)

  ## Admin (owner/admin) customer management

  @doc "Lists/searches the tenant's customers. `term` matches name, email, or phone."
  @spec list_customers(binary() | nil) :: [CustomerUser.t()]
  def list_customers(term \\ nil), do: read(fn -> Repo.all(customer_query(term)) end)

  @doc "Paginates the tenant's customer search. Returns `%{data: [...], next_cursor: ...}`."
  @spec page_customers(binary() | nil, map() | keyword()) ::
          %{data: [CustomerUser.t()], next_cursor: binary() | nil}
  def page_customers(term \\ nil, params \\ %{}) do
    read(fn ->
      {rows, cursor} = Pagination.paginate(customer_query(term), params)
      %{data: rows, next_cursor: cursor}
    end)
  end

  @doc "Admin edit of a customer's contact details. Audited."
  @spec admin_update_customer(CustomerActor.t(), binary(), map()) ::
          {:ok, CustomerUser.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def admin_update_customer(actor, id, attrs) do
    update_with_audit(actor, id, "customer.updated", attrs)
  end

  @doc "Deactivates a customer (blocks login, retains data) and revokes sessions. Audited."
  @spec deactivate_customer(CustomerActor.t(), binary()) ::
          {:ok, CustomerUser.t()} | {:error, :not_found}
  def deactivate_customer(actor, id), do: set_active(actor, id, false, "customer.deactivated")

  @doc "Reactivates a customer. Audited."
  @spec reactivate_customer(CustomerActor.t(), binary()) ::
          {:ok, CustomerUser.t()} | {:error, :not_found}
  def reactivate_customer(actor, id), do: set_active(actor, id, true, "customer.reactivated")

  @doc "Triggers a password-reset email for a customer. Audited."
  @spec trigger_password_reset(CustomerActor.t(), binary()) :: :ok | {:error, :not_found}
  def trigger_password_reset(actor, id) do
    read(fn ->
      case Repo.get(CustomerUser, id) do
        nil ->
          {:error, :not_found}

        %CustomerUser{} = user ->
          {plaintext, changeset} = CustomerUserToken.build(user, "reset_password")
          {:ok, _} = Repo.insert(changeset)
          {:ok, _} = Audit.record(actor, "customer.password_reset_requested", user, %{})
          {:ok, {user, plaintext}}
      end
    end)
    |> case do
      {:ok, {user, plaintext}} ->
        Notifier.deliver_reset_password_instructions(user, plaintext)
        :ok

      {:error, :not_found} ->
        {:error, :not_found}

      _ ->
        :ok
    end
  end

  ## Households

  @doc "Fetches a household by id, raising if absent for the tenant in context."
  @spec get_household!(binary()) :: Household.t()
  def get_household!(id), do: read(fn -> Repo.get!(Household, id) end)

  @doc "Fetches a household by id, or `nil`."
  @spec get_household(binary()) :: Household.t() | nil
  def get_household(id), do: read(fn -> Repo.get(Household, id) end)

  @doc "The household a customer user belongs to in the tenant in context, or `nil`."
  @spec household_for_user(CustomerUser.t() | binary()) :: Household.t() | nil
  def household_for_user(%CustomerUser{id: id}), do: household_for_user(id)

  def household_for_user(customer_user_id) when is_binary(customer_user_id) do
    read(fn ->
      Repo.one(
        from m in HouseholdMember,
          join: h in Household,
          on: h.id == m.household_id,
          where: m.customer_user_id == ^customer_user_id,
          select: h,
          limit: 1
      )
    end)
  end

  @doc "Fetches a household member by id, or `nil`."
  @spec get_member(binary()) :: HouseholdMember.t() | nil
  def get_member(id), do: read(fn -> Repo.get(HouseholdMember, id) end)

  @doc "The household membership for a customer user, or `nil`."
  @spec get_membership_for_user(binary()) :: HouseholdMember.t() | nil
  def get_membership_for_user(customer_user_id) when is_binary(customer_user_id) do
    read(fn ->
      Repo.one(
        from m in HouseholdMember,
          where: m.customer_user_id == ^customer_user_id,
          limit: 1
      )
    end)
  end

  @doc "Lists a household's members with their customer users preloaded."
  @spec list_household_members(binary()) :: [HouseholdMember.t()]
  def list_household_members(household_id) do
    read(fn -> Repo.all(member_query(household_id)) end)
  end

  @doc "Fetches a household with members (and their users) preloaded."
  @spec household_detail(binary()) :: Household.t() | nil
  def household_detail(id) do
    read(fn ->
      case Repo.get(Household, id) do
        nil -> nil
        household -> Repo.preload(household, members: :customer_user)
      end
    end)
  end

  @doc "Lists/searches the tenant's households by member name or email."
  @spec list_households(binary() | nil) :: [Household.t()]
  def list_households(term \\ nil), do: read(fn -> Repo.all(household_query(term)) end)

  @doc "Paginates the tenant's household search. Returns `%{data: [...], next_cursor: ...}`."
  @spec page_households(binary() | nil, map() | keyword()) ::
          %{data: [Household.t()], next_cursor: binary() | nil}
  def page_households(term \\ nil, params \\ %{}) do
    read(fn ->
      {rows, cursor} = Pagination.paginate(household_query(term), params)
      %{data: rows, next_cursor: cursor}
    end)
  end

  @doc "The emails of every member of a household (used by WP-05 notifications)."
  @spec list_manager_emails(binary()) :: [binary()]
  def list_manager_emails(household_id) do
    read(fn ->
      Repo.all(
        from m in HouseholdMember,
          join: u in CustomerUser,
          on: u.id == m.customer_user_id,
          where: m.household_id == ^household_id,
          select: u.email
      )
    end)
  end

  ## Invitations

  @doc """
  Invites another adult (by email + relationship) to co-manage the actor's
  household. Creates a 7-day, single-use token and publishes
  `household.member_invited`.
  """
  @spec invite_member(CustomerActor.t(), map()) ::
          {:ok, %{invite: HouseholdInvite.t(), token: binary()}}
          | {:error, :forbidden | :already_member | :invalid_email | Ecto.Changeset.t()}
  def invite_member(%CustomerActor{} = actor, attrs) do
    attrs = stringify(attrs)
    email = attrs["email"]

    read(fn ->
      cond do
        is_nil(email) or email == "" ->
          {:error, :invalid_email}

        member_by_email?(actor.household_id, email) ->
          {:error, :already_member}

        true ->
          do_invite_member(actor, attrs)
      end
    end)
  end

  @doc "Lists a household's pending (unaccepted, unexpired) invites."
  @spec list_pending_invites(binary()) :: [HouseholdInvite.t()]
  def list_pending_invites(household_id) do
    now = now()

    read(fn ->
      Repo.all(
        from i in HouseholdInvite,
          where:
            i.household_id == ^household_id and is_nil(i.accepted_at) and i.expires_at > ^now,
          order_by: [desc: i.inserted_at]
      )
    end)
  end

  @doc "Fetches a pending invite by its plaintext token for the tenant in context."
  @spec get_invite_by_token(binary()) :: HouseholdInvite.t() | nil
  def get_invite_by_token(token) when is_binary(token) do
    hash = CustomerUserToken.hash(token)

    read(fn ->
      Repo.one(
        from i in HouseholdInvite,
          where: i.token_hash == ^hash and is_nil(i.accepted_at),
          limit: 1
      )
    end)
  end

  @doc """
  Accepts a household invitation.

  `opts[:customer_user]` is the logged-in user, when there is one. Otherwise the
  invite email is trusted: an existing account at this tenant joins, or a new
  pre-confirmed account is created from `params`.

  Fails with `{:error, :already_has_household}` when the account already manages
  another household (one household per customer user in MVP).
  """
  @spec accept_invite(binary(), map(), keyword()) ::
          {:ok,
           %{
             customer_user: CustomerUser.t(),
             household: Household.t(),
             member: HouseholdMember.t()
           }}
          | {:error,
             :invalid_invite
             | :expired_invite
             | :already_member
             | :already_has_household
             | Ecto.Changeset.t()}
  def accept_invite(token, params, opts \\ []) do
    hash = CustomerUserToken.hash(token)
    read(fn -> accept_invite_tx(hash, params, opts) end)
  end

  ## Membership changes

  @doc "Removes a manager from the actor's household. Primary members only."
  @spec remove_member(CustomerActor.t(), binary()) ::
          {:ok, HouseholdMember.t()} | {:error, :forbidden | :not_found}
  def remove_member(%CustomerActor{} = actor, member_id) do
    read(fn ->
      with {:ok, target} <- fetch_member(member_id),
           :ok <- authorize_remove(actor, target) do
        Repo.delete(target)
      end
    end)
  end

  @doc "The actor leaves their household. A primary member must transfer first."
  @spec leave_household(CustomerActor.t()) ::
          {:ok, HouseholdMember.t()} | {:error, :forbidden | :not_found}
  def leave_household(%CustomerActor{customer_user_id: customer_user_id}) do
    read(fn ->
      case Repo.one(
             from m in HouseholdMember, where: m.customer_user_id == ^customer_user_id, limit: 1
           ) do
        nil -> {:error, :not_found}
        %HouseholdMember{role: :primary} -> {:error, :forbidden}
        %HouseholdMember{} = member -> Repo.delete(member)
      end
    end)
  end

  @doc "Transfers the primary role to another member of the actor's household."
  @spec transfer_primary(CustomerActor.t(), binary()) ::
          {:ok, HouseholdMember.t()} | {:error, :forbidden | :not_found}
  def transfer_primary(%CustomerActor{} = actor, member_id) do
    read(fn ->
      with {:ok, target} <- fetch_member(member_id),
           :ok <- authorize_transfer(actor, target) do
        do_transfer_primary(actor, target)
      end
    end)
  end

  ## Private: identity helpers

  defp check_password(%CustomerUser{} = user, password) do
    if CustomerUser.valid_password?(user, password) do
      if CustomerUser.active?(user), do: {:ok, user}, else: {:error, :deactivated}
    else
      {:error, :invalid_credentials}
    end
  end

  defp invalid_credentials(password) do
    # Run a hash anyway to keep timing comparable for unknown emails.
    _ = Password.verify(password, "pbkdf2_sha256$1$AA==$AA==")
    {:error, :invalid_credentials}
  end

  defp session_user(%CustomerUserToken{customer_user: %CustomerUser{} = user} = token) do
    cond do
      CustomerUserToken.expired?(token) -> :error
      not CustomerUser.active?(user) -> :error
      true -> {:ok, user}
    end
  end

  defp session_user(_token), do: :error

  defp confirm_found_token(%CustomerUserToken{} = token) do
    if CustomerUserToken.expired?(token) do
      {:error, :invalid_token}
    else
      {:ok, customer_user} =
        token.customer_user |> CustomerUser.confirm_changeset() |> Repo.update()

      delete_context_tokens(customer_user.id, ["confirm", "change_email"])
      {:ok, customer_user}
    end
  end

  defp maybe_reset_password(%CustomerUserToken{} = token, attrs) do
    if CustomerUserToken.expired?(token) do
      {:error, :invalid_token}
    else
      apply_password_reset(token, attrs)
    end
  end

  defp apply_password_reset(token, attrs) do
    case token.customer_user |> CustomerUser.password_changeset(attrs) |> Repo.update() do
      {:ok, customer_user} ->
        delete_context_tokens(customer_user.id, ["reset_password"])
        {:ok, customer_user}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  ## Private: admin helpers

  defp update_with_audit(actor, id, action, attrs) do
    read(fn ->
      case Repo.get(CustomerUser, id) do
        nil -> {:error, :not_found}
        %CustomerUser{} = user -> persist_update_with_audit(actor, user, action, attrs)
      end
    end)
  end

  defp persist_update_with_audit(actor, user, action, attrs) do
    Multi.new()
    |> Multi.update(:customer_user, CustomerUser.profile_changeset(user, attrs))
    |> Multi.run(:audit, fn _repo, %{customer_user: updated} ->
      Audit.record(actor, action, updated, %{})
    end)
    |> Repo.transaction()
    |> case do
      {:ok, changes} -> {:ok, changes.customer_user}
      {:error, _step, reason, _changes} -> {:error, reason}
    end
  end

  defp set_active(actor, id, active, action) do
    read(fn ->
      case Repo.get(CustomerUser, id) do
        nil -> {:error, :not_found}
        %CustomerUser{} = user -> persist_active(actor, user, active, action)
      end
    end)
  end

  defp persist_active(actor, user, active, action) do
    Multi.new()
    |> Multi.update(:customer_user, CustomerUser.activation_changeset(user, active))
    |> Multi.run(:revoke_sessions, fn _repo, %{customer_user: updated} ->
      unless active, do: delete_context_tokens(updated.id, ["session"])
      {:ok, :ok}
    end)
    |> Multi.run(:audit, fn _repo, %{customer_user: updated} ->
      Audit.record(actor, action, updated, %{active: active})
    end)
    |> Repo.transaction()
    |> case do
      {:ok, changes} -> {:ok, changes.customer_user}
      {:error, _step, reason, _changes} -> {:error, reason}
    end
  end

  ## Private: household/invite helpers

  defp do_invite_member(%CustomerActor{} = actor, attrs) do
    tenant_id = TenantContext.get_tenant_id()
    plaintext = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
    expires_at = DateTime.add(now(), HouseholdInvite.validity_days(), :day)

    changeset =
      HouseholdInvite.changeset(%HouseholdInvite{}, %{
        tenant_id: tenant_id,
        household_id: actor.household_id,
        email: attrs["email"],
        relationship: attrs["relationship"],
        token_hash: CustomerUserToken.hash(plaintext),
        invited_by: actor.customer_user_id,
        expires_at: expires_at
      })

    with {:ok, invite} <- Repo.insert(changeset),
         {:ok, _} <-
           Events.publish("household.member_invited", %{
             tenant_id: tenant_id,
             household_id: actor.household_id,
             invite_id: invite.id,
             email: invite.email
           }) do
      Notifier.deliver_household_invite(invite, plaintext, TenantContext.get_tenant())
      {:ok, %{invite: invite, token: plaintext}}
    end
  end

  defp accept_invite_tx(hash, params, opts) do
    case Repo.one(
           from i in HouseholdInvite,
             where: i.token_hash == ^hash and is_nil(i.accepted_at),
             limit: 1
         ) do
      nil -> {:error, :invalid_invite}
      %HouseholdInvite{} = invite -> accept_found_invite(invite, params, opts)
    end
  end

  defp accept_found_invite(invite, params, opts) do
    if HouseholdInvite.expired?(invite) do
      {:error, :expired_invite}
    else
      do_accept_invite(invite, params, opts)
    end
  end

  defp do_accept_invite(invite, params, opts) do
    with {:ok, user} <- resolve_invite_user(invite, params, opts),
         :ok <- guard_membership(invite, user) do
      accept_and_join(invite, user)
    end
  end

  defp accept_and_join(invite, user) do
    Multi.new()
    |> Multi.insert(:member, fn _changes ->
      HouseholdMember.changeset(%HouseholdMember{}, %{
        tenant_id: invite.tenant_id,
        household_id: invite.household_id,
        customer_user_id: user.id,
        role: :manager,
        relationship: invite.relationship
      })
    end)
    |> Multi.update(:invite, HouseholdInvite.changeset(invite, %{accepted_at: now()}))
    |> Multi.run(:event, fn _repo, %{member: member} ->
      Events.publish("household.member_joined", %{
        tenant_id: invite.tenant_id,
        household_id: invite.household_id,
        customer_user_id: user.id,
        member_id: member.id
      })
    end)
    |> Repo.transaction()
    |> case do
      {:ok, changes} ->
        {:ok,
         %{
           customer_user: user,
           household: Repo.get(Household, invite.household_id),
           invite: changes.invite,
           member: changes.member
         }}

      {:error, _step, reason, _changes} ->
        {:error, reason}
    end
  end

  defp resolve_invite_user(invite, params, opts) do
    case opts[:customer_user] do
      %CustomerUser{} = user ->
        {:ok, user}

      nil ->
        case Repo.get_by(CustomerUser, email: invite.email) do
          %CustomerUser{} = user -> {:ok, user}
          nil -> register_invited_user(invite, params)
        end
    end
  end

  defp register_invited_user(invite, params) do
    attrs =
      params
      |> stringify()
      |> Map.put("email", invite.email)

    changeset =
      CustomerUser.registration_changeset(%CustomerUser{tenant_id: invite.tenant_id}, attrs)

    case Repo.insert(changeset) do
      {:ok, user} ->
        {:ok, _} = user |> CustomerUser.confirm_changeset() |> Repo.update()
        {:ok, %{user | confirmed_at: now()}}

      {:error, changeset} ->
        case Repo.get_by(CustomerUser, email: invite.email) do
          %CustomerUser{} = user -> {:ok, user}
          nil -> {:error, changeset}
        end
    end
  end

  defp guard_membership(invite, user) do
    case get_membership_for_user(user.id) do
      nil ->
        :ok

      %HouseholdMember{household_id: household_id} ->
        if household_id == invite.household_id do
          {:error, :already_member}
        else
          {:error, :already_has_household}
        end
    end
  end

  defp fetch_member(member_id) do
    case Repo.get(HouseholdMember, member_id) do
      nil -> {:error, :not_found}
      %HouseholdMember{} = member -> {:ok, member}
    end
  end

  defp authorize_remove(%CustomerActor{} = actor, %HouseholdMember{} = target) do
    cond do
      target.household_id != actor.household_id -> {:error, :forbidden}
      not actor_primary?(actor) -> {:error, :forbidden}
      target.role == :primary -> {:error, :forbidden}
      target.customer_user_id == actor.customer_user_id -> {:error, :forbidden}
      true -> :ok
    end
  end

  defp authorize_transfer(%CustomerActor{} = actor, %HouseholdMember{} = target) do
    cond do
      target.household_id != actor.household_id -> {:error, :forbidden}
      target.customer_user_id == actor.customer_user_id -> {:error, :forbidden}
      not actor_primary?(actor) -> {:error, :forbidden}
      true -> :ok
    end
  end

  defp do_transfer_primary(actor, target) do
    current =
      Repo.one(
        from m in HouseholdMember,
          where: m.customer_user_id == ^actor.customer_user_id,
          limit: 1
      )

    Multi.new()
    |> Multi.update(:demoted, HouseholdMember.changeset(current, %{role: :manager}))
    |> Multi.update(:promoted, HouseholdMember.changeset(target, %{role: :primary}))
    |> Multi.run(:audit, fn _repo, %{promoted: promoted} ->
      Audit.record(actor, "household.primary_transferred", promoted, %{})
    end)
    |> Repo.transaction()
    |> case do
      {:ok, changes} -> {:ok, changes.promoted}
      {:error, _step, reason, _changes} -> {:error, reason}
    end
  end

  defp actor_primary?(%CustomerActor{customer_user_id: customer_user_id}) do
    case get_membership_for_user(customer_user_id) do
      %HouseholdMember{role: :primary} -> true
      _ -> false
    end
  end

  defp member_by_email?(household_id, email) do
    Repo.exists?(
      from m in HouseholdMember,
        join: u in CustomerUser,
        on: u.id == m.customer_user_id,
        where: m.household_id == ^household_id and u.email == ^email
    )
  end

  defp member_query(household_id) do
    from(m in HouseholdMember,
      where: m.household_id == ^household_id,
      order_by: [asc: m.role, asc: m.inserted_at],
      preload: [:customer_user]
    )
  end

  ## Private: search

  defp customer_query(nil),
    do: from(u in CustomerUser, order_by: [asc: u.last_name, asc: u.first_name])

  defp customer_query(""), do: customer_query(nil)

  defp customer_query(term) when is_binary(term) do
    like = "%" <> String.trim(term) <> "%"

    from(u in CustomerUser,
      where:
        ilike(u.first_name, ^like) or ilike(u.last_name, ^like) or ilike(u.email, ^like) or
          like(u.phone, ^like),
      order_by: [asc: u.last_name, asc: u.first_name]
    )
  end

  defp household_query(nil), do: from(h in Household, order_by: [desc: h.inserted_at])

  defp household_query(term) when is_binary(term) do
    trimmed = String.trim(term)

    if trimmed == "" do
      household_query(nil)
    else
      like = "%" <> trimmed <> "%"

      from(h in Household,
        left_join: m in HouseholdMember,
        on: m.household_id == h.id,
        left_join: u in CustomerUser,
        on: u.id == m.customer_user_id,
        where: ilike(h.name, ^like) or ilike(u.email, ^like) or ilike(u.last_name, ^like),
        distinct: true,
        order_by: [desc: h.inserted_at]
      )
    end
  end

  defp household_name(%CustomerUser{last_name: last_name})
       when is_binary(last_name) and last_name != "",
       do: "#{last_name} Household"

  defp household_name(_user), do: "Household"

  ## Private: plumbing

  defp delete_context_tokens(customer_user_id, contexts) do
    Repo.delete_all(
      from t in CustomerUserToken,
        where: t.customer_user_id == ^customer_user_id and t.context in ^contexts
    )
  end

  defp multi_tx(multi) do
    # `Repo.with_tenant_tx/1`'s `Ecto.Multi` clause is currently unusable (its
    # internal `:__set_tenant__` step returns `:ok` instead of `{:ok, _}`); see
    # docs/rfcs/20260928-core-tenant-tx-multi.md. Run the multi in a nested
    # transaction that already has the tenant GUC set.
    case Repo.with_tenant_tx(fn -> Repo.transaction(multi) end) do
      {:ok, {:ok, changes}} -> {:ok, changes}
      {:ok, {:error, _step, %Ecto.Changeset{} = changeset, _changes}} -> {:error, changeset}
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

  defp stringify(attrs) when is_list(attrs), do: attrs |> Enum.into(%{}) |> stringify()

  defp stringify(attrs) when is_map(attrs) do
    Map.new(attrs, fn {key, value} -> {to_string(key), value} end)
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:microsecond)
end
