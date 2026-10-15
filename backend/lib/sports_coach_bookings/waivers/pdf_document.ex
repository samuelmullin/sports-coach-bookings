defmodule SportsCoachBookings.Waivers.PdfDocument do
  @moduledoc """
  Lays out a signed waiver as a PDF (US-Letter, Helvetica) and returns the bytes.

  Pure: takes the already-loaded data and does no I/O besides the in-process PDF
  builder. The waiver body is the exact markdown that was signed, rendered as
  plain text with light structure (headings, bullets, paragraphs); inline
  markdown markers are stripped. The signature record that follows is the
  evidence block: who signed, for whom, when, from where, and the content hash
  that ties the document to the signed version.
  """

  alias SportsCoachBookings.Waivers.IP

  @page_size :letter
  @margin 54
  @body_size 10
  @leading 14

  @type data :: %{
          required(:tenant_name) => String.t(),
          required(:template_name) => String.t(),
          required(:version) => integer(),
          required(:body_markdown) => String.t(),
          required(:player_name) => String.t(),
          required(:signature) => map()
        }

  @doc """
  Builds the PDF for `data` and returns the binary.

  Options: `:compress` (default `true`); tests disable it to inspect the text.
  """
  @spec build(data(), keyword()) :: binary()
  def build(data, opts \\ []) do
    {:ok, pdf} = Pdf.new(size: @page_size, compress: Keyword.get(opts, :compress, true))

    try do
      pdf
      |> Pdf.set_info(
        title: "#{clean(data.template_name)} (v#{data.version})",
        producer: "SportsCoachBookings"
      )
      |> Pdf.set_font("Helvetica", @body_size)
      |> Pdf.set_text_leading(@leading)
      |> start_at_top()
      |> header(data)
      |> body(data.body_markdown)
      |> signature_block(data)

      Pdf.export(pdf)
    after
      Pdf.cleanup(pdf)
    end
  end

  ## Layout

  defp header(pdf, data) do
    pdf
    |> block({clean(data.tenant_name), [font_size: 9, color: :gray]}, 0)
    |> block({clean(data.template_name), [font_size: 18, bold: true, leading: 24]}, 6)
    |> block({"Version #{data.version}", [font_size: 9, color: :gray]}, 12)
  end

  defp body(pdf, markdown) do
    markdown
    |> String.replace("\r\n", "\n")
    |> String.split("\n")
    |> Enum.reduce(pdf, &markdown_line/2)
  end

  defp markdown_line(line, pdf) do
    case String.trim(line) do
      "" ->
        Pdf.move_down(pdf, 6)

      "#" <> _ = heading ->
        text = heading |> String.trim_leading("#") |> String.trim() |> strip_inline()
        pdf |> Pdf.move_down(6) |> block({text, [font_size: 12, bold: true, leading: 18]}, 2)

      "- " <> item ->
        block(pdf, "•  " <> strip_inline(item), 0)

      "* " <> item ->
        block(pdf, "•  " <> strip_inline(item), 0)

      text ->
        block(pdf, strip_inline(text), 0)
    end
  end

  defp signature_block(pdf, %{signature: signature} = data) do
    pdf
    |> Pdf.move_down(18)
    |> block({"Signature record", [font_size: 12, bold: true, leading: 18]}, 4)
    |> fields([
      {"Signed for", data.player_name},
      {"Typed signature", signature.signer_name_typed},
      {"Relationship", signature.signer_relationship || "—"},
      {"Consent given", if(signature.consent_checkbox, do: "Yes", else: "No")},
      {"Signed at (UTC)", format_time(signature.signed_at)},
      {"IP address", ip(signature.ip)},
      {"User agent", signature.user_agent},
      {"Content SHA-256", signature.content_sha256},
      {"Signature ID", signature.id}
    ])
  end

  defp fields(pdf, rows) do
    Enum.reduce(rows, pdf, fn {label, value}, acc ->
      block(acc, [{label <> ": ", [bold: true]}, clean(to_string(value))], 0)
    end)
  end

  ## Pagination

  # Draws `text` (a binary or annotated text) as a wrapped paragraph at the cursor,
  # continuing on new pages until it is fully drawn, then leaves `gap` points.
  defp block(pdf, text, gap) do
    %{width: width, height: height} = Pdf.size(pdf)
    box_width = width - 2 * @margin
    text = normalize_text(text)

    pdf
    |> draw(text, box_width, height)
    |> Pdf.move_down(gap)
  end

  defp draw(pdf, text, box_width, page_height) do
    y = Pdf.cursor(pdf)
    available = y - @margin

    if available < @leading * 2 do
      pdf |> new_page() |> draw(text, box_width, page_height)
    else
      case Pdf.text_wrap(pdf, {@margin, y}, {box_width, available}, text) do
        {pdf, :complete} ->
          # Advance the cursor past what was drawn.
          Pdf.set_cursor(pdf, Pdf.cursor(pdf))

        {pdf, remaining} ->
          pdf |> new_page() |> draw(remaining, box_width, page_height)
      end
    end
  end

  defp new_page(pdf) do
    pdf |> Pdf.add_page(@page_size) |> start_at_top()
  end

  defp start_at_top(pdf) do
    %{height: height} = Pdf.size(pdf)
    Pdf.set_cursor(pdf, height - @margin)
  end

  ## Text helpers

  defp normalize_text({text, opts}) when is_binary(text), do: [{clean(text), opts}]
  defp normalize_text(text) when is_binary(text), do: clean(text)

  defp normalize_text(list) when is_list(list) do
    Enum.map(list, fn
      {text, opts} -> {clean(text), opts}
      text -> clean(text)
    end)
  end

  defp strip_inline(text) do
    text
    |> String.replace(~r/\[([^\]]+)\]\(([^)]+)\)/, "\\1 (\\2)")
    |> String.replace(~r/(\*\*|__|\*|_|`)/, "")
  end

  @replacements %{
    "‘" => "'",
    "’" => "'",
    "“" => "\"",
    "”" => "\"",
    "–" => "-",
    "—" => "-",
    "…" => "...",
    " " => " ",
    "\t" => "    "
  }

  # Standard-14 Helvetica only covers Latin-1-ish text. Map the common typographic
  # characters to ASCII and replace anything else outside Latin-1 so a stray emoji
  # cannot make rendering fail.
  defp clean(text) do
    text
    |> String.replace(Map.keys(@replacements), &Map.fetch!(@replacements, &1))
    |> String.to_charlist()
    |> Enum.map(fn
      cp when cp in 32..126 or cp in 161..255 or cp == 0x2022 -> cp
      _ -> ??
    end)
    |> to_string_latin1()
  end

  # `•` (U+2022) is in WinAnsi at 0x95 but not in Latin-1, and the library's
  # encoder takes UTF-8, so only Latin-1 + bullet survive; everything is
  # re-encoded as UTF-8 and the library converts to WinAnsi.
  defp to_string_latin1(codepoints), do: List.to_string(codepoints)

  defp format_time(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S UTC")
  defp format_time(_), do: "—"

  defp ip(nil), do: "—"
  defp ip(ip), do: IP.format(ip)
end
