defmodule SportsCoachBookings.Core.Pagination do
  @moduledoc """
  Cursor-based pagination helper.

  Endpoints accept `?cursor=…&limit=…` and return `%{data: [...], next_cursor: …}`.
  Cursors are opaque, URL-safe strings derived from the last row's
  `(inserted_at, id)` keyset tuple, ordered newest-first.
  """

  import Ecto.Query

  @default_limit 25
  @max_limit 100

  @doc "Parses and clamps a `limit` request param."
  @spec page_size(map() | keyword(), integer()) :: integer()
  def page_size(params, default \\ @default_limit) do
    params
    |> fetch(:limit)
    |> parse_limit(default)
  end

  @doc """
  Fetches one page of `query` (ordered by `inserted_at desc, id desc`).

  Returns `{rows, next_cursor}` where `next_cursor` is `nil` on the last page.
  """
  @spec paginate(Ecto.Queryable.t(), map() | keyword(), keyword()) ::
          {[struct()], String.t() | nil}
  def paginate(query, params, opts \\ []) do
    repo = Keyword.get(opts, :repo, SportsCoachBookings.Repo)
    limit = page_size(params)

    base =
      query
      |> order_by([r], desc: r.inserted_at, desc: r.id)
      |> limit(^limit)

    cursor = params |> fetch(:cursor) |> decode_cursor()

    base =
      case cursor do
        {timestamp, id} ->
          where(
            base,
            [r],
            r.inserted_at < ^timestamp or (r.inserted_at == ^timestamp and r.id < ^id)
          )

        nil ->
          base
      end

    rows = repo.all(base)
    next_cursor = if length(rows) == limit, do: encode_cursor(List.last(rows)), else: nil
    {rows, next_cursor}
  end

  @doc "Encodes a row's keyset into an opaque cursor string."
  @spec encode_cursor(struct()) :: String.t()
  def encode_cursor(%{inserted_at: timestamp, id: id}) do
    payload = %{"t" => DateTime.to_iso8601(timestamp), "id" => id}

    payload
    |> Jason.encode!()
    |> Base.url_encode64(padding: false)
  end

  @doc "Decodes a cursor string into `{timestamp, id}` or `nil`."
  @spec decode_cursor(String.t() | nil) :: {DateTime.t(), binary()} | nil
  def decode_cursor(nil), do: nil
  def decode_cursor(""), do: nil

  def decode_cursor(cursor) when is_binary(cursor) do
    with {:ok, json} <- Base.url_decode64(cursor, padding: false),
         {:ok, %{"t" => timestamp, "id" => id}} <- Jason.decode(json),
         {:ok, datetime, _} <- DateTime.from_iso8601(timestamp) do
      {datetime, id}
    else
      _ -> nil
    end
  end

  defp fetch(params, key) when is_map(params) do
    Map.get(params, to_string(key)) || Map.get(params, key)
  end

  defp fetch(params, key) when is_list(params), do: Keyword.get(params, key)

  defp parse_limit(nil, default), do: default
  defp parse_limit("", default), do: default

  defp parse_limit(value, default) do
    case Integer.parse(to_string(value)) do
      {n, ""} when n > 0 -> min(n, @max_limit)
      _ -> default
    end
  end
end
