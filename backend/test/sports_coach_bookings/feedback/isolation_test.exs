defmodule SportsCoachBookings.Feedback.IsolationTest do
  use SportsCoachBookings.DataCase, async: true

  alias SportsCoachBookings.Feedback.Revision
  alias SportsCoachBookings.Feedback.SessionFeedback
  alias SportsCoachBookings.Feedback.SkillTag

  test "session_feedback is tenant-isolated" do
    assert_tenant_isolated(SessionFeedback, :session_feedback)
  end

  test "feedback_revisions are tenant-isolated" do
    assert_tenant_isolated(Revision, :feedback_revision)
  end

  test "feedback_skill_tags are tenant-isolated" do
    assert_tenant_isolated(SkillTag, :feedback_skill_tag)
  end
end
