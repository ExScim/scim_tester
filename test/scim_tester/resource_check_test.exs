defmodule ScimTester.ResourceCheckTest do
  use ExUnit.Case, async: true

  alias ScimTester.ResourceCheck

  @user %{
    "userName" => "jdoe",
    "active" => false,
    "name" => %{"givenName" => "John", "familyName" => "Smith", "formatted" => "John Smith"},
    "emails" => [%{"value" => "j@example.com", "type" => "work", "primary" => true}]
  }

  describe "mismatches/2" do
    test "returns nothing when every expectation holds" do
      expect = [
        {["name", "familyName"], "Smith"},
        {["active"], false},
        {["emails"], [%{"value" => "j@example.com", "type" => "work"}]}
      ]

      assert ResourceCheck.mismatches(@user, expect) == []
    end

    test "describes values that weren't applied" do
      assert ["name.familyName is \"Smith\", expected \"Doe\""] =
               ResourceCheck.mismatches(@user, [{["name", "familyName"], "Doe"}])
    end

    test "reports missing attributes" do
      assert ["title is nil, expected \"Engineer\""] =
               ResourceCheck.mismatches(@user, [{["title"], "Engineer"}])
    end

    test "matches attribute names and strings case-insensitively" do
      assert ResourceCheck.mismatches(@user, [{["Name", "FAMILYNAME"], "smith"}]) == []
    end

    test "does not treat a string as a boolean" do
      assert [_] = ResourceCheck.mismatches(%{"active" => "false"}, [{["active"], false}])
    end

    test "treats nil as absent" do
      assert ResourceCheck.mismatches(%{"userName" => "jd"}, [{["displayName"], nil}]) == []
      assert [_] = ResourceCheck.mismatches(%{"displayName" => "JD"}, [{["displayName"], nil}])
    end
  end

  describe "changes/2" do
    test "returns changed leaves and skips unchanged sub-attributes" do
      updated =
        @user
        |> put_in(["name", "familyName"], "Doe")
        |> Map.put("title", "Engineer")

      assert Enum.sort(ResourceCheck.changes(@user, updated)) == [
               {["name", "familyName"], "Doe"},
               {["title"], "Engineer"}
             ]
    end

    test "returns whole lists that changed" do
      updated = Map.put(@user, "emails", [%{"value" => "new@example.com"}])

      assert ResourceCheck.changes(@user, updated) == [
               {["emails"], [%{"value" => "new@example.com"}]}
             ]
    end
  end
end
