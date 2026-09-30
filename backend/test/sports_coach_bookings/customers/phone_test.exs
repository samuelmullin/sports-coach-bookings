defmodule SportsCoachBookings.Customers.PhoneTest do
  use ExUnit.Case, async: true

  alias SportsCoachBookings.Customers.Phone

  describe "normalize/2" do
    test "normalizes national numbers for supported regions to E.164" do
      assert {:ok, "+19025550111"} = Phone.normalize("CA", "9025550111")
      assert {:ok, "+14155550123"} = Phone.normalize("US", "4155550123")
      assert {:ok, "+447911123456"} = Phone.normalize("GB", "7911123456")
      assert {:ok, "+61412345678"} = Phone.normalize("AU", "412345678")
    end

    test "ignores case and surrounding whitespace in the region" do
      assert {:ok, "+19025550111"} = Phone.normalize(" ca ", "9025550111")
    end

    test "rejects an invalid national number" do
      assert {:error, :invalid} = Phone.normalize("CA", "123")
      assert {:error, :invalid} = Phone.normalize("US", "555")
    end

    test "rejects a national number without a region" do
      assert {:error, :invalid} = Phone.normalize(nil, "9025550111")
      assert {:error, :invalid} = Phone.normalize("", "9025550111")
    end

    test "treats blank input as optional" do
      assert {:ok, nil} = Phone.normalize("CA", nil)
      assert {:ok, nil} = Phone.normalize("CA", "")
      assert {:ok, nil} = Phone.normalize(nil, "   ")
      assert {:ok, nil} = Phone.normalize(nil, nil)
    end

    test "accepts a full E.164 number regardless of the region" do
      assert {:ok, "+19025550111"} = Phone.normalize(nil, "+19025550111")
      assert {:ok, "+447911123456"} = Phone.normalize("US", "+447911123456")
    end

    test "rejects an invalid E.164 number" do
      assert {:error, :invalid} = Phone.normalize(nil, "+15555550100")
    end
  end
end
