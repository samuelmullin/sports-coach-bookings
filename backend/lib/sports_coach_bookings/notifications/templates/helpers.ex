defmodule SportsCoachBookings.Notifications.Templates.Helpers do
  @moduledoc """
  Shared helpers callable from template EEx (fully qualified) to build links.
  """

  @doc "Base URL used for links in transactional email."
  @spec app_url() :: String.t()
  def app_url do
    Application.get_env(
      :sports_coach_bookings,
      :notifications_app_url,
      "https://sportscoachbookings.com"
    )
  end

  @doc "Builds an absolute token link from a path and token."
  @spec link(String.t(), String.t()) :: String.t()
  def link(path, token) do
    "#{app_url()}#{path}?token=#{URI.encode_www_form(to_string(token))}"
  end

  @doc "Renders a simple email button linking to `url`."
  @spec button(String.t(), String.t()) :: String.t()
  def button(label, url) do
    ~s(<p style="margin:24px 0;"><a href="#{url}" style="background-color:#1d4ed8;color:#ffffff;text-decoration:none;padding:12px 20px;border-radius:6px;display:inline-block;font-weight:bold;">#{label}</a></p>)
  end
end
