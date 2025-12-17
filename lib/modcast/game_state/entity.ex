defmodule Modcast.GameState.Entity do
  @moduledoc """
  Entity structure representing an in-game object tied to a mod.
  Entities are immutable except for player_id when transferred.
  """
  
  @enforce_keys [:entity_id, :asset_id, :hash, :player_id]
  defstruct [
    :entity_id,
    :asset_id,
    :hash,
    :player_id,
    :created_at,
    :last_transferred
  ]
  
  @type t :: %__MODULE__{
    entity_id: String.t(),
    asset_id: String.t(),
    hash: String.t(),
    player_id: String.t(),
    created_at: DateTime.t(),
    last_transferred: DateTime.t() | nil
  }
  
  def new(entity_id, asset_id, hash, player_id) do
    %__MODULE__{
      entity_id: entity_id,
      asset_id: asset_id,
      hash: hash,
      player_id: player_id,
      created_at: DateTime.utc_now(),
      last_transferred: nil
    }
  end
  
  def transfer(entity, new_player_id) do
    %{entity | 
      player_id: new_player_id,
      last_transferred: DateTime.utc_now()
    }
  end
  
  def belongs_to?(entity, player_id), do: entity.player_id == player_id
end