defmodule ScimTester.ConnectionTest do
  use ExUnit.Case, async: true

  alias ExScimClient.Client
  alias ScimTester.Connection

  describe "build/1" do
    test "returns {\"\", nil} when base URL is missing" do
      assert {"", nil} = Connection.build(%{"base_url" => "", "auth_method" => "bearer"})
    end

    test "normalizes the base URL by appending /scim/v2 when absent" do
      {normalized, _client} =
        Connection.build(%{
          "base_url" => "https://api.example.com",
          "auth_method" => "bearer",
          "bearer_token" => "tok"
        })

      assert normalized == "https://api.example.com/scim/v2"
    end

    test "leaves an already-normalized base URL untouched" do
      {normalized, _client} =
        Connection.build(%{
          "base_url" => "https://api.example.com/scim/v2",
          "auth_method" => "bearer",
          "bearer_token" => "tok"
        })

      assert normalized == "https://api.example.com/scim/v2"
    end

    test "bearer method builds a bearer client" do
      {_url, client} =
        Connection.build(%{
          "base_url" => "https://api.example.com/scim/v2",
          "auth_method" => "bearer",
          "bearer_token" => "tok"
        })

      assert %Client{auth: {:bearer, "tok"}} = client
    end

    test "bearer method without a token yields no client" do
      {_url, client} =
        Connection.build(%{
          "base_url" => "https://api.example.com/scim/v2",
          "auth_method" => "bearer",
          "bearer_token" => ""
        })

      assert is_nil(client)
    end

    test "basic method builds a basic client" do
      {_url, client} =
        Connection.build(%{
          "base_url" => "https://api.example.com/scim/v2",
          "auth_method" => "basic",
          "basic_username" => "user",
          "basic_password" => "pass"
        })

      assert %Client{auth: {:basic, "user", "pass"}} = client
    end

    test "basic method without a username yields no client" do
      {_url, client} =
        Connection.build(%{
          "base_url" => "https://api.example.com/scim/v2",
          "auth_method" => "basic",
          "basic_username" => "",
          "basic_password" => "pass"
        })

      assert is_nil(client)
    end

    test "oauth method yields no client until a token is fetched" do
      {_url, client} =
        Connection.build(%{
          "base_url" => "https://api.example.com/scim/v2",
          "auth_method" => "oauth",
          "oauth_token_url" => "https://idp.example.com/token",
          "oauth_client_id" => "id",
          "oauth_client_secret" => "secret"
        })

      assert is_nil(client)
    end

    test "defaults to the bearer method when none is given" do
      {_url, client} =
        Connection.build(%{"base_url" => "https://api.example.com", "bearer_token" => "tok"})

      assert %Client{auth: {:bearer, "tok"}} = client
    end
  end

  describe "client_with_token/2" do
    test "builds a bearer client from a token" do
      assert %Client{auth: {:bearer, "tok"}} =
               Connection.client_with_token("https://api.example.com/scim/v2", "tok")
    end
  end
end
