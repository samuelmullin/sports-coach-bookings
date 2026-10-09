defmodule SportsCoachBookings.Waivers.PdfStore.Local do
  @moduledoc """
  Filesystem `SportsCoachBookings.Waivers.PdfStore` for dev and test.

  Files live under `config :sports_coach_bookings, #{inspect(__MODULE__)}, root: path`
  (default `tmp/waiver_pdfs`, git-ignored). Keys are validated so they cannot
  escape the root.
  """

  @behaviour SportsCoachBookings.Waivers.PdfStore

  @impl true
  # sobelow_skip ["Traversal.FileModule"] — path/1 expands and rejects keys outside root.
  def put(key, pdf) do
    with {:ok, path} <- path(key),
         :ok <- File.mkdir_p(Path.dirname(path)) do
      File.write(path, pdf)
    end
  end

  @impl true
  # sobelow_skip ["Traversal.FileModule"] — path/1 expands and rejects keys outside root.
  def get(key) do
    with {:ok, path} <- path(key) do
      case File.read(path) do
        {:ok, pdf} -> {:ok, pdf}
        {:error, :enoent} -> {:error, :not_found}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @impl true
  # sobelow_skip ["Traversal.FileModule"] — path/1 expands and rejects keys outside root.
  def delete(key) do
    with {:ok, path} <- path(key) do
      case File.rm(path) do
        :ok -> :ok
        {:error, :enoent} -> :ok
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp path(key) when is_binary(key) do
    root = Path.expand(root())
    path = Path.expand(key, root)

    if String.starts_with?(path, root <> "/"), do: {:ok, path}, else: {:error, :invalid_key}
  end

  defp root do
    :sports_coach_bookings
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:root, "tmp/waiver_pdfs")
  end
end
