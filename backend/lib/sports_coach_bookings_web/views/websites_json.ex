defmodule SportsCoachBookingsWeb.WebsitesJSON do
  @moduledoc "Serialises hosted websites and contact submissions."

  alias SportsCoachBookings.Websites
  alias SportsCoachBookings.Websites.ContactSubmission
  alias SportsCoachBookings.Websites.Site

  @doc "Serialises the staff website editor resource."
  @spec site(Site.t()) :: map()
  def site(site) do
    %{
      id: site.id,
      enabled: site.enabled,
      draft_content: site.draft_content,
      preview_content: Websites.preview_content(site.draft_content),
      published_content: site.published_content,
      published_at: datetime(site.published_at),
      updated_at: datetime(site.updated_at)
    }
  end

  @doc "Serialises a contact submission."
  @spec contact_submission(ContactSubmission.t()) :: map()
  def contact_submission(submission) do
    %{
      id: submission.id,
      name: submission.name,
      email: submission.email,
      phone: submission.phone,
      company: submission.company,
      subject: submission.subject,
      message: submission.message,
      status: submission.status,
      resolved_at: datetime(submission.resolved_at),
      inserted_at: datetime(submission.inserted_at)
    }
  end

  @doc "Serialises a paginated contact submission collection."
  @spec collection([ContactSubmission.t()], binary() | nil) :: map()
  def collection(rows, cursor),
    do: %{data: Enum.map(rows, &contact_submission/1), next_cursor: cursor}

  defp datetime(nil), do: nil
  defp datetime(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp datetime(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)
end
