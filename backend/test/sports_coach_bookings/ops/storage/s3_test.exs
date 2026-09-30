defmodule SportsCoachBookings.Ops.Storage.S3Test do
  # Not async: one test sets global app env for the storage module.
  use ExUnit.Case, async: false

  alias SportsCoachBookings.Tenancy.Storage.S3

  @config [
    bucket: "scb-uploads",
    region: "ca-central-1",
    access_key_id: "AKIAIOSFODNN7EXAMPLE",
    secret_access_key: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
  ]

  test "presigned PUT URL has the AWS SigV4 shape" do
    now = ~U[2026-09-28 12:00:00Z]
    url = S3.presigned_url(:put, "tenant/logo.png", @config, 900, now)

    assert url =~ "https://scb-uploads.s3.ca-central-1.amazonaws.com/tenant/logo.png?"
    assert url =~ "X-Amz-Algorithm=AWS4-HMAC-SHA256"

    assert url =~
             "X-Amz-Credential=AKIAIOSFODNN7EXAMPLE%2F20260928%2Fca-central-1%2Fs3%2Faws4_request"

    assert url =~ "X-Amz-Date=20260928T120000Z"
    assert url =~ "X-Amz-Expires=900"
    assert url =~ "X-Amz-SignedHeaders=host"
    assert url =~ ~r/X-Amz-Signature=[0-9a-f]{64}\z/
  end

  test "presign_put returns the storage behaviour's map shape" do
    Application.put_env(:sports_coach_bookings, S3, @config)
    on_exit(fn -> Application.delete_env(:sports_coach_bookings, S3) end)

    tenant_id = "11111111-1111-1111-1111-111111111111"
    upload = %{content_type: "image/png", byte_size: 100, filename: "logo.png"}

    assert {:ok, presigned} = S3.presign_put(upload, tenant_id)
    assert presigned.method == "PUT"
    assert presigned.key == "#{tenant_id}/logo.png"
    assert presigned.headers == %{"Content-Type" => "image/png"}
    assert %DateTime{} = presigned.expires_at
    assert presigned.upload_url =~ "X-Amz-Signature="
  end

  test "build_key sanitises and tenant-partitions filenames" do
    assert S3.build_key(%{filename: "my logo!.png"}, "t1") == "t1/my-logo-.png"
    assert S3.build_key(%{filename: nil}, "t1") == "t1/asset"
  end

  test "public_url honours a configured public base URL" do
    Application.put_env(
      :sports_coach_bookings,
      S3,
      @config ++ [public_base_url: "https://cdn.example.com/assets"]
    )

    on_exit(fn -> Application.delete_env(:sports_coach_bookings, S3) end)

    assert S3.public_url("t1/logo.png") == "https://cdn.example.com/assets/t1/logo.png"
  end
end
