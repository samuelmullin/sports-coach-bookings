defmodule SportsCoachBookings.Security.UploadValidationTest do
  @moduledoc """
  WP-19 upload hardening: content-type allow-list, size cap, magic-byte
  sniffing, and SVG sanitisation-by-rejection.
  """

  use SportsCoachBookings.DataCase, async: true

  alias SportsCoachBookings.Tenancy.Storage
  alias SportsCoachBookings.Tenancy.Storage.Svg

  @png <<0x89, "PNG", 0x0D, 0x0A, 0x1A, 0x0A>>
  @jpeg <<0xFF, 0xD8, 0xFF, 0xE0>>

  test "accepts a well-formed png" do
    assert {:ok, _} =
             Storage.validate(%{
               "content_type" => "image/png",
               "byte_size" => byte_size(@png),
               "content" => @png
             })
  end

  test "rejects an unsupported content type" do
    assert {:error, :unsupported_content_type} =
             Storage.validate(%{"content_type" => "application/pdf", "byte_size" => 10})
  end

  test "rejects an oversize upload" do
    assert {:error, :file_too_large} =
             Storage.validate(%{
               "content_type" => "image/png",
               "byte_size" => Storage.max_bytes() + 1
             })
  end

  test "rejects a zero/negative byte size" do
    assert {:error, :invalid_byte_size} =
             Storage.validate(%{"content_type" => "image/png", "byte_size" => 0})
  end

  test "rejects bytes that do not match the declared type" do
    assert {:error, :content_type_mismatch} =
             Storage.validate(%{
               "content_type" => "image/png",
               "byte_size" => byte_size(@jpeg),
               "content" => @jpeg
             })
  end

  describe "SVG rejection" do
    test "rejects script, event handlers, and external references" do
      for body <- [
            ~s|<svg><script>alert(1)</script></svg>|,
            ~s|<svg onload="alert(1)"></svg>|,
            ~s|<svg><a xlink:href="https://evil.example">x</a></svg>|,
            ~s|<?xml version="1.0"?><!DOCTYPE svg [<!ENTITY x "y">]><svg/>|,
            ~s|<svg><foreignObject/></svg>|,
            ~s|<svg><animate attributeName="x"/></svg>|,
            ~s|<svg><style>@import url(https://evil.example/x.css);</style></svg>|
          ] do
        assert {:error, :unsafe_svg} = Svg.sanitize(body), "expected rejection: #{body}"
      end
    end

    test "accepts a simple safe svg" do
      assert {:ok, _} = Svg.sanitize(~s(<svg xmlns="http://www.w3.org/2000/svg"><rect/></svg>))
    end
  end
end
