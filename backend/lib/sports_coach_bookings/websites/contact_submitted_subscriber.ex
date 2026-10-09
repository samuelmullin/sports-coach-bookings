defmodule SportsCoachBookings.Websites.ContactSubmittedSubscriber do
  @moduledoc "Notifies the tenant contact when a hosted-site inquiry is submitted."

  @behaviour SportsCoachBookings.Events.Subscriber

  alias SportsCoachBookings.Notifications
  alias SportsCoachBookings.Tenancy
  alias SportsCoachBookings.Websites

  @impl true
  def handle_event("website.contact_submitted", %{
        "submission_id" => submission_id,
        "tenant_id" => tenant_id
      }) do
    submission = Websites.get_contact_submission(submission_id)
    tenant = Tenancy.get_tenant(tenant_id)

    case {submission, tenant && tenant.contact_email} do
      {%{} = inquiry, email} when is_binary(email) and email != "" ->
        Notifications.deliver(
          :website_contact_submitted,
          [%{type: :email, id: nil, email: email}],
          %{
            name: inquiry.name,
            email: inquiry.email,
            phone: inquiry.phone || "Not provided",
            subject: inquiry.subject || "Website inquiry",
            message: inquiry.message
          },
          category: :operational,
          idempotency_key: "website-contact-#{submission_id}"
        )

      _missing ->
        :ok
    end
  end

  def handle_event(_name, _payload), do: :ok
end
