defmodule SportsCoachBookings.Notifications.Broadcasts.Markdown do
  @moduledoc """
  A small, dependency-free Markdown renderer for broadcast bodies.

  Only a safe subset is supported and **raw HTML is never allowed**: the input is
  entity-escaped before any markup is generated. Supported blocks are headings,
  paragraphs, unordered and ordered lists, block quotes, horizontal rules, and
  fenced code. Supported inline markup is bold, italic, inline code, and links to
  `http(s)://`, `mailto:`, or root-relative URLs.
  """

  @link_regex ~r/\[([^\]]*)\]\(([^)\s]+)\)/

  @doc "Renders `markdown` to a safe HTML fragment."
  @spec to_html(binary() | nil) :: String.t()
  def to_html(nil), do: ""

  def to_html(markdown) when is_binary(markdown) do
    markdown
    |> String.replace("\r\n", "\n")
    |> String.split("\n")
    |> parse([])
    |> Enum.join("\n")
  end

  ## Block parsing

  defp parse([], acc), do: Enum.reverse(acc)

  defp parse([line | rest], acc) do
    cond do
      fence?(line) ->
        parse_fence(rest, acc)

      hr?(line) ->
        parse(rest, ["<hr />" | acc])

      heading(line) != nil ->
        parse(rest, [heading(line) | acc])

      list_item(line) != nil ->
        parse_list(rest, list_item(line), [list_item_text(line)], acc)

      quote_line?(line) ->
        parse_quote(rest, [quote_text(line)], acc)

      blank?(line) ->
        parse(rest, acc)

      true ->
        parse_paragraph(rest, [line], acc)
    end
  end

  defp parse_fence(lines, acc) do
    {code_lines, rest} = Enum.split_while(lines, &(not fence?(&1)))

    rest =
      case rest do
        [_closing | tail] -> tail
        [] -> []
      end

    html = "<pre><code>" <> escape(Enum.join(code_lines, "\n")) <> "</code></pre>"
    parse(rest, [html | acc])
  end

  defp parse_list([line | rest], kind, items, acc) do
    case list_item(line) do
      ^kind -> parse_list(rest, kind, [list_item_text(line) | items], acc)
      _other -> parse([line | rest], [render_list(kind, items) | acc])
    end
  end

  defp parse_list([], kind, items, acc), do: Enum.reverse([render_list(kind, items) | acc])

  defp parse_quote([line | rest], lines, acc) do
    if quote_line?(line) do
      parse_quote(rest, [quote_text(line) | lines], acc)
    else
      parse([line | rest], [render_quote(lines) | acc])
    end
  end

  defp parse_quote([], lines, acc), do: Enum.reverse([render_quote(lines) | acc])

  defp parse_paragraph([line | rest], lines, acc) do
    cond do
      blank?(line) -> parse(rest, [render_paragraph(lines) | acc])
      block_start?(line) -> parse([line | rest], [render_paragraph(lines) | acc])
      true -> parse_paragraph(rest, [line | lines], acc)
    end
  end

  defp parse_paragraph([], lines, acc), do: Enum.reverse([render_paragraph(lines) | acc])

  defp block_start?(line) do
    fence?(line) or hr?(line) or heading(line) != nil or list_item(line) != nil or
      quote_line?(line)
  end

  ## Block renderers

  defp render_list(kind, items) do
    tag = if kind == :ol, do: "ol", else: "ul"

    body =
      items
      |> Enum.reverse()
      |> Enum.map_join("", &"<li>#{inline(&1)}</li>")

    "<#{tag}>#{body}</#{tag}>"
  end

  defp render_quote(lines) do
    inner = lines |> Enum.reverse() |> Enum.join(" ")
    "<blockquote><p>#{inline(inner)}</p></blockquote>"
  end

  defp render_paragraph(lines) do
    body = lines |> Enum.reverse() |> Enum.join(" ") |> inline()
    "<p>#{body}</p>"
  end

  ## Line predicates

  defp blank?(line), do: String.trim(line) == ""
  defp fence?(line), do: String.starts_with?(String.trim_leading(line), "```")

  defp hr?(line), do: Regex.match?(~r/^\s*([-*_])(\s*\1){2,}\s*$/, line)

  defp heading(line) do
    case Regex.run(~r/^\s{0,3}(\#{1,6})\s+(.*?)\s*#*\s*$/, line) do
      [_, hashes, text] ->
        level = byte_size(hashes)
        "<h#{level}>#{inline(text)}</h#{level}>"

      _ ->
        nil
    end
  end

  defp list_item(line) do
    cond do
      Regex.match?(~r/^\s*[-*+]\s+/, line) -> :ul
      Regex.match?(~r/^\s*\d+\.\s+/, line) -> :ol
      true -> nil
    end
  end

  defp list_item_text(line) do
    line
    |> String.trim_leading()
    |> String.replace(~r/^[-*+]\s+/, "")
    |> String.replace(~r/^\d+\.\s+/, "")
  end

  defp quote_line?(line), do: Regex.match?(~r/^\s*>/, line)

  defp quote_text(line) do
    line
    |> String.trim_leading()
    |> String.replace_prefix(">", "")
    |> String.trim_leading()
  end

  ## Inline rendering

  defp inline(text) do
    {text, codes} = text |> escape() |> extract_code()

    text =
      text
      |> bold()
      |> italic()
      |> link()

    restore_code(text, codes)
  end

  defp bold(text) do
    text
    |> then(&Regex.replace(~r/\*\*([^*]+)\*\*/, &1, "<strong>\\1</strong>"))
    |> then(&Regex.replace(~r/__([^_]+)__/, &1, "<strong>\\1</strong>"))
  end

  defp italic(text) do
    text
    |> then(&Regex.replace(~r/\*([^*]+)\*/, &1, "<em>\\1</em>"))
    |> then(&Regex.replace(~r/(?<!\w)_([^_]+)_(?!\w)/, &1, "<em>\\1</em>"))
  end

  defp extract_code(text) do
    Regex.scan(~r/`([^`]+)`/, text)
    |> Enum.reduce({text, []}, fn [_full, code], {acc, codes} ->
      token = "\x00CODE#{length(codes)}\x00"
      {String.replace(acc, "`#{code}`", token, global: false), codes ++ [{token, code}]}
    end)
  end

  defp restore_code(text, codes) do
    Enum.reduce(codes, text, fn {token, code}, acc ->
      String.replace(acc, token, "<code>#{code}</code>")
    end)
  end

  defp link(text) do
    Regex.replace(@link_regex, text, fn _full, label, url ->
      if safe_url?(url), do: ~s(<a href="#{url}">#{label}</a>), else: label
    end)
  end

  defp safe_url?(url) do
    String.starts_with?(url, ["https://", "http://", "mailto:", "/", "#"])
  end

  @doc false
  @spec escape(binary()) :: String.t()
  def escape(text) when is_binary(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&#39;")
  end
end
