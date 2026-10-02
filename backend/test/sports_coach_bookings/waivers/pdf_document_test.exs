defmodule SportsCoachBookings.Waivers.PdfDocumentTest do
  use ExUnit.Case, async: true

  alias SportsCoachBookings.Waivers.PdfDocument

  defp data(body) do
    %{
      tenant_name: "Acme Soccer",
      template_name: "General Waiver",
      version: 3,
      body_markdown: body,
      player_name: "Sam Reyes",
      signature: %{
        id: "11111111-2222-3333-4444-555555555555",
        signer_name_typed: "Dana Reyes",
        signer_relationship: "Parent",
        consent_checkbox: true,
        signed_at: ~U[2026-09-30 12:00:00Z],
        ip: nil,
        user_agent: "Mozilla/5.0 (Test)",
        content_sha256: String.duplicate("ab", 32)
      }
    }
  end

  defp pages(pdf), do: length(Regex.scan(~r{/Type /Page\b(?!s)}, pdf))

  test "produces a PDF containing the header, body, and signature record" do
    pdf =
      PdfDocument.build(data("# Release\n\nI **agree** to the terms.\n\n- one\n- two"),
        compress: false
      )

    assert "%PDF-" <> _ = pdf

    for text <- ["Acme Soccer", "General Waiver", "Version 3", "Release", "I agree to the terms."] do
      assert pdf =~ text
    end

    for text <- [
          "Signature record",
          "Sam Reyes",
          "Dana Reyes",
          "Parent",
          "2026-09-30 12:00:00 UTC",
          String.duplicate("ab", 32)
        ] do
      assert pdf =~ text
    end

    refute pdf =~ "**"
  end

  test "long bodies paginate and the signature record still lands at the end" do
    body = Enum.map_join(1..120, "\n\n", &("Paragraph #{&1}. " <> String.duplicate("word ", 60)))
    pdf = PdfDocument.build(data(body), compress: false)

    assert pages(pdf) > 3
    assert pdf =~ "Paragraph 120."
    assert pdf =~ "Signature record"
  end

  test "characters outside Latin-1 (emoji, CJK) do not break rendering" do
    pdf = PdfDocument.build(data("Smart “quotes” — and 😀 and 漢字 and café"), compress: false)

    assert "%PDF-" <> _ = pdf
    # Helvetica/WinAnsi stores é as the single byte 0xE9; the emoji/CJK become "?".
    assert pdf =~ "caf" <> <<0xE9>>
    assert pdf =~ "and ? and ??"
  end

  test "an empty body still renders the signature record" do
    assert PdfDocument.build(data(""), compress: false) =~ "Signature record"
  end
end
