defmodule Modcast.MDFParserTest do
  use ExUnit.Case
  alias Modcast.MDFParser

  @moduledoc """
  Basic tests for MDF parser demo functionality.
  """



  describe "helper functions" do
    setup do
      metadata = %{
        name: "Demo Car",
        author: "demo.author",
        asset_type: "player_car"
      }
      {:ok, metadata: metadata}
    end

    test "get_name/1 returns mod name", %{metadata: metadata} do
      assert MDFParser.get_name(metadata) == "Demo Car"
    end

    test "get_author/1 returns author", %{metadata: metadata} do
      assert MDFParser.get_author(metadata) == "demo.author"
    end

    test "get_asset_type/1 returns asset type", %{metadata: metadata} do
      assert MDFParser.get_asset_type(metadata) == "player_car"
    end

    test "get_name/1 returns default for missing name" do
      assert MDFParser.get_name(%{}) == "Unknown Mod"
    end
  end

  describe "parse_from_zip/1" do
    test "returns error for non-existent file" do
      assert {:error, :file_not_found} = MDFParser.parse_from_zip("nonexistent.zip")
    end
  end
end
