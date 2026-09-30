defmodule SportsCoachBookings.Repo.Migrations.FeedbackCreateSkillTags do
  use Ecto.Migration

  import SportsCoachBookings.Core.Migration

  def change do
    tenant_table :feedback_skill_tags do
      add :name, :string, null: false
      add :slug, :string, null: false
      add :position, :integer, null: false, default: 0
      add :active, :boolean, null: false, default: true
    end

    create unique_index(:feedback_skill_tags, [:tenant_id, :slug])
    create index(:feedback_skill_tags, [:tenant_id, :position])
  end
end
