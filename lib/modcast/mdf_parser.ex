defmodule Modcast.MDFParser do
  @moduledoc """
  Simple parser for Mod Definition Format (MDF) files.
  Reads mds.xml from mod ZIP files to extract metadata.
  """
  
  require Logger

  @mdf_filename "mds.xml"

  @doc """
  Parse MDF file from a ZIP archive.
  Returns basic metadata map.
  
  ## Examples
  
      iex> MDFParser.parse_from_zip("./mods/car_mod.zip")
      {:ok, %{name: "Veilside RX7", author: "pablo.masian", asset_type: "player_car"}}
  """
  def parse_from_zip(zip_path) do
    with true <- File.exists?(zip_path),
         {:ok, zip_handle} <- :zip.zip_open(to_charlist(zip_path), [:memory]),
         {:ok, xml_content} <- read_mds_from_zip(zip_handle),
         :ok <- :zip.zip_close(zip_handle),
         {:ok, metadata} <- parse_xml_simple(xml_content) do
      {:ok, metadata}
    else
      false -> {:error, :file_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Get mod display name from metadata.
  """
  def get_name(metadata), do: Map.get(metadata, :name, "Unknown Mod")

  @doc """
  Get mod author from metadata.
  """
  def get_author(metadata), do: Map.get(metadata, :author, "Unknown")

  @doc """
  Get asset type from metadata.
  """
  def get_asset_type(metadata), do: Map.get(metadata, :asset_type, "unknown")

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp read_mds_from_zip(zip_handle) do
    case :zip.zip_get(to_charlist(@mdf_filename), zip_handle) do
      {:ok, {_filename, content}} -> 
        {:ok, content}
      
      {:error, _} ->
        Logger.warning("[MDF] #{@mdf_filename} not found in ZIP")
        {:error, :mds_not_found}
    end
  end

  defp parse_xml_simple(xml_content) when is_binary(xml_content) do
    try do
      # Simple regex-based parsing for demo purposes
      name = extract_text(xml_content, "<name>(.*?)</name>")
      author = extract_text(xml_content, "<author>(.*?)</author>")
      version = extract_text(xml_content, "<version>(.*?)</version>")
      asset_type = extract_text(xml_content, "<game_asset_type>(.*?)</game_asset_type>")
      asset_id = extract_text(xml_content, "<asset_id>(.*?)</asset_id>")
      
      metadata = %{
        name: name || "Unknown Mod",
        author: author || "Unknown",
        version: version || "1.0.0",
        asset_type: asset_type || "unknown",
        asset_id: asset_id || "unknown"
      }
      
      Logger.info("[MDF] Parsed mod: #{metadata.name} by #{metadata.author}")
      {:ok, metadata}
    rescue
      e -> 
        Logger.error("[MDF] Failed to parse XML: #{inspect(e)}")
        {:error, :parse_failed}
    end
  end

  defp extract_text(xml, pattern) do
    case Regex.run(~r/#{pattern}/s, xml) do
      [_, text] -> String.trim(text)
      _ -> nil
    end
  end
end
