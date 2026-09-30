defmodule SportsCoachBookings.Notifications.Broadcasts.MarkdownTest do
  use ExUnit.Case, async: true

  alias SportsCoachBookings.Notifications.Broadcasts.Markdown

  test "renders headings, paragraphs, and inline markup" do
    html = Markdown.to_html("# Title\n\nA **bold** and *italic* word with `code`.")

    assert html =~ "<h1>Title</h1>"
    assert html =~ "<strong>bold</strong>"
    assert html =~ "<em>italic</em>"
    assert html =~ "<code>code</code>"
  end

  test "renders unordered and ordered lists" do
    html = Markdown.to_html("- one\n- two\n\n1. first\n2. second")

    assert html =~ "<ul><li>one</li><li>two</li></ul>"
    assert html =~ "<ol><li>first</li><li>second</li></ol>"
  end

  test "renders block quotes and horizontal rules" do
    html = Markdown.to_html("> quoted\n\n---")

    assert html =~ "<blockquote><p>quoted</p></blockquote>"
    assert html =~ "<hr />"
  end

  test "never emits raw HTML" do
    html = Markdown.to_html("<script>alert('x')</script>")

    refute html =~ "<script>"
    assert html =~ "&lt;script&gt;"
  end

  test "renders safe links only" do
    html = Markdown.to_html("[ok](https://example.com) [bad](javascript:alert(1))")

    assert html =~ ~s(<a href="https://example.com">ok</a>)
    refute html =~ "javascript:"
  end

  test "renders fenced code with escaped content" do
    html = Markdown.to_html("```\n<script>\n```")

    assert html =~ "<pre><code>"
    assert html =~ "&lt;script&gt;"
    refute html =~ "<script>"
  end
end
