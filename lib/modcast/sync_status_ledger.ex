defmodule Modcast.SyncStatusLedger do
  @moduledoc """
  Sync Status Ledger - Stores and manages all game entities.
  Provides synchronization and conflict resolution between peers.
  
  The SSL maintains a distributed registry of all entities in the game session,
  ensuring that all players have a consistent view of:
  - Which entities exist
  - Who owns each entity
  - Which mod (hash) each entity uses
  - Entity creation and transfer history
  
  ## Conflict Resolution
  
  When merging ledgers from different peers, conflicts are resolved using
  "last write wins" (LWW) based on timestamps. The entity with the most recent
  `last_transferred` or `created_at` timestamp takes precedence.
  
  """
  
  alias Modcast.GameState.Entity
  require Logger
  
  defstruct entities: %{}, version: 0
  
  @type t :: %__MODULE__{
    entities: %{String.t() => Entity.t()},
    version: non_neg_integer()
  }
  
  @doc """
  Creates a new empty ledger.
  """
  def new, do: %__MODULE__{entities: %{}, version: 0}
  
  @doc """
  Adds or updates an entity in the ledger.
  Increments the version counter for change tracking.
  """
  def put_entity(%__MODULE__{} = ledger, %Entity{} = entity) do
    %{ledger | 
      entities: Map.put(ledger.entities, entity.entity_id, entity),
      version: ledger.version + 1
    }
  end
  
  @doc """
  Retrieves an entity by its ID.
  Returns nil if the entity doesn't exist.
  """
  def get_entity(%__MODULE__{} = ledger, entity_id) when is_binary(entity_id) do
    Map.get(ledger.entities, entity_id)
  end
  
  @doc """
  Removes an entity from the ledger.
  """
  def delete_entity(%__MODULE__{} = ledger, entity_id) when is_binary(entity_id) do
    %{ledger | 
      entities: Map.delete(ledger.entities, entity_id),
      version: ledger.version + 1
    }
  end
  
  @doc """
  Returns all entities owned by a specific player.
  """
  def get_entities_by_player(%__MODULE__{} = ledger, player_id) when is_binary(player_id) do
    ledger.entities
    |> Map.values()
    |> Enum.filter(&(&1.player_id == player_id))
  end
  
  @doc """
  Returns all entities using a specific mod (by hash).
  """
  def get_entities_by_hash(%__MODULE__{} = ledger, hash) when is_binary(hash) do
    ledger.entities
    |> Map.values()
    |> Enum.filter(&(&1.hash == hash))
  end
  
  @doc """
  Returns all entities of a specific asset type.
  """
  def get_entities_by_asset(%__MODULE__{} = ledger, asset_id) when is_binary(asset_id) do
    ledger.entities
    |> Map.values()
    |> Enum.filter(&(&1.asset_id == asset_id))
  end
  
  @doc """
  Returns all entities in the ledger as a list.
  """
  def list_entities(%__MODULE__{} = ledger) do
    Map.values(ledger.entities)
  end
  
  @doc """
  Returns the number of entities in the ledger.
  """
  def count_entities(%__MODULE__{} = ledger) do
    map_size(ledger.entities)
  end
  
  @doc """
  Checks if an entity exists in the ledger.
  """
  def has_entity?(%__MODULE__{} = ledger, entity_id) when is_binary(entity_id) do
    Map.has_key?(ledger.entities, entity_id)
  end
  
  @doc """
  Transfers entity ownership from one player to another.
  Returns {:ok, updated_ledger} or {:error, reason}.
  """
  def transfer_entity(%__MODULE__{} = ledger, entity_id, new_player_id) 
      when is_binary(entity_id) and is_binary(new_player_id) do
    case get_entity(ledger, entity_id) do
      nil ->
        {:error, :entity_not_found}
      
      entity ->
        transferred_entity = Entity.transfer(entity, new_player_id)
        {:ok, put_entity(ledger, transferred_entity)}
    end
  end
  
  @doc """
  Merges two ledgers using Last Write Wins (LWW) conflict resolution.
  
  For each entity:
  - If entity exists in only one ledger, it's included
  - If entity exists in both, the one with the most recent timestamp wins
  - Version is set to the maximum of both versions
  """
  def merge(%__MODULE__{} = local, %__MODULE__{} = remote) do
    merged_entities = 
      Map.merge(local.entities, remote.entities, fn _entity_id, local_entity, remote_entity ->
        resolve_conflict(local_entity, remote_entity)
      end)
    
    %__MODULE__{
      entities: merged_entities,
      version: max(local.version, remote.version) + 1
    }
  end
  
  # Resolves conflicts between two versions of the same entity
  # Uses Last Write Wins (LWW) based on timestamps
  defp resolve_conflict(local_entity, remote_entity) do
    local_time = get_latest_timestamp(local_entity)
    remote_time = get_latest_timestamp(remote_entity)
    
    case DateTime.compare(local_time, remote_time) do
      :gt -> local_entity
      :lt -> remote_entity
      :eq -> 
        # If timestamps are equal, use entity_id as tiebreaker for deterministic resolution
        if local_entity.entity_id >= remote_entity.entity_id do
          local_entity
        else
          remote_entity
        end
    end
  end
  
  # Gets the most recent timestamp from an entity
  defp get_latest_timestamp(%Entity{} = entity) do
    if entity.last_transferred do
      entity.last_transferred
    else
      entity.created_at
    end
  end
  
  @doc """
  Returns statistics about the ledger.
  """
  def stats(%__MODULE__{} = ledger) do
    entities = list_entities(ledger)
    
    players = entities |> Enum.map(& &1.player_id) |> Enum.uniq()
    hashes = entities |> Enum.map(& &1.hash) |> Enum.uniq()
    assets = entities |> Enum.map(& &1.asset_id) |> Enum.uniq()
    
    entities_by_player = Enum.frequencies_by(entities, & &1.player_id)
    entities_by_hash = Enum.frequencies_by(entities, & &1.hash)
    entities_by_asset = Enum.frequencies_by(entities, & &1.asset_id)
    
    %{
      total_entities: count_entities(ledger),
      unique_players: length(players),
      unique_mods: length(hashes),
      unique_assets: length(assets),
      entities_by_player: entities_by_player,
      entities_by_hash: entities_by_hash,
      entities_by_asset: entities_by_asset,
      version: ledger.version
    }
  end
  
  @doc """
  Converts the ledger to a map suitable for JSON serialization.
  """
  def to_map(%__MODULE__{} = ledger) do
    %{
      entities: Enum.map(ledger.entities, fn {id, entity} ->
        {id, entity_to_map(entity)}
      end) |> Map.new(),
      version: ledger.version
    }
  end
  
  @doc """
  Creates a ledger from a map (deserialization).
  """
  def from_map(%{entities: entities_map, version: version}) do
    entities = 
      Enum.map(entities_map, fn {id, entity_map} ->
        {id, entity_from_map(entity_map)}
      end)
      |> Map.new()
    
    %__MODULE__{entities: entities, version: version}
  end
  def from_map(%{"entities" => entities_map, "version" => version}) do
    from_map(%{entities: entities_map, version: version})
  end
  
  # Helper to convert Entity struct to map
  defp entity_to_map(%Entity{} = entity) do
    %{
      entity_id: entity.entity_id,
      asset_id: entity.asset_id,
      hash: entity.hash,
      player_id: entity.player_id,
      created_at: DateTime.to_iso8601(entity.created_at),
      last_transferred: entity.last_transferred && DateTime.to_iso8601(entity.last_transferred)
    }
  end
  
  # Helper to convert map to Entity struct
  defp entity_from_map(entity_map) do
    %Entity{
      entity_id: entity_map[:entity_id] || entity_map["entity_id"],
      asset_id: entity_map[:asset_id] || entity_map["asset_id"],
      hash: entity_map[:hash] || entity_map["hash"],
      player_id: entity_map[:player_id] || entity_map["player_id"],
      created_at: parse_datetime(entity_map[:created_at] || entity_map["created_at"]),
      last_transferred: parse_datetime(entity_map[:last_transferred] || entity_map["last_transferred"])
    }
  end
  
  defp parse_datetime(nil), do: nil
  defp parse_datetime(datetime_string) when is_binary(datetime_string) do
    case DateTime.from_iso8601(datetime_string) do
      {:ok, datetime, _offset} -> datetime
      {:error, _} -> DateTime.utc_now()
    end
  end
  defp parse_datetime(%DateTime{} = datetime), do: datetime
  
  @doc """
  Validates the ledger for consistency.
  Returns {:ok, ledger} or {:error, reasons}.
  """
  def validate(%__MODULE__{} = ledger) do
    errors = []
    
    # Check for duplicate entity_ids (should not happen, but check anyway)
    entity_ids = ledger.entities |> Map.keys()
    duplicate_ids = entity_ids -- Enum.uniq(entity_ids)
    
    errors = if length(duplicate_ids) > 0 do
      ["Duplicate entity IDs found: #{inspect(duplicate_ids)}" | errors]
    else
      errors
    end
    
    # Validate each entity
    entity_errors = 
      ledger.entities
      |> Map.values()
      |> Enum.flat_map(&validate_entity/1)
    
    all_errors = errors ++ entity_errors
    
    if length(all_errors) > 0 do
      {:error, all_errors}
    else
      {:ok, ledger}
    end
  end
  
  defp validate_entity(%Entity{} = entity) do
    errors = []
    
    errors = if is_nil(entity.entity_id) or entity.entity_id == "" do
      ["Entity has empty entity_id" | errors]
    else
      errors
    end
    
    errors = if is_nil(entity.asset_id) or entity.asset_id == "" do
      ["Entity #{entity.entity_id} has empty asset_id" | errors]
    else
      errors
    end
    
    errors = if is_nil(entity.hash) or entity.hash == "" do
      ["Entity #{entity.entity_id} has empty hash" | errors]
    else
      errors
    end
    
    errors = if is_nil(entity.player_id) or entity.player_id == "" do
      ["Entity #{entity.entity_id} has empty player_id" | errors]
    else
      errors
    end
    
    errors = if is_nil(entity.created_at) do
      ["Entity #{entity.entity_id} has nil created_at" | errors]
    else
      errors
    end
    
    errors
  end
  
  @doc """
  Clears all entities from the ledger.
  """
  def clear(%__MODULE__{} = ledger) do
    %__MODULE__{entities: %{}, version: ledger.version + 1}
  end
end