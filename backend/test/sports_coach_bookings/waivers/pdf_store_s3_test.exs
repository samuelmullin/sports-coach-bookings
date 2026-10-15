defmodule SportsCoachBookings.Waivers.PdfStoreS3Test do
  use ExUnit.Case, async: false

  alias SportsCoachBookings.Tenancy.Storage.S3, as: Signer
  alias SportsCoachBookings.Waivers.PdfStore.S3

  @key "tenant-1/waivers/sig-1.pdf"

  setup do
    previous = Application.get_env(:sports_coach_bookings, Signer)

    Application.put_env(:sports_coach_bookings, Signer,
      bucket: "public-assets",
      private_bucket: "private-waivers",
      region: "ca-central-1",
      access_key_id: "AKIATEST",
      secret_access_key: "secret",
      endpoint: "http://rustfs.test:9000",
      force_path_style: true,
      req_options: [plug: {Req.Test, __MODULE__}]
    )

    on_exit(fn -> Application.put_env(:sports_coach_bookings, Signer, previous || []) end)
  end

  defp signed?(conn) do
    query = URI.decode_query(conn.query_string)

    query["X-Amz-Algorithm"] == "AWS4-HMAC-SHA256" and
      String.starts_with?(query["X-Amz-Credential"], "AKIATEST/") and
      query["X-Amz-Signature"] =~ ~r/\A[0-9a-f]{64}\z/
  end

  test "put sends a signed PUT of the bytes to the private bucket" do
    Req.Test.expect(__MODULE__, fn conn ->
      assert conn.method == "PUT"
      assert conn.request_path == "/private-waivers/#{@key}"
      assert signed?(conn)
      assert Plug.Conn.get_req_header(conn, "content-type") == ["application/pdf"]
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      assert body == "%PDF-bytes"
      Plug.Conn.send_resp(conn, 200, "")
    end)

    assert :ok = S3.put(@key, "%PDF-bytes")
  end

  test "get returns the body, and maps 404 to :not_found" do
    Req.Test.expect(__MODULE__, fn conn ->
      assert conn.method == "GET"
      assert signed?(conn)
      Plug.Conn.send_resp(conn, 200, "%PDF-bytes")
    end)

    assert {:ok, "%PDF-bytes"} = S3.get(@key)

    Req.Test.expect(__MODULE__, &Plug.Conn.send_resp(&1, 404, "<Error>NoSuchKey</Error>"))
    assert {:error, :not_found} = S3.get(@key)
  end

  test "delete treats 204 and 404 as success and surfaces other failures" do
    for status <- [204, 404] do
      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.method == "DELETE"
        assert signed?(conn)
        Plug.Conn.send_resp(conn, status, "")
      end)

      assert :ok = S3.delete(@key)
    end

    Req.Test.expect(__MODULE__, &Plug.Conn.send_resp(&1, 403, "denied"))
    assert {:error, {:http_status, 403}} = S3.delete(@key)
  end

  test "falls back to the shared bucket when no private bucket is configured" do
    config = Application.get_env(:sports_coach_bookings, Signer)

    Application.put_env(
      :sports_coach_bookings,
      Signer,
      Keyword.delete(config, :private_bucket)
    )

    Req.Test.expect(__MODULE__, fn conn ->
      assert conn.request_path == "/public-assets/#{@key}"
      Plug.Conn.send_resp(conn, 200, "")
    end)

    assert :ok = S3.put(@key, "x")
  end
end
