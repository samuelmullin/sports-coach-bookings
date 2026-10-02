defmodule SportsCoachBookings.Waivers.PdfStoreTest do
  use ExUnit.Case, async: true

  alias SportsCoachBookings.Waivers.PdfStore

  defp key, do: "tenant-#{System.unique_integer([:positive])}/waivers/x.pdf"

  test "round-trips, overwrites, and deletes" do
    k = key()
    assert {:error, :not_found} = PdfStore.get(k)

    assert :ok = PdfStore.put(k, "one")
    assert {:ok, "one"} = PdfStore.get(k)

    assert :ok = PdfStore.put(k, "two")
    assert {:ok, "two"} = PdfStore.get(k)

    assert :ok = PdfStore.delete(k)
    assert {:error, :not_found} = PdfStore.get(k)
    assert :ok = PdfStore.delete(k)
  end

  test "keys cannot escape the storage root" do
    assert {:error, :invalid_key} = PdfStore.put("../escape.pdf", "x")
    assert {:error, :invalid_key} = PdfStore.get("../../etc/passwd")
    assert {:error, :invalid_key} = PdfStore.delete("/etc/passwd")
  end
end
