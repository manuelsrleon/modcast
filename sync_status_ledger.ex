defmodule Modcast.SyncStatusLedger do
  @moduledoc """
  Sync Status Ledger - Stores and manages all game entities.
  Provides synchronization and conflict resolution between peers.
  """
  
  alias Modcast.GameState.Entity
  
  defstruct entities: %{}
  
  @type t :: %__MODULE__{entities: %{String.t() => Entity.t()}}
  
  def new, do: %__MODULE__{}
  
  def put_entity(ledger, %Entity{} = entity) do
    %{ledger | entities: Map.put(ledger.entities, entity.entity_id, entity)}
  end
  
  def get_entity(ledger, entity_id), do: Map.get(ledger.entities, entity_id)
  
  def delete_entity(ledger, entity_id), do: %{ledger | entities: Map.delete(ledger.entities, entity_id)}
  
  def get_entities_by_player(ledger, player_id) do
    ledger.entities
    |> Map.values()
    |> Enum.filter(&(&1.player_id == player_id))
  end
  
  def get_entities_by_hash(ledger, hash) do
    ledger.entities
    |> Map.values()
    |> Enum.filter(&(&1.hash == hash))
  end
  
  def list_entities(ledger), do: Map.values(ledger.entities)
  
  def merge(local, remote), do: %__MODULE__{entities: Map.merge(local.entities, remote.entities)}
end