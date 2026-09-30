defmodule SportsCoachBookings.Notifications.Templates do
  @moduledoc """
  Config-driven registry of email templates.

  Templates are registered in
  `config :sports_coach_bookings, :notification_templates` as a map of key
  (atom or string) to a module implementing
  `SportsCoachBookings.Notifications.Template`. Contexts add their own entries,
  so there are no merge conflicts on a shared module.
  """

  @doc "The module registered under `key`, or `nil`."
  @spec get(atom() | String.t()) :: module() | nil
  def get(key), do: Map.get(registry(), normalize(key))

  @doc "Whether `key` is registered."
  @spec registered?(atom() | String.t()) :: boolean()
  def registered?(key), do: not is_nil(get(key))

  @doc "All registered `{key, module}` pairs keyed by normalised string key."
  @spec all() :: %{optional(String.t()) => module()}
  def all, do: registry()

  @doc "The registered template keys, sorted."
  @spec keys() :: [String.t()]
  def keys, do: registry() |> Map.keys() |> Enum.sort()

  @doc "The required assigns declared by the template registered under `key`."
  @spec required_assigns(atom() | String.t()) :: [atom()]
  def required_assigns(key) do
    case get(key) do
      nil -> []
      module -> module.required_assigns()
    end
  end

  @doc """
  Validates that `assigns` contains every required assign for `key`.

  Returns `:ok` or `{:error, {:missing_assigns, [atom()]}}`.
  """
  @spec validate_assigns(atom() | String.t(), map()) ::
          :ok | {:error, {:missing_assigns, [atom()]}}
  def validate_assigns(key, assigns) when is_map(assigns) do
    missing =
      key
      |> required_assigns()
      |> Enum.reject(&Map.has_key?(assigns, &1))

    if missing == [], do: :ok, else: {:error, {:missing_assigns, missing}}
  end

  @doc """
  Fake assigns for previewing `key`: the template's own samples merged over
  sensible defaults for its required assigns.
  """
  @spec sample_assigns(atom() | String.t()) :: map()
  def sample_assigns(key) do
    case get(key) do
      nil ->
        %{}

      module ->
        defaults = Map.new(module.required_assigns(), &{&1, default_assign(&1)})
        Map.merge(defaults, safe_sample(module))
    end
  end

  @doc "Whether the template registered under `key` is exempt from suppression."
  @spec exempt_from_suppression?(atom() | String.t()) :: boolean()
  def exempt_from_suppression?(key) do
    case get(key) do
      nil -> false
      module -> exempt?(module)
    end
  end

  defp exempt?(module) do
    Code.ensure_loaded?(module) and function_exported?(module, :exempt_from_suppression?, 0) and
      module.exempt_from_suppression?()
  end

  defp safe_sample(module) do
    if Code.ensure_loaded?(module) and function_exported?(module, :sample_assigns, 0),
      do: module.sample_assigns(),
      else: %{}
  end

  defp default_assign(:token), do: "sample-token"
  defp default_assign(:email), do: "recipient@example.com"
  defp default_assign(:previous_email), do: "old@example.com"
  defp default_assign(:url), do: "https://localhost/sample"
  defp default_assign(:action_url), do: "https://localhost/sample"
  defp default_assign(:role), do: "coach"
  defp default_assign(:relationship), do: "parent"
  defp default_assign(:tenant), do: "Sample Coaching"
  defp default_assign(:amount), do: "$25.00"
  defp default_assign(:booking_reference), do: "A-000123"
  defp default_assign(key), do: "Sample #{key}"

  defp normalize(key) when is_atom(key), do: Atom.to_string(key)
  defp normalize(key) when is_binary(key), do: key

  defp registry do
    :sports_coach_bookings
    |> Application.get_env(:notification_templates, %{})
    |> Map.new(fn {k, v} -> {normalize(k), v} end)
  end
end
