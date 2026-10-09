defmodule SportsCoachBookings.Waivers.PdfHtmlTest do
  use ExUnit.Case, async: true

  alias SportsCoachBookings.Waivers.PdfHtml

  test "preserves Unicode, applies branding, and escapes supplied content" do
    html =
      PdfHtml.build(%{
        tenant_name: "Académie <Nord>",
        template_name: "同意書 & Release",
        version: 2,
        body_markdown: "# Bienvenue 😀\n\n- café\n- 漢字\n\n<script>alert(1)</script>",
        player_name: "Zoë 王",
        branding: %{
          logo_url: "https://assets.example/logo.png?x=1&y=2",
          primary_color: "#123456",
          text_color: "#222222",
          font_family: "lato"
        },
        signature: %{
          id: "signature-id",
          signer_name_typed: "Renée 王",
          signer_relationship: "Parent",
          consent_checkbox: true,
          signed_at: ~U[2026-10-02 12:00:00Z],
          ip: nil,
          user_agent: "Browser <unsafe>",
          content_sha256: "abc123"
        }
      })

    assert html =~ "Académie &lt;Nord&gt;"
    assert html =~ "同意書 &amp; Release"
    assert html =~ "Bienvenue 😀"
    assert html =~ "Zoë 王"
    assert html =~ "#123456"
    assert html =~ ~s(font: 10pt/1.5 "Lato")
    assert html =~ "logo.png?x=1&amp;y=2"
    assert html =~ "&lt;script&gt;alert(1)&lt;/script&gt;"
    refute html =~ "<script>alert(1)</script>"
  end
end
