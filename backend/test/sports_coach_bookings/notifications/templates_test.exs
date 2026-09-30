defmodule SportsCoachBookings.Notifications.TemplatesTest do
  use ExUnit.Case, async: true

  alias SportsCoachBookings.Notifications.Templates

  test "the sample template is registered alongside the seam templates" do
    for key <- [
          :sample,
          :customer_confirm,
          :customer_reset_password,
          :customer_email_change,
          :household_invite,
          :staff_invite,
          :staff_confirm,
          :staff_reset_password
        ] do
      assert Templates.registered?(key), "expected #{key} to be registered"
      assert Templates.get(key)
    end

    assert Templates.get("sample") == Templates.get(:sample)
  end

  test "unknown keys are not registered" do
    refute Templates.registered?(:nope)
    assert Templates.get(:nope) == nil
    assert Templates.required_assigns(:nope) == []
  end

  test "required assigns are validated" do
    assert Templates.required_assigns(:sample) == [:name, :action_url]
    assert :ok = Templates.validate_assigns(:sample, %{name: "a", action_url: "b"})

    assert {:error, {:missing_assigns, [:action_url]}} =
             Templates.validate_assigns(:sample, %{name: "a"})
  end

  test "sample assigns cover every required assign" do
    assigns = Templates.sample_assigns(:sample)
    assert :ok = Templates.validate_assigns(:sample, assigns)
  end

  test "password-reset templates are exempt from suppression" do
    assert Templates.exempt_from_suppression?(:customer_reset_password)
    assert Templates.exempt_from_suppression?(:staff_reset_password)
    refute Templates.exempt_from_suppression?(:customer_confirm)
  end
end
