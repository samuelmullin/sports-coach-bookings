defmodule SportsCoachBookings.Ops.Storage.S3IntegrationTest do
  use ExUnit.Case, async: false

  alias SportsCoachBookings.Tenancy.Storage.S3, as: Signer
  alias SportsCoachBookings.Waivers.PdfStore.S3, as: PdfStore

  @moduletag skip: System.get_env("S3_INTEGRATION") != "1"

  test "public presigned uploads and private waiver storage round-trip against S3" do
    previous = Application.get_env(:sports_coach_bookings, Signer)

    config = [
      bucket: System.fetch_env!("S3_BUCKET"),
      private_bucket: System.fetch_env!("S3_PRIVATE_BUCKET"),
      region: System.fetch_env!("S3_REGION"),
      access_key_id: System.fetch_env!("S3_ACCESS_KEY_ID"),
      secret_access_key: System.fetch_env!("S3_SECRET_ACCESS_KEY"),
      endpoint: System.fetch_env!("S3_ENDPOINT"),
      force_path_style: true
    ]

    Application.put_env(:sports_coach_bookings, Signer, config)
    suffix = System.unique_integer([:positive, :monotonic])
    public_key = "integration/public-#{suffix}.txt"
    private_key = "integration/private-#{suffix}.pdf"

    on_exit(fn ->
      request(config, :delete, public_key)
      PdfStore.delete(private_key)
      Application.put_env(:sports_coach_bookings, Signer, previous || [])
    end)

    assert {:ok, %{status: status}} =
             request(config, :put, public_key,
               body: "s3-public-round-trip",
               headers: [{"content-type", "text/plain"}]
             )

    assert status in 200..299

    assert {:ok, %{status: 200, body: "s3-public-round-trip"}} =
             request(config, :get, public_key)

    assert :ok = PdfStore.put(private_key, "%PDF-live-round-trip")
    assert {:ok, "%PDF-live-round-trip"} = PdfStore.get(private_key)
    assert :ok = PdfStore.delete(private_key)
    assert {:error, :not_found} = PdfStore.get(private_key)
  end

  defp request(config, method, key, opts \\ []) do
    url = Signer.presigned_url(method, key, config, 60, DateTime.utc_now())

    [method: method, url: url, retry: false, decode_body: false]
    |> Keyword.merge(opts)
    |> Req.request()
  end
end
