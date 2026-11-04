defmodule ScimTester.ScimTestingTest do
  use ExUnit.Case, async: true

  alias ScimTester.ScimTesting

  describe "group test dependencies" do
    test "enabling group_membership enables the group and user it needs" do
      enabled = ScimTesting.enable_test(:group_membership, MapSet.new())

      assert MapSet.equal?(enabled, MapSet.new([:group_membership, :create_group, :create_user]))
    end

    test "disabling create_user keeps nested_groups but not group_membership" do
      enabled = ScimTesting.disable_test(:create_user, ScimTesting.default_enabled_tests())

      assert :nested_groups in enabled
      refute :group_membership in enabled
    end

    test "disabling create_group disables every test on the test group" do
      enabled = ScimTesting.disable_test(:create_group, ScimTesting.default_enabled_tests())

      for test <- [:get_group, :update_group, :group_membership, :nested_groups, :delete_group] do
        refute test in enabled
      end

      assert :list_groups in enabled
    end
  end
end
