defmodule SportsCoachBookings.Waivers.PdfHtml do
  @moduledoc "Builds escaped, branded HTML for the Chrome-backed waiver renderer."

  alias Phoenix.HTML
  alias SportsCoachBookings.Waivers.IP

  @font_families %{
    "inter" => ~s("Inter", "Noto Sans", sans-serif),
    "roboto" => ~s("Roboto", "Noto Sans", sans-serif),
    "lato" => ~s("Lato", "Noto Sans", sans-serif),
    "open_sans" => ~s("Open Sans", "Noto Sans", sans-serif),
    "montserrat" => ~s("Montserrat", "Noto Sans", sans-serif),
    "source_sans_pro" => ~s("Source Sans Pro", "Noto Sans", sans-serif),
    "system" => ~s("Noto Sans", sans-serif)
  }

  @doc "Returns a complete HTML document; all supplied text is escaped."
  @spec build(map()) :: binary()
  def build(data) do
    branding = data.branding
    font = Map.get(@font_families, branding.font_family, @font_families["system"])

    """
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8">
        <style>
          @page { size: Letter; margin: 0.65in; }
          * { box-sizing: border-box; }
          body { color: #{safe_color(branding.text_color, "#111827")}; font: 10pt/1.5 #{font}; margin: 0; text-rendering: geometricPrecision; }
          header { align-items: center; border-bottom: 3px solid #{safe_color(branding.primary_color, "#1d4ed8")}; display: flex; gap: 16px; margin-bottom: 24px; padding-bottom: 14px; }
          header img { max-height: 46px; max-width: 180px; object-fit: contain; }
          h1 { font-size: 20pt; line-height: 1.2; margin: 2px 0; }
          h2 { font-size: 13pt; break-after: avoid; margin: 18px 0 6px; }
          p { margin: 0 0 9px; orphans: 3; widows: 3; }
          ul { margin: 0 0 10px; padding-left: 22px; }
          li { margin-bottom: 3px; }
          .tenant, .version { color: #64748b; font-size: 9pt; }
          .signature { border-top: 1px solid #cbd5e1; break-inside: avoid; margin-top: 28px; padding-top: 14px; }
          .signature dl { display: grid; grid-template-columns: 130px 1fr; margin: 0; }
          .signature dt { font-weight: 700; padding: 3px 8px 3px 0; }
          .signature dd { margin: 0; overflow-wrap: anywhere; padding: 3px 0; }
        </style>
      </head>
      <body>
        <header>
          #{logo(branding.logo_url, data.tenant_name)}
          <div>
            <div class="tenant">#{escape(data.tenant_name)}</div>
            <h1>#{escape(data.template_name)}</h1>
            <div class="version">Version #{escape(data.version)}</div>
          </div>
        </header>
        <main>
          #{markdown(data.body_markdown)}
          #{signature(data)}
        </main>
      </body>
    </html>
    """
  end

  defp markdown(markdown) do
    markdown
    |> String.replace("\r\n", "\n")
    |> String.split("\n")
    |> Enum.reduce({[], []}, fn line, {blocks, list} ->
      case String.trim(line) do
        "" ->
          {flush_list(blocks, list), []}

        "#" <> _ = heading ->
          blocks = flush_list(blocks, list)
          text = heading |> String.trim_leading("#") |> String.trim() |> strip_inline()
          {["<h2>#{escape(text)}</h2>" | blocks], []}

        "- " <> item ->
          {blocks, [strip_inline(item) | list]}

        "* " <> item ->
          {blocks, [strip_inline(item) | list]}

        text ->
          blocks = flush_list(blocks, list)
          {["<p>#{escape(strip_inline(text))}</p>" | blocks], []}
      end
    end)
    |> then(fn {blocks, list} -> flush_list(blocks, list) end)
    |> Enum.reverse()
    |> Enum.join("\n")
  end

  defp flush_list(blocks, []), do: blocks

  defp flush_list(blocks, list) do
    items = list |> Enum.reverse() |> Enum.map_join(&"<li>#{escape(&1)}</li>")
    ["<ul>#{items}</ul>" | blocks]
  end

  defp signature(%{signature: record} = data) do
    rows = [
      {"Signed for", data.player_name},
      {"Typed signature", record.signer_name_typed},
      {"Relationship", record.signer_relationship || "—"},
      {"Consent given", if(record.consent_checkbox, do: "Yes", else: "No")},
      {"Signed at (UTC)", format_time(record.signed_at)},
      {"IP address", if(record.ip, do: IP.format(record.ip), else: "—")},
      {"User agent", record.user_agent},
      {"Content SHA-256", record.content_sha256},
      {"Signature ID", record.id}
    ]

    fields =
      Enum.map_join(rows, fn {label, value} -> "<dt>#{label}</dt><dd>#{escape(value)}</dd>" end)

    ~s(<section class="signature"><h2>Signature record</h2><dl>#{fields}</dl></section>)
  end

  defp logo(nil, _tenant_name), do: ""
  defp logo("", _tenant_name), do: ""

  defp logo(url, tenant_name),
    do: ~s(<img src="#{escape(url)}" alt="#{escape(tenant_name)} logo">)

  defp strip_inline(text) do
    text
    |> String.replace(~r/\[([^\]]+)\]\(([^)]+)\)/, "\\1 (\\2)")
    |> String.replace(~r/(\*\*|__|\*|_|`)/, "")
  end

  defp safe_color(value, fallback) when is_binary(value) do
    if Regex.match?(~r/^#[0-9a-fA-F]{6}$/, value), do: value, else: fallback
  end

  defp safe_color(_, fallback), do: fallback
  defp escape(value), do: value |> to_string() |> HTML.html_escape() |> HTML.safe_to_string()
  defp format_time(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S UTC")
  defp format_time(_), do: "—"
end
