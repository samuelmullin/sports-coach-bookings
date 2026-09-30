defmodule SportsCoachBookings.Repo.Migrations.NotificationsCreateNotificationPreferences do
  use Ecto.Migration

  import SportsCoachBookings.Core.Migration

  def change do
    # Per customer user / staff user preferences. `marketing_opt_in` defaults to
    # false (CASL express consent); operational and transactional are always on.
    # The subject is stored polymorphically (`subject_type` + `subject_id`) to
    # avoid two nullable cross-context FK columns.
    tenant_table :notification_preferences do
      add :subject_type, :string, null: false
      add :subject_id, :uuid, null: false
      add :marketing_opt_in, :boolean, null: false, default: false
      add :operational, :boolean, null: false, default: true
      add :transactional, :boolean, null: false, default: true
    end

    create unique_index(:notification_preferences, [:tenant_id, :subject_type, :subject_id])
  end
end
