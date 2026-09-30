defmodule SportsCoachBookings.Repo.Migrations.NotificationsCreateMessages do
  use Ecto.Migration

  import SportsCoachBookings.Core.Migration

  def change do
    # One row per `Notifications.deliver/4` call. Tenant-owned (RLS enabled and
    # forced). `idempotency_key` is unique per tenant; NULLs never collide, so a
    # plain unique index is equivalent to a partial one for our needs.
    tenant_table :messages do
      add :template_key, :string, null: false
      add :category, :string, null: false, default: "transactional"
      add :subject, :string
      add :idempotency_key, :string

      # Template assigns are stored so the worker (and an admin "resend") can
      # re-render the message without the original request. See the wp-05 RFC.
      add :assigns, :map, null: false, default: %{}
    end

    create unique_index(:messages, [:tenant_id, :idempotency_key])
    create index(:messages, [:tenant_id, :template_key])
  end
end
