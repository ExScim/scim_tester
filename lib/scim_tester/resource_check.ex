defmodule ScimTester.ResourceCheck do
  @moduledoc """
  Compares a SCIM resource returned by a provider with the values a test wrote.

  Attribute names match case-insensitively, as SCIM requires. Strings compare
  case-insensitively, maps match on the keys of the expected value, and lists
  match when every expected element has a match. Attributes the provider adds
  (`meta`, `name.formatted`) are ignored.
  """

  @type expectation :: {path :: [String.t()], value :: term()}

  @doc """
  Returns a description of every expectation `resource` doesn't meet, or `[]`.
  """
  @spec mismatches(map(), [expectation()]) :: [String.t()]
  def mismatches(resource, expectations) do
    Enum.flat_map(expectations, fn {path, expected} ->
      actual = get_path(resource, path)

      if contains?(actual, expected),
        do: [],
        else: ["#{Enum.join(path, ".")} is #{inspect(actual)}, expected #{inspect(expected)}"]
    end)
  end

  @doc """
  Returns the expectations `updated` sets relative to `existing`: one per changed
  value, descending into maps so unchanged sub-attributes aren't compared.
  """
  @spec changes(map(), map()) :: [expectation()]
  def changes(existing, updated), do: changes(existing, updated, [])

  defp changes(existing, updated, path) when is_map(updated) and is_map(existing) do
    Enum.flat_map(updated, fn {key, value} ->
      changes(get_path(existing, [key]), value, path ++ [key])
    end)
  end

  defp changes(same, same, _path), do: []
  defp changes(_existing, nil, _path), do: []
  defp changes(nil, updated, path) when is_map(updated), do: changes(%{}, updated, path)
  defp changes(_existing, updated, path), do: [{path, updated}]

  @doc """
  Returns the value at `path`, looking up each attribute name case-insensitively.
  """
  @spec get_path(term(), [String.t()]) :: term()
  def get_path(value, []), do: value

  def get_path(resource, [name | rest]) when is_map(resource) do
    normalized = String.downcase(name)

    resource
    |> Enum.find_value(fn {key, value} ->
      if String.downcase(to_string(key)) == normalized, do: {:found, value}
    end)
    |> case do
      {:found, value} -> get_path(value, rest)
      nil -> nil
    end
  end

  def get_path(_value, _path), do: nil

  @doc """
  Returns whether `actual` holds `expected`.
  """
  @spec contains?(term(), term()) :: boolean()
  def contains?(actual, expected) when is_map(expected) do
    is_map(actual) and
      Enum.all?(expected, fn {key, value} -> contains?(get_path(actual, [key]), value) end)
  end

  def contains?(actual, expected) when is_list(expected) do
    is_list(actual) and
      Enum.all?(expected, fn value -> Enum.any?(actual, &contains?(&1, value)) end)
  end

  def contains?(actual, expected) when is_binary(actual) and is_binary(expected) do
    String.downcase(actual) == String.downcase(expected)
  end

  def contains?(actual, expected), do: actual == expected
end
