defmodule SportsCoachBookings.Tenancy.StorageTest do
  use ExUnit.Case, async: true

  alias SportsCoachBookings.Tenancy.Storage
  alias SportsCoachBookings.Tenancy.Storage.Svg

  test "presigns a png with a deterministic key and public URL" do
    upload = %{"filename" => "Logo.PNG", "content_type" => "image/png", "byte_size" => 1_000}

    assert {:ok, first} = Storage.presign_put(upload, "tenant-1")
    assert {:ok, second} = Storage.presign_put(upload, "tenant-1")

    assert first.key == second.key
    assert first.key == "tenant-1/Logo.PNG"
    assert first.upload_url =~ first.key
    assert first.method == "PUT"
    assert first.headers["Content-Type"] == "image/png"
    assert Storage.public_url(first.key) =~ first.key
  end

  test "rejects unsupported content types, empty files, and oversized files" do
    base = %{"filename" => "x.png", "content_type" => "image/png", "byte_size" => 10}

    assert {:error, :unsupported_content_type} =
             Storage.presign_put(%{base | "content_type" => "image/gif"}, "t")

    assert {:error, :invalid_byte_size} =
             Storage.presign_put(%{base | "byte_size" => 0}, "t")

    assert {:error, :file_too_large} =
             Storage.presign_put(%{base | "byte_size" => Storage.max_bytes() + 1}, "t")
  end

  test "sanitises SVG uploads by rejecting active content" do
    assert {:error, :unsafe_svg} =
             Svg.sanitize(~s|<svg onload="alert(1)"><rect/></svg>|)

    assert {:error, :unsafe_svg} =
             Svg.sanitize(~s|<svg><script>alert(1)</script></svg>|)

    assert {:ok, _} = Svg.sanitize(~s(<svg><rect width="1" height="1"/></svg>))

    assert {:error, :unsafe_svg} =
             Storage.validate(%{
               "content_type" => "image/svg+xml",
               "byte_size" => 20,
               "content" => ~s|<svg onload="x()"/>|
             })

    assert {:ok, _} =
             Storage.validate(%{
               "content_type" => "image/svg+xml",
               "byte_size" => 20,
               "content" => ~s|<svg/>|
             })
  end
end
