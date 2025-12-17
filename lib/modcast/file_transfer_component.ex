defmodule Modcast.FileTransferComponent do
  @moduledoc "Handles complete file transfers for small mod files"
  require Logger
  alias Modcast.Utils

  @max_file_size 10 * 1024 * 1024

  def send_file(socket, file_path, file_hash) do
    case File.read(file_path) do
      {:ok, file_data} ->
        file_size = byte_size(file_data)
        
        if file_size > @max_file_size do
          Logger.warning("[FTC] File too large: #{Path.basename(file_path)}")
          {:error, :file_too_large}
        else
          computed_hash = Utils.compute_data_hash(file_data)
          
          if computed_hash != file_hash do
            Logger.error("[FTC] Local hash mismatch for #{Path.basename(file_path)}")
            {:error, :local_hash_mismatch}
          else
            message = {:mod_file, file_hash, Path.basename(file_path), file_data}
            :gen_tcp.send(socket, encode_message(message))
            Logger.info("[FTC] Sent #{Path.basename(file_path)} (#{file_size} bytes)")
            {:ok, file_size}
          end
        end
      
      {:error, reason} ->
        Logger.error("[FTC] Failed to read #{file_path}: #{inspect(reason)}")
        {:error, :file_read_error}
    end
  end

  def receive_file(mods_folder, file_hash, filename, file_data) do
    computed_hash = Utils.compute_data_hash(file_data)
    
    if computed_hash != file_hash do
      Logger.error("[FTC] Hash mismatch: expected #{String.slice(file_hash, 0, 8)}..., got #{String.slice(computed_hash, 0, 8)}...")
      {:error, :hash_mismatch}
    else
      case Utils.find_file_by_hash(mods_folder, file_hash) do
        existing_path when not is_nil(existing_path) ->
          Logger.info("[FTC] File already exists: #{Path.basename(existing_path)}")
          {:ok, existing_path, :already_exists}
        
        nil ->
          unique_name = Utils.unique_filename(mods_folder, filename)
          file_path = Path.join(mods_folder, unique_name)
          
          case File.write(file_path, file_data) do
            :ok ->
              final_hash = Utils.compute_file_hash(file_path)
              if final_hash != file_hash do
                File.rm!(file_path)
                {:error, :write_integrity_failed}
              else
                Logger.info("[FTC] Saved #{unique_name} (#{byte_size(file_data)} bytes)")
                {:ok, file_path, :downloaded}
              end
            
            {:error, reason} ->
              Logger.error("[FTC] Failed to save #{unique_name}: #{inspect(reason)}")
              {:error, :file_write_error}
          end
      end
    end
  end

  def handle_mod_request(file_hash, filename, requestor_id, socket, state) do
    case Map.get(state.mod_metadata, file_hash) do
      %{file_path: path} ->
        if File.exists?(path) do
          Task.start(fn ->
            case send_file(socket, path, file_hash) do
              {:ok, size} -> 
                Logger.info("[FTC] Sent #{filename} to #{requestor_id} (#{size} bytes)")
              {:error, reason} -> 
                Logger.error("[FTC] Failed to send #{filename} to #{requestor_id}: #{inspect(reason)}")
            end
          end)
          :ok
        else
          Logger.warning("[FTC] File not found for hash #{String.slice(file_hash, 0, 8)}...")
          :error
        end
        
      _ ->
        Logger.warning("[FTC] Requested mod not available: #{String.slice(file_hash, 0, 8)}...")
        :error
    end
  end

  def handle_mod_received(file_hash, filename, file_data, state) do
    case receive_file(state.mods_folder, file_hash, filename, file_data) do
      {:ok, file_path, :downloaded} ->
        mod_data = %{
          filename: Path.basename(file_path),
          display_name: Utils.get_mod_display_name(filename),
          file_path: file_path,
          ready_at: DateTime.utc_now()
        }
        
        new_available = MapSet.put(state.available_mods, file_hash)
        new_metadata = Map.put(state.mod_metadata, file_hash, mod_data)
        new_state = %{state | available_mods: new_available, mod_metadata: new_metadata}
        
        if state.callback_handler do
          apply(state.callback_handler, :on_mod_ready, [file_hash, mod_data])
          if MapSet.subset?(state.required_mods, new_available) do
            apply(state.callback_handler, :on_all_mods_ready, [])
          end
        end
        
        Logger.info("[FTC] Processed #{filename} successfully")
        {:ok, new_state}
      
      {:ok, _, :already_exists} ->
        if not MapSet.member?(state.available_mods, file_hash) do
          mod_data = Map.get(state.mod_metadata, file_hash) || %{
            filename: filename,
            display_name: Utils.get_mod_display_name(filename),
            file_path: Utils.find_file_by_hash(state.mods_folder, file_hash),
            ready_at: DateTime.utc_now()
          }
          
          new_available = MapSet.put(state.available_mods, file_hash)
          new_metadata = Map.put(state.mod_metadata, file_hash, mod_data)
          new_state = %{state | available_mods: new_available, mod_metadata: new_metadata}
          
          if state.callback_handler do
            apply(state.callback_handler, :on_mod_ready, [file_hash, mod_data])
          end
          
          {:ok, new_state}
        else
          {:ok, state}
        end
      
      {:error, :hash_mismatch} ->
        if state.callback_handler do
          apply(state.callback_handler, :on_mod_hash_mismatch, 
                [file_hash, Utils.compute_data_hash(file_data)])
        end
        {:error, :hash_mismatch, state}
      
      {:error, reason} ->
        Logger.error("[FTC] Failed to process mod: #{inspect(reason)}")
        {:error, reason, state}
    end
  end

  defp encode_message(message), do: :erlang.term_to_binary(message)
end