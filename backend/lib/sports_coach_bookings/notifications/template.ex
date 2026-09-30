defmodule SportsCoachBookings.Notifications.Template do
  @moduledoc """
  Behaviour implemented by every registered email template.

  Template modules are registered in
  `config :sports_coach_bookings, :notification_templates` (a map of key to
  module) so each context can add its own templates without editing ours.

  `html/1` returns the **body** markup; the engine wraps it in the shared
  responsive `SportsCoachBookings.Notifications.Layout`. `text/1` is the plain
  text alternative and is always sent.
  """

  @callback subject(assigns :: map()) :: String.t()
  @callback html(assigns :: map()) :: String.t()
  @callback text(assigns :: map()) :: String.t()
  @callback required_assigns() :: [atom()]
  @callback sample_assigns() :: map()
  @callback exempt_from_suppression?() :: boolean()

  @optional_callbacks sample_assigns: 0, exempt_from_suppression?: 0

  @doc """
  Declares a template from EEx strings.

      defmodule MyApp.Templates.Welcome do
        use SportsCoachBookings.Notifications.Template,
          required: [:name],
          subject: "Welcome, <%= assigns[:name] %>",
          html: "<h1>Hello <%= assigns[:name] %></h1>",
          text: "Hello <%= assigns[:name] %>"
      end
  """
  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      @behaviour SportsCoachBookings.Notifications.Template

      import SportsCoachBookings.Notifications.Render

      @template_subject Keyword.fetch!(opts, :subject)
      @template_html Keyword.fetch!(opts, :html)
      @template_text Keyword.fetch!(opts, :text)
      @template_required Keyword.get(opts, :required, [])
      @template_sample Keyword.get(opts, :sample, %{})
      @template_exempt Keyword.get(opts, :exempt, false)

      @impl SportsCoachBookings.Notifications.Template
      def required_assigns, do: @template_required

      @impl SportsCoachBookings.Notifications.Template
      def sample_assigns, do: @template_sample

      @impl SportsCoachBookings.Notifications.Template
      def exempt_from_suppression?, do: @template_exempt

      @impl SportsCoachBookings.Notifications.Template
      def subject(assigns), do: eex(@template_subject, assigns)

      @impl SportsCoachBookings.Notifications.Template
      def html(assigns), do: eex(@template_html, assigns)

      @impl SportsCoachBookings.Notifications.Template
      def text(assigns), do: eex(@template_text, assigns)
    end
  end
end
