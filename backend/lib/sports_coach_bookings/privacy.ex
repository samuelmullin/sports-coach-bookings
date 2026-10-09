defmodule SportsCoachBookings.Privacy do
  @moduledoc """
  PIPEDA household data export and erasure.

  Orchestrates the owning contexts through their public APIs; this module never
  touches another context's schemas.

  ## Export

  `export_household/1` gathers everything held about the caller's household:
  accounts, players (profile, emergency contacts, authorized pickups, medical
  info, waiver signatures, shared coach feedback), bookings, credits, and
  orders. Medical reads and the export itself are audited. Coach-internal
  feedback is excluded: it is staff work product, not shared with the family.

  ## Erasure

  `erase_household/2` is irreversible and runs in one transaction:

  | Data | Treatment |
  |---|---|
  | Players, profiles, contacts, pickups, **medical info** | Deleted |
  | Coach feedback about the players | Deleted |
  | Carts, reservation holds | Deleted |
  | Customer accounts | Anonymized, deactivated, sessions/tokens revoked |
  | Household members, invites | Deleted; household name cleared |
  | Waiver signatures | Kept as acceptance evidence; name, IP, user agent, PDF reference scrubbed |
  | Delivery / broadcast-recipient emails | Scrubbed |
  | Orders, payments, refunds, credit ledger, bookings | Retained (financial/operational records; opaque ids only) |
  | Audit events | Retained (append-only) |

  Erasure is refused while the household has upcoming bookings or an order
  awaiting payment, and requires the primary member's password. Unused credits
  are forfeited.
  """

  alias SportsCoachBookings.Bookings
  alias SportsCoachBookings.Commerce
  alias SportsCoachBookings.Core.Audit
  alias SportsCoachBookings.Core.CustomerActor
  alias SportsCoachBookings.Credits
  alias SportsCoachBookings.Customers
  alias SportsCoachBookings.Customers.CustomerUser
  alias SportsCoachBookings.Events
  alias SportsCoachBookings.Feedback
  alias SportsCoachBookings.Notifications
  alias SportsCoachBookings.Players
  alias SportsCoachBookings.Repo
  alias SportsCoachBookings.Reservations
  alias SportsCoachBookings.Waivers

  @type blocker :: :upcoming_bookings | :pending_orders

  @doc "Assembles the household's data bundle. Audited."
  @spec export_household(CustomerActor.t()) :: {:ok, map()} | {:error, term()}
  def export_household(%CustomerActor{household_id: household_id} = actor) do
    Repo.with_tenant_tx(fn ->
      household = Customers.household_detail(household_id)

      players =
        household_id
        |> Players.list_for_household()
        |> Enum.map(&player_bundle(actor, &1))

      {:ok, _} =
        Audit.record(actor, "privacy.household_exported", household, %{
          player_count: length(players)
        })

      %{
        generated_at: DateTime.utc_now() |> DateTime.truncate(:second),
        household: household,
        players: players,
        bookings: Bookings.list_for_household(household_id, scope: :all),
        credit_lots: Credits.list_lots(household_id),
        credit_ledger: Credits.list_ledger(household_id),
        orders: Commerce.list_orders_for_household(household_id)
      }
    end)
  end

  defp player_bundle(actor, player) do
    {:ok, medical} = Players.read_medical_info(actor, player)

    %{
      player: player,
      profile: Players.get_profile(player.id),
      emergency_contacts: Players.list_emergency_contacts(player.id),
      authorized_pickups: Players.list_authorized_pickups(player.id),
      medical_info: medical,
      waiver_signatures: Waivers.list_signatures(player_id: player.id),
      shared_feedback: Feedback.shared_for_player(player.id)
    }
  end

  @doc """
  Irreversibly erases the caller's household. Returns a summary of what was
  removed. `password` is the primary member's current password.
  """
  @spec erase_household(CustomerActor.t(), binary() | nil) ::
          {:ok, map()}
          | {:error, :forbidden | :invalid_password | {:erasure_blocked, [blocker()]}}
  def erase_household(%CustomerActor{household_id: household_id} = actor, password) do
    with :ok <- require_primary(actor),
         :ok <- verify_password(actor, password),
         :ok <- check_blockers(household_id) do
      Repo.with_tenant_tx(fn -> do_erase(actor) end)
    end
  end

  defp do_erase(%CustomerActor{household_id: household_id} = actor) do
    household = Customers.get_household!(household_id)

    player_ids = Players.erase_household_players(household_id)
    feedback = Feedback.erase_for_players(player_ids)
    pdf_keys = Waivers.anonymize_signatures(player_ids)
    carts = Commerce.erase_household_carts(household_id)
    holds = Reservations.erase_household(household_id)
    %{user_ids: user_ids, emails: emails} = Customers.anonymize_household(household_id)
    scrubbed = Notifications.scrub_emails(emails)

    summary = %{
      players: length(player_ids),
      feedback: feedback,
      accounts: length(user_ids),
      carts: carts,
      reservations: holds,
      scrubbed_messages: scrubbed,
      waiver_pdfs: length(pdf_keys)
    }

    {:ok, _} = Audit.record(actor, "privacy.household_erased", household, summary)

    {:ok, _} =
      Events.publish("household.erased", %{
        household_id: household_id,
        tenant_id: household.tenant_id
      })

    summary
  end

  defp require_primary(%CustomerActor{customer_user_id: user_id, household_id: household_id}) do
    case Customers.get_membership_for_user(user_id) do
      %{role: :primary, household_id: ^household_id} -> :ok
      _ -> {:error, :forbidden}
    end
  end

  defp verify_password(%CustomerActor{customer_user_id: user_id}, password)
       when is_binary(password) do
    with %CustomerUser{} = user <- Customers.get_customer_user(user_id),
         true <- CustomerUser.valid_password?(user, password) do
      :ok
    else
      _ -> {:error, :invalid_password}
    end
  end

  defp verify_password(_actor, _password), do: {:error, :invalid_password}

  defp check_blockers(household_id) do
    blockers =
      Enum.filter([:upcoming_bookings, :pending_orders], &blocked?(&1, household_id))

    if blockers == [], do: :ok, else: {:error, {:erasure_blocked, blockers}}
  end

  # `:upcoming` is live (held/confirmed) bookings for sessions still ahead.
  defp blocked?(:upcoming_bookings, household_id),
    do: Bookings.list_for_household(household_id, scope: :upcoming) != []

  defp blocked?(:pending_orders, household_id), do: Commerce.pending_orders?(household_id)
end
