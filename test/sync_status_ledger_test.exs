defmodule Modcast.SyncStatusLedgerTest do
  use ExUnit.Case, async: true
  
  alias Modcast.SyncStatusLedger
  alias Modcast.GameState.Entity
  
  doctest Modcast.SyncStatusLedger
  
  describe "new/0" do
    test "creates an empty ledger" do
      ledger = SyncStatusLedger.new()
      
      assert ledger.entities == %{}
      assert ledger.version == 0
    end
  end
  
  describe "put_entity/2" do
    test "adds a new entity to the ledger" do
      ledger = SyncStatusLedger.new()
      entity = Entity.new("sword_1", "weapon", "abc123", "Player1")
      
      updated = SyncStatusLedger.put_entity(ledger, entity)
      
      assert SyncStatusLedger.has_entity?(updated, "sword_1")
      assert updated.version == 1
    end
    
    test "updates an existing entity" do
      ledger = SyncStatusLedger.new()
      entity1 = Entity.new("sword_1", "weapon", "abc123", "Player1")
      entity2 = Entity.new("sword_1", "weapon", "def456", "Player2")
      
      updated = ledger
      |> SyncStatusLedger.put_entity(entity1)
      |> SyncStatusLedger.put_entity(entity2)
      
      retrieved = SyncStatusLedger.get_entity(updated, "sword_1")
      assert retrieved.player_id == "Player2"
      assert retrieved.hash == "def456"
      assert updated.version == 2
    end
  end
  
  describe "get_entity/2" do
    test "retrieves an existing entity" do
      ledger = SyncStatusLedger.new()
      entity = Entity.new("sword_1", "weapon", "abc123", "Player1")
      
      updated = SyncStatusLedger.put_entity(ledger, entity)
      retrieved = SyncStatusLedger.get_entity(updated, "sword_1")
      
      assert retrieved.entity_id == "sword_1"
      assert retrieved.player_id == "Player1"
    end
    
    test "returns nil for non-existent entity" do
      ledger = SyncStatusLedger.new()
      
      assert SyncStatusLedger.get_entity(ledger, "nonexistent") == nil
    end
  end
  
  describe "delete_entity/2" do
    test "removes an entity from the ledger" do
      ledger = SyncStatusLedger.new()
      entity = Entity.new("sword_1", "weapon", "abc123", "Player1")
      
      updated = ledger
      |> SyncStatusLedger.put_entity(entity)
      |> SyncStatusLedger.delete_entity("sword_1")
      
      assert not SyncStatusLedger.has_entity?(updated, "sword_1")
      assert updated.version == 2
    end
  end
  
  describe "get_entities_by_player/2" do
    test "returns all entities owned by a player" do
      ledger = SyncStatusLedger.new()
      entity1 = Entity.new("sword_1", "weapon", "abc123", "Player1")
      entity2 = Entity.new("shield_1", "armor", "def456", "Player1")
      entity3 = Entity.new("sword_2", "weapon", "ghi789", "Player2")
      
      updated = ledger
      |> SyncStatusLedger.put_entity(entity1)
      |> SyncStatusLedger.put_entity(entity2)
      |> SyncStatusLedger.put_entity(entity3)
      
      player1_entities = SyncStatusLedger.get_entities_by_player(updated, "Player1")
      
      assert length(player1_entities) == 2
      assert Enum.all?(player1_entities, &(&1.player_id == "Player1"))
    end
    
    test "returns empty list for player with no entities" do
      ledger = SyncStatusLedger.new()
      
      assert SyncStatusLedger.get_entities_by_player(ledger, "Player1") == []
    end
  end
  
  describe "get_entities_by_hash/2" do
    test "returns all entities using a specific mod" do
      ledger = SyncStatusLedger.new()
      entity1 = Entity.new("sword_1", "weapon", "abc123", "Player1")
      entity2 = Entity.new("sword_2", "weapon", "abc123", "Player2")
      entity3 = Entity.new("shield_1", "armor", "def456", "Player1")
      
      updated = ledger
      |> SyncStatusLedger.put_entity(entity1)
      |> SyncStatusLedger.put_entity(entity2)
      |> SyncStatusLedger.put_entity(entity3)
      
      abc_entities = SyncStatusLedger.get_entities_by_hash(updated, "abc123")
      
      assert length(abc_entities) == 2
      assert Enum.all?(abc_entities, &(&1.hash == "abc123"))
    end
  end
  
  describe "get_entities_by_asset/2" do
    test "returns all entities of a specific asset type" do
      ledger = SyncStatusLedger.new()
      entity1 = Entity.new("sword_1", "weapon", "abc123", "Player1")
      entity2 = Entity.new("sword_2", "weapon", "def456", "Player2")
      entity3 = Entity.new("shield_1", "armor", "ghi789", "Player1")
      
      updated = ledger
      |> SyncStatusLedger.put_entity(entity1)
      |> SyncStatusLedger.put_entity(entity2)
      |> SyncStatusLedger.put_entity(entity3)
      
      weapons = SyncStatusLedger.get_entities_by_asset(updated, "weapon")
      
      assert length(weapons) == 2
      assert Enum.all?(weapons, &(&1.asset_id == "weapon"))
    end
  end
  
  describe "transfer_entity/3" do
    test "transfers entity ownership successfully" do
      ledger = SyncStatusLedger.new()
      entity = Entity.new("sword_1", "weapon", "abc123", "Player1")
      
      updated = SyncStatusLedger.put_entity(ledger, entity)
      {:ok, transferred} = SyncStatusLedger.transfer_entity(updated, "sword_1", "Player2")
      
      transferred_entity = SyncStatusLedger.get_entity(transferred, "sword_1")
      assert transferred_entity.player_id == "Player2"
      assert transferred_entity.last_transferred != nil
    end
    
    test "returns error for non-existent entity" do
      ledger = SyncStatusLedger.new()
      
      result = SyncStatusLedger.transfer_entity(ledger, "nonexistent", "Player2")
      
      assert result == {:error, :entity_not_found}
    end
  end
  
  describe "count_entities/1" do
    test "counts entities correctly" do
      ledger = SyncStatusLedger.new()
      entity1 = Entity.new("sword_1", "weapon", "abc123", "Player1")
      entity2 = Entity.new("shield_1", "armor", "def456", "Player1")
      
      assert SyncStatusLedger.count_entities(ledger) == 0
      
      updated = ledger
      |> SyncStatusLedger.put_entity(entity1)
      |> SyncStatusLedger.put_entity(entity2)
      
      assert SyncStatusLedger.count_entities(updated) == 2
    end
  end
  
  describe "merge/2" do
    test "merges two ledgers with different entities" do
      entity1 = Entity.new("sword_1", "weapon", "abc123", "Player1")
      entity2 = Entity.new("shield_1", "armor", "def456", "Player2")
      
      ledger1 = SyncStatusLedger.new() |> SyncStatusLedger.put_entity(entity1)
      ledger2 = SyncStatusLedger.new() |> SyncStatusLedger.put_entity(entity2)
      
      merged = SyncStatusLedger.merge(ledger1, ledger2)
      
      assert SyncStatusLedger.count_entities(merged) == 2
      assert SyncStatusLedger.has_entity?(merged, "sword_1")
      assert SyncStatusLedger.has_entity?(merged, "shield_1")
    end
    
    test "resolves conflicts using last write wins" do
      # Create entity with older timestamp
      entity_old = Entity.new("sword_1", "weapon", "abc123", "Player1")
      
      # Wait a bit and create newer entity
      Process.sleep(10)
      entity_new = Entity.new("sword_1", "weapon", "def456", "Player2")
      
      ledger1 = SyncStatusLedger.new() |> SyncStatusLedger.put_entity(entity_old)
      ledger2 = SyncStatusLedger.new() |> SyncStatusLedger.put_entity(entity_new)
      
      merged = SyncStatusLedger.merge(ledger1, ledger2)
      
      result = SyncStatusLedger.get_entity(merged, "sword_1")
      # Newer entity should win
      assert result.player_id == "Player2"
      assert result.hash == "def456"
    end
  end
  
  describe "stats/1" do
    test "returns comprehensive statistics" do
      ledger = SyncStatusLedger.new()
      entity1 = Entity.new("sword_1", "weapon", "abc123", "Player1")
      entity2 = Entity.new("sword_2", "weapon", "abc123", "Player2")
      entity3 = Entity.new("shield_1", "armor", "def456", "Player1")
      
      updated = ledger
      |> SyncStatusLedger.put_entity(entity1)
      |> SyncStatusLedger.put_entity(entity2)
      |> SyncStatusLedger.put_entity(entity3)
      
      stats = SyncStatusLedger.stats(updated)
      
      assert stats.total_entities == 3
      assert stats.unique_players == 2
      assert stats.unique_mods == 2
      assert stats.unique_assets == 2
      assert stats.entities_by_player["Player1"] == 2
      assert stats.entities_by_player["Player2"] == 1
      assert stats.entities_by_hash["abc123"] == 2
      assert stats.version == 3
    end
  end
  
  describe "to_map/1 and from_map/1" do
    test "serializes and deserializes ledger correctly" do
      ledger = SyncStatusLedger.new()
      entity1 = Entity.new("sword_1", "weapon", "abc123", "Player1")
      entity2 = Entity.new("shield_1", "armor", "def456", "Player2")
      
      updated = ledger
      |> SyncStatusLedger.put_entity(entity1)
      |> SyncStatusLedger.put_entity(entity2)
      
      # Serialize
      map = SyncStatusLedger.to_map(updated)
      
      assert is_map(map)
      assert map.version == 2
      assert map_size(map.entities) == 2
      
      # Deserialize
      restored = SyncStatusLedger.from_map(map)
      
      assert SyncStatusLedger.count_entities(restored) == 2
      assert SyncStatusLedger.has_entity?(restored, "sword_1")
      assert SyncStatusLedger.has_entity?(restored, "shield_1")
      assert restored.version == 2
    end
    
    test "handles string keys from JSON" do
      map_with_strings = %{
        "entities" => %{
          "sword_1" => %{
            "entity_id" => "sword_1",
            "asset_id" => "weapon",
            "hash" => "abc123",
            "player_id" => "Player1",
            "created_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
            "last_transferred" => nil
          }
        },
        "version" => 1
      }
      
      ledger = SyncStatusLedger.from_map(map_with_strings)
      
      assert SyncStatusLedger.count_entities(ledger) == 1
      assert SyncStatusLedger.has_entity?(ledger, "sword_1")
    end
  end
  
  describe "validate/1" do
    test "validates a correct ledger" do
      ledger = SyncStatusLedger.new()
      entity = Entity.new("sword_1", "weapon", "abc123", "Player1")
      updated = SyncStatusLedger.put_entity(ledger, entity)
      
      assert {:ok, ^updated} = SyncStatusLedger.validate(updated)
    end
    
    test "detects invalid entities" do
      # Create invalid entity manually (bypassing constructor)
      invalid_entity = %Entity{
        entity_id: "",
        asset_id: "weapon",
        hash: "abc123",
        player_id: "Player1",
        created_at: DateTime.utc_now(),
        last_transferred: nil
      }
      
      ledger = %SyncStatusLedger{
        entities: %{"" => invalid_entity},
        version: 1
      }
      
      assert {:error, errors} = SyncStatusLedger.validate(ledger)
      assert length(errors) > 0
    end
  end
  
  describe "clear/1" do
    test "removes all entities" do
      ledger = SyncStatusLedger.new()
      entity1 = Entity.new("sword_1", "weapon", "abc123", "Player1")
      entity2 = Entity.new("shield_1", "armor", "def456", "Player2")
      
      updated = ledger
      |> SyncStatusLedger.put_entity(entity1)
      |> SyncStatusLedger.put_entity(entity2)
      
      cleared = SyncStatusLedger.clear(updated)
      
      assert SyncStatusLedger.count_entities(cleared) == 0
      assert cleared.version == 3  # Version increments
    end
  end
end
