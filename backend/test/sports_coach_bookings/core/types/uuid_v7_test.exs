defmodule SportsCoachBookings.Core.Types.UUIDv7Test do
  use ExUnit.Case, async: true

  alias SportsCoachBookings.Core.Types.UUIDv7

  test "generates a canonical v7 UUID string" do
    uuid = UUIDv7.generate()

    assert String.match?(
             uuid,
             ~r/^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/
           )
  end

  test "generated ids sort by creation time" do
    first = UUIDv7.generate()
    Process.sleep(2)
    second = UUIDv7.generate()

    assert first < second
  end

  test "round-trips through the Ecto type" do
    uuid = UUIDv7.generate()
    assert {:ok, raw} = UUIDv7.dump(uuid)
    assert byte_size(raw) == 16
    assert {:ok, ^uuid} = UUIDv7.load(raw)
  end
end
