defmodule SportsCoachBookingsWeb.Players.Helpers do
  @moduledoc false

  @doc """
  Extracts an attributes map from a request, accepting either a wrapped body
  (`%{"player" => %{...}}`) or a flat body. Drops routing/query params.
  """
  @spec body(map(), String.t()) :: map()
  def body(params, key) do
    case Map.get(params, key) do
      %{} = attrs -> attrs
      _ -> Map.drop(params, ["id", "player_id", "cursor", "limit", key])
    end
  end
end
