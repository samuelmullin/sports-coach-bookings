defmodule SportsCoachBookingsWeb.Portal.WebsiteMetaController do
  @moduledoc "Tenant-specific robots and sitemap documents for hosted websites."

  use SportsCoachBookingsWeb, :controller

  alias SportsCoachBookings.Websites

  @paths ~w(/ /schedule /packages /shop /about /coaches /testimonials /gallery /sponsors /faq /contact)

  @doc "GET /robots.txt"
  def robots(conn, _params) do
    body =
      if Websites.published_site() do
        "User-agent: *\nAllow: /\nSitemap: #{origin(conn)}/sitemap.xml\n"
      else
        "User-agent: *\nDisallow: /\n"
      end

    conn |> put_resp_content_type("text/plain") |> send_resp(:ok, body)
  end

  @doc "GET /sitemap.xml"
  def sitemap(conn, _params) do
    if Websites.published_site() do
      urls = Enum.map_join(@paths, "\n", &sitemap_url(origin(conn), &1))

      body =
        ~s|<?xml version="1.0" encoding="UTF-8"?>\n| <>
          ~s|<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n| <>
          urls <> "\n</urlset>\n"

      conn |> put_resp_content_type("application/xml") |> send_resp(:ok, body)
    else
      send_resp(conn, :not_found, "Not found")
    end
  end

  defp sitemap_url(origin, path), do: "  <url><loc>#{xml(origin <> path)}</loc></url>"

  defp origin(conn) do
    scheme = conn.scheme |> Atom.to_string()

    default_port? =
      (scheme == "https" and conn.port == 443) or (scheme == "http" and conn.port == 80)

    port = if default_port?, do: "", else: ":#{conn.port}"
    "#{scheme}://#{conn.host}#{port}"
  end

  defp xml(value) do
    value
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&apos;")
  end
end
