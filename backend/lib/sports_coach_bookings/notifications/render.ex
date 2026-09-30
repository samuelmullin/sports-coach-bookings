defmodule SportsCoachBookings.Notifications.Render do
  @moduledoc """
  Minimal EEx rendering for notification templates.

  Templates and the layout are developer-authored EEx strings; the assigns map is
  bound as `assigns`, so templates read values with `assigns[:key]`. Output is
  HTML/text (never user-supplied templates), so no escaping engine is used.
  """

  @doc "Renders an EEx template string with `assigns` bound."
  @spec eex(String.t(), map()) :: String.t()
  # Templates are developer-authored modules in the `:notification_templates`
  # registry; no user-supplied template string is ever evaluated here. Accepted
  # false positive for Sobelow's RCE.EEx check.
  # sobelow_skip ["RCE.EEx"]
  def eex(template, assigns) when is_binary(template) and is_map(assigns) do
    EEx.eval_string(template, assigns: assigns)
  end
end
