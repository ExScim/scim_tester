defmodule ScimTester.ScimTesting do
  @moduledoc """
  Context module for SCIM integration testing.

  Provides functions for running SCIM API tests, generating test data,
  and managing test execution lifecycle.
  """

  alias ExScimClient.Resources.Groups
  alias ExScimClient.Resources.Users
  alias ExScimClient.Me
  alias ExScimClient.Resources.Bulk
  alias ExScimClient.Resources.Schemas
  alias ExScimClient.Resources.ResourceTypes
  alias ScimTester.DataGenConfig
  alias ScimTester.ResourceCheck
  alias ScimTester.SchemaPayload

  @user_schema_id "urn:ietf:params:scim:schemas:core:2.0:User"
  @group_schema_id "urn:ietf:params:scim:schemas:core:2.0:Group"

  @test_definitions [
    %{
      id: :create_user,
      name: "Create User",
      icon: "hero-beaker",
      description: "Create a new user account",
      depends_on: []
    },
    %{
      id: :get_user,
      name: "Get User",
      icon: "hero-beaker",
      description: "Fetch user details",
      depends_on: [:create_user]
    },
    %{
      id: :update_user,
      name: "Update User",
      icon: "hero-beaker",
      description: "Modify user information",
      depends_on: [:create_user]
    },
    %{
      id: :patch_user,
      name: "Patch User",
      icon: "hero-beaker",
      description: "Apply partial user updates",
      depends_on: [:create_user]
    },
    %{
      id: :list_users,
      name: "List Users",
      icon: "hero-beaker",
      description: "Browse all users",
      depends_on: []
    },
    %{
      id: :delete_user,
      name: "Delete User",
      icon: "hero-beaker",
      description: "Remove the test user",
      depends_on: [:create_user]
    },
    %{
      id: :create_group,
      name: "Create Group",
      icon: "hero-user-group",
      description: "Create a new group",
      depends_on: []
    },
    %{
      id: :get_group,
      name: "Get Group",
      icon: "hero-user-group",
      description: "Fetch group details",
      depends_on: [:create_group]
    },
    %{
      id: :update_group,
      name: "Update Group",
      icon: "hero-user-group",
      description: "Replace the group's display name",
      depends_on: [:create_group]
    },
    %{
      id: :group_membership,
      name: "Group Membership",
      icon: "hero-user-group",
      description: "Add the test user to the group and remove it again",
      depends_on: [:create_group, :create_user]
    },
    %{
      id: :nested_groups,
      name: "Nested Groups",
      icon: "hero-user-group",
      description: "Add a group to the group and reject circular nesting",
      depends_on: [:create_group]
    },
    %{
      id: :list_groups,
      name: "List Groups",
      icon: "hero-user-group",
      description: "Browse all groups",
      depends_on: []
    },
    %{
      id: :delete_group,
      name: "Delete Group",
      icon: "hero-user-group",
      description: "Remove the test group",
      depends_on: [:create_group]
    },
    %{
      id: :me_operations,
      name: "User Profile",
      icon: "hero-beaker",
      description: "Check current user information",
      depends_on: []
    },
    %{
      id: :schema_operations,
      name: "Schema Info",
      icon: "hero-beaker",
      description: "Get data structure details",
      depends_on: []
    },
    %{
      id: :resource_types,
      name: "Resource Types",
      icon: "hero-beaker",
      description: "List available resource types",
      depends_on: []
    },
    %{
      id: :bulk_operations,
      name: "Bulk Operations",
      icon: "hero-beaker",
      description: "Process multiple operations at once",
      depends_on: []
    }
  ]

  @doc """
  Returns the list of available test definitions.
  """
  def test_definitions, do: @test_definitions

  @doc """
  Initializes test results map with all tests in pending state.
  """
  def init_test_results do
    Enum.reduce(@test_definitions, %{}, fn test, acc ->
      Map.put(acc, test.id, %{status: :pending, result: nil, error: nil})
    end)
  end

  @doc """
  Returns the default enabled tests set (all tests).
  """
  def default_enabled_tests do
    @test_definitions |> Enum.map(& &1.id) |> MapSet.new()
  end

  @doc """
  Returns all test IDs that depend on the given test (direct and transitive).
  """
  def dependents_of(test_id) do
    direct =
      @test_definitions
      |> Enum.filter(fn t -> test_id in t.depends_on end)
      |> Enum.map(& &1.id)

    transitive = Enum.flat_map(direct, &dependents_of/1)

    Enum.uniq(direct ++ transitive)
  end

  @capability_test_map %{
    "patch" => [:patch_user],
    "bulk" => [:bulk_operations]
  }

  @doc """
  Returns the capability-to-test mapping.
  """
  def capability_test_map, do: @capability_test_map

  @doc """
  Given a capabilities map (from ServiceProviderConfig), returns the list of
  test IDs whose required capability is not supported by the provider.

  Returns an empty list if capabilities is nil.
  """
  def tests_disabled_by_capabilities(nil), do: []

  def tests_disabled_by_capabilities(capabilities) when is_map(capabilities) do
    Enum.flat_map(@capability_test_map, fn {capability_key, test_ids} ->
      supported = get_in(capabilities, [capability_key, "supported"])

      if supported == true do
        []
      else
        test_ids
      end
    end)
  end

  @doc """
  Returns a MapSet of enabled tests after removing tests unsupported by the
  provider's capabilities, including their transitive dependents.
  """
  def enabled_tests_for_capabilities(capabilities) do
    disabled = tests_disabled_by_capabilities(capabilities)
    all_disabled = Enum.flat_map(disabled, fn test_id -> [test_id | dependents_of(test_id)] end)
    all_disabled_set = MapSet.new(all_disabled)
    MapSet.difference(default_enabled_tests(), all_disabled_set)
  end

  @doc """
  Returns all dependencies of the given test (direct and transitive).
  """
  def dependencies_of(test_id) do
    test = Enum.find(@test_definitions, &(&1.id == test_id))

    case test do
      nil ->
        []

      %{depends_on: depends_on} ->
        transitive = Enum.flat_map(depends_on, &dependencies_of/1)
        Enum.uniq(depends_on ++ transitive)
    end
  end

  @doc """
  Enables a test and all its dependencies in the enabled tests set.
  """
  def enable_test(test_id, enabled_tests) do
    to_enable = MapSet.new([test_id | dependencies_of(test_id)])
    MapSet.union(enabled_tests, to_enable)
  end

  @doc """
  Disables a test and all its dependents in the enabled tests set.
  """
  def disable_test(test_id, enabled_tests) do
    to_disable = MapSet.new([test_id | dependents_of(test_id)])
    MapSet.difference(enabled_tests, to_disable)
  end

  @doc """
  Runs all SCIM tests in sequence.

  This function orchestrates the entire test suite, sending progress messages
  to the provided process ID. Only tests in the enabled_tests set will be executed.
  `schemas` maps schema URIs to the provider's schema definitions.
  """
  def run_all_tests(
        pid,
        client,
        enabled_tests,
        schemas \\ %{},
        data_config \\ DataGenConfig.default()
      ) do
    send(pid, {:log_message, "Starting SCIM Integration Tests", :start})

    user_id = run_create(pid, client, :create_user, enabled_tests, schemas, data_config)
    if user_id, do: send(pid, {:user_created, user_id})

    group_id = run_create(pid, client, :create_group, enabled_tests, schemas, data_config)
    if group_id, do: send(pid, {:group_created, group_id})

    resources = %{user: user_id, group: group_id}

    # Tests that need the created resources (only if enabled AND they exist)
    Enum.each(
      [
        :get_user,
        :update_user,
        :patch_user,
        :get_group,
        :update_group,
        :group_membership,
        :nested_groups
      ],
      fn test ->
        if MapSet.member?(enabled_tests, test) and resources_exist?(test, resources) do
          run_single_test(pid, client, test, resources, schemas, data_config)
        end
      end
    )

    # Independent tests (only if enabled)
    Enum.each(
      [
        :list_users,
        :list_groups,
        :me_operations,
        :schema_operations,
        :resource_types,
        :bulk_operations
      ],
      fn test ->
        if MapSet.member?(enabled_tests, test) do
          run_single_test(pid, client, test, resources, schemas, data_config)
        end
      end
    )

    # Delete the created resources last
    Enum.each([:delete_group, :delete_user], fn test ->
      if MapSet.member?(enabled_tests, test) and resources_exist?(test, resources) do
        run_single_test(pid, client, test, resources, schemas, data_config)
      end
    end)

    send(pid, {:tests_completed})
  end

  defp run_create(pid, client, test, enabled_tests, schemas, data_config) do
    if MapSet.member?(enabled_tests, test) do
      case run_single_test(pid, client, test, %{}, schemas, data_config) do
        {:ok, id} -> id
        _ -> nil
      end
    end
  end

  # Whether the resources a test's dependencies create exist.
  defp resources_exist?(test_id, resources) do
    deps = dependencies_of(test_id)

    (:create_user not in deps or resources.user != nil) and
      (:create_group not in deps or resources.group != nil)
  end

  @doc """
  Runs a single test and reports progress to the provided process ID.

  `resources` holds the ids of the created test user and group, as
  `%{user: id, group: id}`.
  """
  def run_single_test(
        pid,
        client,
        test_id,
        resources,
        schemas \\ %{},
        data_config \\ DataGenConfig.default()
      ) do
    send(pid, {:test_started, test_id})
    send(pid, {:log_message, "Running #{test_id}...", :running})

    # Validate client first
    case validate_client(client) do
      :ok ->
        result = execute_test_safely(test_id, client, resources, schemas || %{}, data_config)
        handle_test_result(pid, test_id, result)

      {:error, reason} ->
        send(pid, {:test_failed, test_id, reason})
        send(pid, {:log_message, "#{test_id} failed: #{reason}", :error})
        {:error, reason}
    end
  end

  defp validate_client(nil),
    do: {:error, "SCIM client not configured - please set BASE_URL and BEARER_TOKEN"}

  defp validate_client(_client), do: :ok

  defp execute_test_safely(test_id, client, resources, schemas, data_config) do
    user_id = Map.get(resources, :user)
    group_id = Map.get(resources, :group)
    user_schema = Map.get(schemas, @user_schema_id)

    try do
      case test_id do
        :create_user -> test_create_user(client, user_schema, data_config)
        :get_user -> test_get_user(client, user_id)
        :update_user -> test_update_user(client, user_id, user_schema, data_config)
        :patch_user -> test_patch_user(client, user_id, user_schema, data_config)
        :list_users -> test_list_users(client)
        :delete_user -> test_delete_user(client, user_id)
        :create_group -> test_create_group(client)
        :get_group -> test_get_group(client, group_id)
        :update_group -> test_update_group(client, group_id)
        :group_membership -> test_group_membership(client, group_id, user_id, schemas)
        :nested_groups -> test_nested_groups(client, group_id, user_id, schemas)
        :list_groups -> test_list_groups(client)
        :delete_group -> test_delete_group(client, group_id)
        :me_operations -> test_me_operations(client)
        :schema_operations -> test_schema_operations(client)
        :resource_types -> test_resource_type_operations(client)
        :bulk_operations -> test_bulk_operations(client, user_schema, data_config)
      end
    rescue
      error -> {:error, "Connection failed: #{inspect(error)}"}
    catch
      :exit, reason -> {:error, "Connection terminated: #{inspect(reason)}"}
      error -> {:error, "Request failed: #{inspect(error)}"}
    end
  end

  defp handle_test_result(pid, test_id, result) do
    case result do
      {:ok, data} ->
        send(pid, {:test_completed, test_id, data})
        send(pid, {:log_message, "#{test_id} completed successfully", :success})
        {:ok, data}

      {:error, reason} ->
        report_failure(pid, test_id, format_error(reason))

      other ->
        report_failure(pid, test_id, "Unexpected response format: #{inspect(other)}")
    end
  end

  defp report_failure(pid, test_id, error_message) do
    send(pid, {:test_failed, test_id, error_message})
    send(pid, {:log_message, "#{test_id} failed: #{error_message}", :error})
    {:error, error_message}
  end

  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason)

  defp test_create_user(client, user_schema, data_config) do
    user_data =
      if user_schema,
        do: SchemaPayload.generate_create_payload(user_schema, data_config),
        else: generate_random_user(data_config)

    case Users.create(client, user_data) do
      {:ok, %{"id" => user_id} = _response} -> {:ok, user_id}
      error -> error
    end
  end

  defp test_get_user(client, user_id) do
    Users.get(client, user_id)
  end

  defp test_update_user(client, user_id, user_schema, data_config) do
    case Users.get(client, user_id) do
      {:ok, existing_user} ->
        updated_data =
          if user_schema,
            do: SchemaPayload.generate_update_payload(user_schema, existing_user, data_config),
            else: generate_random_user_update(existing_user, data_config)

        readable =
          SchemaPayload.readable_attribute_names(
            user_schema || SchemaPayload.default_user_schema()
          )

        expect =
          existing_user
          |> ResourceCheck.changes(updated_data)
          |> Enum.filter(fn {[name | _], _value} -> name in readable end)

        with {:ok, response} <- Users.update(client, user_id, updated_data) do
          verify_write(fn -> Users.get(client, user_id) end, "PUT", response, expect)
        end

      error ->
        error
    end
  end

  defp test_patch_user(client, user_id, user_schema, data_config) do
    cases =
      SchemaPayload.generate_patch_cases(
        user_schema || SchemaPayload.default_user_schema(),
        user_id,
        data_config
      )

    if Enum.all?(cases, &Map.has_key?(&1, :reject)) do
      {:error, "Schema declares no attribute to PATCH"}
    else
      Enum.reduce_while(cases, {:ok, nil}, fn patch_case, _acc ->
        case run_patch_case(client, user_id, patch_case) do
          {:ok, user} -> {:cont, {:ok, user}}
          {:error, reason} -> {:halt, {:error, "#{patch_case.label}: #{format_error(reason)}"}}
        end
      end)
    end
  end

  defp run_patch_case(client, user_id, %{reject: scim_types} = patch_case) do
    expected = "400 " <> Enum.join(scim_types, " or ")

    case Users.patch(client, user_id, patch_case.operations) do
      {:error, %{status: 400, body: body}} ->
        scim_type = if is_map(body), do: body["scimType"]

        if scim_type in scim_types,
          do: Users.get(client, user_id),
          else: {:error, "rejected with scimType #{inspect(scim_type)}, expected #{expected}"}

      {:error, %{status: status}} ->
        {:error, "returned #{status}, expected #{expected}"}

      {:ok, _response} ->
        {:error, "PATCH accepted, expected #{expected}"}

      error ->
        error
    end
  end

  defp run_patch_case(client, user_id, patch_case) do
    with {:ok, response} <- Users.patch(client, user_id, patch_case.operations) do
      verify_write(fn -> Users.get(client, user_id) end, "PATCH", response, patch_case.expect)
    end
  end

  # Checks the response, if it has a body, and a fresh GET.
  defp verify_write(fetch, method, response, expect) do
    with :ok <- check_written(method, "response", response, expect),
         {:ok, fetched} <- fetch.(),
         :ok <- check_written(method, "GET", fetched, expect) do
      {:ok, fetched}
    end
  end

  defp check_written(_method, "response", response, _expect)
       when not is_map(response) or map_size(response) == 0,
       do: :ok

  defp check_written(method, source, resource, expect) do
    case ResourceCheck.mismatches(resource, expect) do
      [] ->
        :ok

      mismatches ->
        {:error,
         "#{method} accepted but not applied (#{source}): " <> Enum.join(mismatches, "; ")}
    end
  end

  defp test_list_users(client) do
    Users.list(client)
  end

  defp test_delete_user(client, user_id) do
    Users.delete(client, user_id)
  end

  defp test_me_operations(client) do
    Me.get(client)
  end

  defp test_schema_operations(client) do
    Schemas.list(client)
  end

  defp test_resource_type_operations(client) do
    ResourceTypes.list(client)
  end

  defp test_bulk_operations(client, user_schema, data_config) do
    user1_data =
      if user_schema,
        do: SchemaPayload.generate_create_payload(user_schema, data_config),
        else: generate_random_user(data_config)

    user2_data =
      if user_schema,
        do: SchemaPayload.generate_create_payload(user_schema, data_config),
        else: generate_random_user(data_config)

    bulk_operations = [
      %{
        "method" => "POST",
        "path" => "/Users",
        "bulkId" => "bulk_user_1",
        "data" => user1_data
      },
      %{
        "method" => "POST",
        "path" => "/Users",
        "bulkId" => "bulk_user_2",
        "data" => user2_data
      }
    ]

    bulk_request = %{
      "schemas" => ["urn:ietf:params:scim:api:messages:2.0:BulkRequest"],
      "Operations" => bulk_operations
    }

    Bulk.execute(client, bulk_request)
  end

  defp test_create_group(client) do
    display_name = "scim_tester_#{generate_random_string(8)}"
    group_data = %{"schemas" => [@group_schema_id], "displayName" => display_name}

    case Groups.create(client, group_data) do
      {:ok, %{"id" => group_id} = response} ->
        fetch = fn -> Groups.get(client, group_id) end

        with {:ok, _group} <-
               verify_write(fetch, "POST", response, [{["displayName"], display_name}]) do
          {:ok, group_id}
        end

      {:ok, _response} ->
        {:error, "POST /Groups returned no id"}

      error ->
        error
    end
  end

  defp test_get_group(client, group_id) do
    with {:ok, group} <- Groups.get(client, group_id) do
      if group["id"] == group_id,
        do: {:ok, group},
        else: {:error, "GET returned id #{inspect(group["id"])}, expected #{group_id}"}
    end
  end

  defp test_update_group(client, group_id) do
    with {:ok, existing} <- Groups.get(client, group_id) do
      display_name = "scim_tester_#{generate_random_string(8)}"
      updated = existing |> Map.delete("meta") |> Map.put("displayName", display_name)

      with {:ok, response} <- Groups.update(client, group_id, updated) do
        fetch = fn -> Groups.get(client, group_id) end
        verify_write(fetch, "PUT", response, [{["displayName"], display_name}])
      end
    end
  end

  defp test_group_membership(client, group_id, user_id, schemas) do
    with :ok <- members_writable(schemas),
         {:ok, _} <- step("Add user", add_member(client, group_id, user_id, "User")),
         :ok <- expect_member(client, group_id, user_id, "User"),
         :ok <- expect_user_group(client, user_id, group_id, "direct", schemas),
         {:ok, _} <- step("Remove user", remove_member(client, group_id, user_id)),
         :ok <- refute_member(client, group_id, user_id),
         :ok <- refute_user_group(client, user_id, group_id, schemas) do
      Groups.get(client, group_id)
    end
  end

  # Nests a new child group in the group, then deletes the child.
  defp test_nested_groups(client, parent_id, user_id, schemas) do
    with :ok <- members_writable(schemas),
         {:ok, child_id} <- step("Create child group", test_create_group(client)) do
      result = check_nesting(client, parent_id, child_id, user_id, schemas)
      Groups.delete(client, child_id)
      result
    end
  end

  defp check_nesting(client, parent_id, child_id, user_id, schemas) do
    with {:ok, _} <- step("Add child group", add_member(client, parent_id, child_id, "Group")),
         :ok <- expect_member(client, parent_id, child_id, "Group"),
         :ok <- check_indirect_membership(client, parent_id, child_id, user_id, schemas),
         :ok <- expect_cycle_rejected(client, child_id, parent_id),
         {:ok, _} <- step("Delete child group", Groups.delete(client, child_id)),
         :ok <- refute_member(client, parent_id, child_id) do
      Groups.get(client, parent_id)
    end
  end

  # A user in the child group is an indirect member of the parent.
  defp check_indirect_membership(_client, _parent_id, _child_id, nil, _schemas), do: :ok

  defp check_indirect_membership(client, parent_id, child_id, user_id, schemas) do
    if user_groups_declared?(schemas) do
      with {:ok, _} <-
             step("Add user to child group", add_member(client, child_id, user_id, "User")),
           :ok <- expect_user_group(client, user_id, child_id, "direct", schemas),
           :ok <- expect_user_group(client, user_id, parent_id, "indirect", schemas),
           {:ok, _} <-
             step("Remove user from child group", remove_member(client, child_id, user_id)) do
        refute_user_group(client, user_id, parent_id, schemas)
      end
    else
      :ok
    end
  end

  defp expect_cycle_rejected(client, child_id, parent_id) do
    case add_member(client, child_id, parent_id, "Group") do
      {:error, %{status: 400}} -> :ok
      {:error, %{status: status}} -> {:error, "Circular nesting returned #{status}, expected 400"}
      {:ok, _} -> {:error, "Circular nesting accepted, expected 400"}
      error -> error
    end
  end

  defp test_list_groups(client) do
    case Groups.list(client) do
      {:ok, %{"totalResults" => total} = body} when is_integer(total) ->
        if total == 0 or is_list(body["Resources"]),
          do: {:ok, body},
          else: {:error, "totalResults is #{total} but Resources is missing"}

      {:ok, _body} ->
        {:error, "ListResponse has no totalResults"}

      error ->
        error
    end
  end

  defp test_delete_group(client, group_id) do
    with {:ok, _} <- Groups.delete(client, group_id) do
      case Groups.get(client, group_id) do
        {:error, %{status: 404}} ->
          {:ok, group_id}

        {:error, %{status: status}} ->
          {:error, "GET after DELETE returned #{status}, expected 404"}

        {:ok, _group} ->
          {:error, "GET after DELETE still returns the group"}

        error ->
          error
      end
    end
  end

  defp add_member(client, group_id, member_id, type) do
    Groups.patch(client, group_id, [
      %{
        "op" => "add",
        "path" => "members",
        "value" => [%{"value" => member_id, "type" => type}]
      }
    ])
  end

  defp remove_member(client, group_id, member_id) do
    Groups.patch(client, group_id, [
      %{"op" => "remove", "path" => ~s(members[value eq "#{member_id}"])}
    ])
  end

  defp members_writable(schemas) do
    members =
      schemas
      |> Map.get(@group_schema_id, %{})
      |> find_attribute("members")

    if members && members["mutability"] == "readOnly",
      do: {:error, "Group schema declares members readOnly"},
      else: :ok
  end

  defp user_groups_declared?(schemas) do
    schemas
    |> Map.get(@user_schema_id, %{})
    |> find_attribute("groups")
    |> Kernel.!=(nil)
  end

  defp find_attribute(schema, name) do
    schema
    |> Map.get("attributes", [])
    |> Enum.find(&(String.downcase(Map.get(&1, "name", "")) == name))
  end

  defp expect_member(client, group_id, member_id, type) do
    with {:ok, group} <- step("GET group", Groups.get(client, group_id)) do
      case find_value(ResourceCheck.get_path(group, ["members"]), member_id) do
        nil -> {:error, "members of #{group_id} lack #{member_id}"}
        member -> check_type("member #{member_id}", member, type)
      end
    end
  end

  defp refute_member(client, group_id, member_id) do
    with {:ok, group} <- step("GET group", Groups.get(client, group_id)) do
      if find_value(ResourceCheck.get_path(group, ["members"]), member_id),
        do: {:error, "members of #{group_id} still list #{member_id}"},
        else: :ok
    end
  end

  # User.groups is checked only when the User schema declares it.
  defp expect_user_group(client, user_id, group_id, type, schemas) do
    if user_groups_declared?(schemas) do
      with {:ok, user} <- step("GET user", Users.get(client, user_id)) do
        case find_value(ResourceCheck.get_path(user, ["groups"]), group_id) do
          nil -> {:error, "groups of user #{user_id} lack #{group_id} (#{type})"}
          group -> check_type("group #{group_id} of user #{user_id}", group, type)
        end
      end
    else
      :ok
    end
  end

  defp refute_user_group(client, user_id, group_id, schemas) do
    if user_groups_declared?(schemas) do
      with {:ok, user} <- step("GET user", Users.get(client, user_id)) do
        if find_value(ResourceCheck.get_path(user, ["groups"]), group_id),
          do: {:error, "groups of user #{user_id} still list #{group_id}"},
          else: :ok
      end
    else
      :ok
    end
  end

  defp find_value(entries, value) when is_list(entries),
    do: Enum.find(entries, &(ResourceCheck.get_path(&1, ["value"]) == value))

  defp find_value(_entries, _value), do: nil

  # `type` is optional; when present it must match.
  defp check_type(label, entry, expected) do
    case ResourceCheck.get_path(entry, ["type"]) do
      nil ->
        :ok

      type ->
        if ResourceCheck.contains?(type, expected),
          do: :ok,
          else: {:error, "#{label} has type #{inspect(type)}, expected #{expected}"}
    end
  end

  defp step(_label, {:ok, _} = ok), do: ok
  defp step(label, {:error, reason}), do: {:error, "#{label}: #{format_error(reason)}"}

  # Data generation functions

  defp generate_random_user(data_config) do
    first_name = DataGenConfig.random_first_name(data_config)
    last_name = DataGenConfig.random_last_name(data_config)
    email = DataGenConfig.random_email(data_config, first_name, last_name)

    %{
      "schemas" => ["urn:ietf:params:scim:schemas:core:2.0:User"],
      "userName" => "test_user_#{generate_random_string(8)}",
      "name" => %{
        "givenName" => first_name,
        "familyName" => last_name
      },
      "displayName" => "#{first_name} #{last_name}",
      "emails" => [
        %{
          "value" => email,
          "type" => "work",
          "primary" => true
        }
      ],
      "active" => true,
      "title" => DataGenConfig.random_job_title(data_config)
    }
  end

  defp generate_random_user_update(existing_user, data_config) do
    random_id = generate_random_string(6)
    first_name = Enum.random(["Updated", "Modified", "Changed", "New"])
    last_name = Enum.random(["User", "Person", "Individual", "Account"])
    display_name = "#{first_name} #{last_name} #{random_id}"
    title = "Updated #{DataGenConfig.random_job_title(data_config)}"

    existing_user
    |> put_in(["name", "givenName"], first_name)
    |> put_in(["name", "familyName"], last_name)
    |> Map.put("displayName", display_name)
    |> Map.put("title", title)
  end

  defp generate_random_string(length) do
    chars = "abcdefghijklmnopqrstuvwxyz0123456789"
    chars_list = String.graphemes(chars)

    1..length
    |> Enum.map(fn _ -> Enum.random(chars_list) end)
    |> Enum.join("")
  end
end
