defmodule Modcast.Utils do
  @moduledoc """
  Utility functions for file operations, hashing, and naming.
  """
  
  def compute_file_hash(file_path) do
    try do
      File.stream!(file_path, [], 65536)
      |> Enum.reduce(:crypto.hash_init(:md5), fn chunk, acc -> :crypto.hash_update(acc, chunk) end)
      |> :crypto.hash_final()
      |> Base.encode16(case: :lower)
    rescue
      _ -> nil
    end
  end
  
  def compute_data_hash(data), do: :crypto.hash(:md5, data) |> Base.encode16(case: :lower)
  def validate_file_hash(file_path, expected_hash), do: compute_file_hash(file_path) == expected_hash
  
  def find_file_by_hash(directory, target_hash) do
    if File.dir?(directory) do
      directory
      |> File.ls!()
      |> Stream.filter(&String.ends_with?(&1, ".zip"))
      |> Stream.map(&Path.join(directory, &1))
      |> Stream.filter(&File.regular?/1)
      |> Enum.find(fn path -> compute_file_hash(path) == target_hash end)
    end
  end
  
  def unique_filename(directory, base_filename) do
    base = Path.rootname(base_filename)
    ext = Path.extname(base_filename)
    find_unique_name(directory, base, ext, 0)
  end
  
  defp find_unique_name(dir, base, ext, counter) do
    candidate = if counter == 0, do: "#{base}#{ext}", else: "#{base}_#{counter}#{ext}"
    candidate_path = Path.join(dir, candidate)
    if File.exists?(candidate_path), do: find_unique_name(dir, base, ext, counter + 1), else: candidate
  end
  
  def get_mod_display_name(filename) do
    filename
    |> Path.rootname(".zip")
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end
  
  def generate_peer_id, do: :crypto.strong_rand_bytes(16) |> Base.encode64() |> String.slice(0, 16)
end