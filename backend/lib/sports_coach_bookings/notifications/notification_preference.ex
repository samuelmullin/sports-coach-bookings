defmodule SportsCoachBookings.Notifications.NotificationPreference do
  @moduledoc """
  Per customer-user / staff-user notification preferences. Tenant-owned (RLS).

  The subject is polymorphic (`subject_type` + `subject_id`) so this table does
  not depend on other contexts' schemas. `marketing_opt_in` defaults to `false`
  (CASL requires express consent); `operational` and `transactional` are always
  on.
  """

  use SportsCoachBookings.Core.TenantSchema

  @type t :: %__MODULE__{}

  @subject_types [:customer_user, :staff_user]

  schema "notification_preferences" do
    field :tenant_id, :binary_id
    field :subject_type, Ecto.Enum, values: @subject_types
    field :subject_id, :binary_id
    field :marketing_opt_in, :boolean, default: false
    field :operational, :boolean, default: true
    field :transactional, :boolean, default: true

    timestamps()
  end

  @doc false
  def changeset(preference, attrs) do
    preference
    |> Ecto.Changeset.cast(attrs, [
      :tenant_id,
      :subject_type,
      :subject_id,
      :marketing_opt_in,
      :operational,
      :transactional
    ])
    |> Ecto.Changeset.validate_required([:tenant_id, :subject_type, :subject_id])
    |> Ecto.Changeset.unique_constraint([:tenant_id, :subject_type, :subject_id])
  end

  @doc "The subject types a preference can be stored for."
  @spec subject_types() :: [atom()]
  def subject_types, do: @subject_types
end
