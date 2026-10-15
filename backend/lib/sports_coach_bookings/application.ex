defmodule SportsCoachBookings.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        SportsCoachBookingsWeb.Telemetry,
        SportsCoachBookings.Ops.ErrorReporter,
        SportsCoachBookings.Repo,
        SportsCoachBookings.Players.Vault,
        SportsCoachBookings.RateLimiter,
        {DNSCluster,
         query: Application.get_env(:sports_coach_bookings, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: SportsCoachBookings.PubSub},
        {Oban, Application.fetch_env!(:sports_coach_bookings, Oban)},
        # Start a worker by calling: SportsCoachBookings.Worker.start_link(arg)
        # {SportsCoachBookings.Worker, arg},
        # Start to serve requests, typically the last entry
        SportsCoachBookingsWeb.Endpoint
      ]
      |> maybe_add_pdf_renderer()

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: SportsCoachBookings.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp maybe_add_pdf_renderer(children) do
    browser_renderer = SportsCoachBookings.Waivers.PdfRenderer.Browser

    if Application.get_env(:sports_coach_bookings, :waiver_pdf_renderer) == browser_renderer do
      List.insert_at(
        children,
        -1,
        {ChromicPDF, Application.get_env(:sports_coach_bookings, ChromicPDF, [])}
      )
    else
      children
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    SportsCoachBookingsWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
