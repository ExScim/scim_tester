defmodule ScimTester.Connection do
  @moduledoc """
  Builds a SCIM client from user-supplied connection details.

  Supports three authentication methods:

    * `"bearer"` - a bearer token
    * `"basic"` - HTTP Basic (username + password)
    * `"oauth"` - OAuth2 client-credentials; the token is fetched separately via
      `fetch_token/1` and then used as a bearer token

  Normalizes the base URL (ensuring a trailing `/scim/v2`) and returns the
  normalized URL alongside the client. Returns `{"", nil}` when the base URL is
  missing and `{normalized_url, nil}` when the chosen method is not yet fully
  configured (or, for OAuth, before a token has been fetched).
  """

  alias ExScimClient.Client

  @type config :: %{optional(String.t()) => String.t()}

  @doc """
  Returns `{normalized_base_url, client_or_nil}` for the given connection config.

  The config is a string-keyed map such as the one produced by the connection
  form: `base_url`, `auth_method`, and the method-specific fields.
  """
  @spec build(config()) :: {String.t(), Client.t() | nil}
  def build(config) do
    base_url = fetch(config, "base_url")

    if base_url == "" do
      {"", nil}
    else
      normalized = normalize_base_url(base_url)
      {normalized, build_client(normalized, fetch(config, "auth_method", "bearer"), config)}
    end
  end

  @doc """
  Fetches an OAuth2 access token using the client-credentials grant.

  Custom `oauth_scopes` (space-separated) are included as the `scope` parameter
  when present. Returns `{:ok, access_token}` or `{:error, message}`.
  """
  @spec fetch_token(config()) :: {:ok, String.t()} | {:error, String.t()}
  def fetch_token(config) do
    token_url = fetch(config, "oauth_token_url")
    client_id = fetch(config, "oauth_client_id")
    client_secret = fetch(config, "oauth_client_secret")
    scopes = fetch(config, "oauth_scopes")

    form =
      [
        grant_type: "client_credentials",
        client_id: client_id,
        client_secret: client_secret
      ]
      |> maybe_put_scope(scopes)

    case Req.post(token_url, form: form) do
      {:ok, %{status: status, body: %{"access_token" => token}}} when status in 200..299 ->
        {:ok, token}

      {:ok, %{status: status, body: body}} ->
        {:error, "Token request failed (HTTP #{status}): #{describe(body)}"}

      {:error, reason} ->
        {:error, "Token request error: #{Exception.message(reason)}"}
    end
  rescue
    error -> {:error, "Token request error: #{Exception.message(error)}"}
  end

  defp build_client(url, "bearer", config) do
    case fetch(config, "bearer_token") do
      "" -> nil
      token -> Client.new(url, {:bearer, token})
    end
  end

  defp build_client(url, "basic", config) do
    username = fetch(config, "basic_username")
    password = fetch(config, "basic_password")

    if username == "", do: nil, else: Client.new(url, {:basic, username, password})
  end

  # OAuth clients are built from a fetched token via `client_with_token/2`.
  defp build_client(_url, "oauth", _config), do: nil

  defp build_client(_url, _method, _config), do: nil

  @doc """
  Builds a bearer client from a normalized base URL and an access token.
  """
  @spec client_with_token(String.t(), String.t()) :: Client.t()
  def client_with_token(base_url, token), do: Client.new(base_url, {:bearer, token})

  defp maybe_put_scope(form, ""), do: form
  defp maybe_put_scope(form, scopes), do: form ++ [scope: scopes]

  defp fetch(config, key, default \\ "") do
    config
    |> Map.get(key, default)
    |> to_string()
    |> String.trim()
  end

  defp describe(body) when is_binary(body), do: body
  defp describe(body), do: inspect(body)

  defp normalize_base_url(base_url) do
    base_url = base_url |> String.trim() |> String.trim_trailing("/")

    if String.ends_with?(base_url, "/scim/v2") do
      base_url
    else
      base_url <> "/scim/v2"
    end
  end
end
