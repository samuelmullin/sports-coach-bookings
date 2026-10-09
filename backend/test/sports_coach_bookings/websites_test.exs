defmodule SportsCoachBookings.WebsitesTest do
  use SportsCoachBookings.DataCase, async: false

  alias SportsCoachBookings.Core.StaffActor
  alias SportsCoachBookings.Notifications.Message
  alias SportsCoachBookings.Repo
  alias SportsCoachBookings.Websites
  alias SportsCoachBookings.Websites.ContactSubmittedSubscriber

  setup do
    tenant = insert(:tenant)
    put_tenant(tenant)

    actor =
      StaffActor.new(
        staff_user_id: Ecto.UUID.generate(),
        tenant_id: tenant.id,
        role: :owner
      )

    %{tenant: tenant, actor: actor}
  end

  test "drafts remain private until published", %{actor: actor} do
    assert Websites.published_site() == nil

    assert {:ok, draft} =
             Websites.update_draft(actor, %{
               "content" => %{"hero" => %{"title" => "Develop your game"}}
             })

    assert draft.draft_content["hero"]["title"] == "Develop your game"
    assert Websites.published_site() == nil

    assert {:ok, published} = Websites.publish(actor)
    assert published.published_at
    assert Websites.published_site().content["hero"]["title"] == "Develop your game"

    assert Enum.any?(Repo.all(Oban.Job), &(&1.args["name"] == "website.published"))
  end

  test "public asset keys receive URLs on published output", %{actor: actor, tenant: tenant} do
    assert {:ok, _site} =
             Websites.update_draft(actor, %{
               "content" => %{"hero" => %{"image_key" => "#{tenant.id}/hero.jpg"}}
             })

    assert {:ok, _site} = Websites.publish(actor)
    assert Websites.published_site().content["hero"]["image_url"] =~ "hero.jpg"
  end

  test "contact submissions validate, publish an event, and can be resolved", %{actor: actor} do
    assert {:error, changeset} =
             Websites.create_contact_submission(%{
               "name" => "Sam",
               "email" => "not-email",
               "message" => "short"
             })

    assert %{email: [_], message: [_]} = errors_on(changeset)

    assert {:ok, submission} =
             Websites.create_contact_submission(%{
               "name" => "Sam",
               "email" => "sam@example.test",
               "message" => "Can you help with a private training session?"
             })

    assert Enum.any?(Repo.all(Oban.Job), &(&1.args["name"] == "website.contact_submitted"))
    assert %{data: [listed]} = Websites.page_contact_submissions()
    assert listed.id == submission.id

    assert {:ok, resolved} =
             Websites.update_contact_submission(actor, submission.id, %{"status" => "resolved"})

    assert resolved.status == :resolved
    assert resolved.resolved_at
  end

  test "contact event notifies the tenant contact without exposing data in the job", %{
    tenant: tenant
  } do
    assert {:ok, submission} =
             Websites.create_contact_submission(%{
               "name" => "Sam",
               "email" => "sam@example.test",
               "subject" => "Private lessons",
               "message" => "Can you help with a private training session?"
             })

    assert {:ok, %{message: message}} =
             ContactSubmittedSubscriber.handle_event("website.contact_submitted", %{
               "submission_id" => submission.id,
               "tenant_id" => tenant.id
             })

    assert %Message{} = message
    assert message.template_key == "website_contact_submitted"
    assert message.assigns["subject"] == "Private lessons"
    refute inspect(Repo.all(Oban.Job)) =~ submission.message
  end
end
