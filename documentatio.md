# Modcast - P2P Mod Sharing System

## What is Modcast?

**Modcast** is a proof-of-concept for an Elixir-based, platform-agnostic P2P mod sharing system for video games. Developed as part of the Software Architecture course at FIC (UDC).

Modcast provides a decentralized, hands-free approach to syncing cosmetic modifications across clients in P2P-hosted multiplayer matches, coop games, or any multiplayer game with custom content support.

## Why P2P?

After analyzing architectural alternatives, we chose P2P for several key reasons:

- **No central server costs**: Each player acts as both client and server
- **Resilience**: No single point of failure
- **Privacy**: Direct communication between players
- **Low latency**: Direct peer-to-peer connections

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                         GAME ENGINE                             │
│                    (Godot, Unity, Unreal...)                    │
└────────────────────────┬────────────────────────────────────────┘
                         │ TCP/JSON (port 5050)
                         │
┌────────────────────────▼────────────────────────────────────────┐
│                    MSAPI (Modcast SyncAPI)                      │
│              Game Engine Interface & Command Parser             │
└────────────────────────┬────────────────────────────────────────┘
                         │
┌────────────────────────▼────────────────────────────────────────┐
│             GSC (Game State Component)                          │
│         Core P2P State Manager & Orchestrator                   │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │  • Session Management                                     │  │
│  │  • Player Registry (players, peers, connections)          │  │
│  │  • Mod Selection & Announcement                           │  │
│  │  • Required Mods Tracking                                 │  │
│  │  • State Persistence (via Persistence module)             │  │
│  └───────────────────────────────────────────────────────────┘  │
└──────┬──────────────────────┬──────────────────┬────────────────┘
       │                      │                  │
       ▼                      ▼                  ▼
┌─────────────┐    ┌─────────────────┐   ┌──────────────┐
│     SSL     │    │       FTC       │   │   NETWORK    │
│   (Ledger)  │    │ (File Transfer) │   │   (TCP/IP)   │
└─────────────┘    └─────────────────┘   └──────────────┘
       │                      │                  │
       ▼                      ▼                  ▼
┌─────────────────────────────────────────────────────────┐
│              PERSISTENT STORAGE (not in use)            │
│  1. ./mods/  - Mod files (shared across sessions)       │
│  2. ./data/  - DETS session state (crash recovery)      │
└─────────────────────────────────────────────────────────┘
```

---

## Core Components

Modcast consists of 7 main components:

1. **MSAPI** - Game engine interface (TCP/JSON API)
2. **GSC** - Game State Component (P2P orchestration)
3. **SSL** - Sync Status Ledger (entity registry)
4. **FTC** - File Transfer Component (mod transfers)
5. **Persistence** - DETS-based state storage (crash recovery) (not in use)
6. **MMF** - Modcast Mod File format (.zip mods)
7. **Storage** - File system persistence (./mods, ./data)

---

### 1. MSAPI (Modcast SyncAPI)

**Purpose**: Interface between game engine and Modcast system

**Location**: `lib/modcast/msapi.ex`

**Responsibilities**:
- Listens on TCP port 5050 for game engine connections
- Parses JSON commands from the game
- Sends events back to the game (mod ready, entity created, etc.)
- Acts as the single entry point for all game interactions

**Communication Protocol**:
```json
// Command from game → Modcast
{"action": "select_mods", "player": "Player1", "hashes": ["abc123", "def456"]}

// Response from Modcast → game
{"response": "ok", "message": "Mods selected. Missing: []"}

// Event from Modcast → game
{"event": "mod_ready", "data": {"hash": "abc123", "filename": "sword.zip"}}
```

**Available Commands**:
| Command | Parameters | Description |
|---------|-----------|-------------|
| `start_session` | session, player | Create new P2P session (host) |
| `join_session` | session, player, host | Join existing session |
| `select_mods` | player, hashes | Select mods for this session |
| `start_game` | - | Lock mods and start game |
| `register_entity` | entity, asset, player, hash | Create in-game entity with mod |
| `transfer_entity` | entity, new_player | Transfer entity ownership |
| `leave_session` | session | Disconnect from session |
| `list_available_mods` | - | Get list of mods in local folder |

**Events Sent to Game**:
- `mod_ready`: A mod has been downloaded and is ready
- `all_mods_ready`: All required mods are available
- `game_started`: Game has started
- `entity_created`: New entity registered
- `entity_transferred`: Entity ownership changed

---

### 2. GSC (Game State Component)

**Purpose**: Core P2P orchestration and state management

**Location**: `lib/modcast/game_state/game_state_component.ex`

**Key State Variables**:
```elixir
%GameStateComponent{
  session_id: "unique_session_123",           # Current session
  local_player_id: "Player1",                 # This player's ID
  phase: :loading | :in_game | :idle,        # Session phase
  
  available_mods: MapSet<hash>,               # Mods in ./mods folder
  selected_mods: MapSet<hash>,                # Mods I chose for this session
  required_mods: MapSet<hash>,                # All mods anyone needs
  
  players: %{player_id => player_info},       # All players in session
  peers: %{peer_id => peer_info},             # Network connections
  player_selections: %{player_id => mods},    # What each player selected
  
  ssl: SyncStatusLedger,                      # Entity registry
  mod_metadata: %{hash => mod_data}           # File info for each mod
}
```

**Session Lifecycle**:

```
┌──────┐  select_mods()    ┌──────┐  start/join_session()  ┌─────────┐
│ IDLE │─────────────────>│ IDLE │──────────────────────>│ LOADING │
└──────┘  (pre-selection)  └──────┘  (with selected mods)  └─────────┘
                                                                 │
                                                                 │ start_game()
                                                                 ▼
   ┌──────┐                                                 ┌─────────┐
   │ IDLE │◀────────────────────────────────────────────────│ IN_GAME │
   └──────┘              leave_session()                    └─────────┘
```

**Mod Selection Flow**:
```
1. Scan local folder → available_mods
2. PRE-SELECT mods in :idle (before session)
   - select_mods([hash1, hash2])
   - Stores locally, no announcement yet
3. Join/start session (validates selection exists)
4. Announce ONLY selected_mods to peers ✓
5. Calculate required_mods (union of selections)
6. Download missing mods automatically
7. Start game when all ready
```

**Key Implementation Details**:

1. **Player ID Handling**:
   - In `:idle` phase: `local_player_id` is `nil`
   - Validation skipped during pre-selection
   - Player ID stored for later validation
   - When joining session: validates stored player_id matches

2. **Selective Sharing**:
   - Only `selected_mods` are announced
   - `available_mods` stays local
   - Prevents exposing entire mod collection
   - Enables privacy and bandwidth control

3. **Validation Rules**:
   ```elixir
   # Start/join session requirements:
   - selected_mods must not be empty
   - player_id must match pre-selection
   - all selected_mods must be in available_mods
   ```

**Code Locations**:
- Pre-selection logic: `game_state_component.ex:147-169`
- Session validation: `game_state_component.ex:63-72, 110-114`
- Selective announcement: `game_state_component.ex:479-484, 564-569`
- Session cleanup: `game_state_component.ex:320`

---

**Critical Design Decision**:
> **Mods are persistent across sessions**. All mods are stored in a shared `./mods` folder. Each session, players select which of their available mods they want to use/share. This enables:
> - Mod reuse between sessions (no re-download)
> - Selective sharing (don't expose entire collection)
> - Persistent mod library building over time

---

### 3. SSL (Sync Status Ledger)

**Purpose**: Distributed registry of game entities

**Location**: `lib/modcast/sync_status_ledger.ex`

**Entity Structure**:
```elixir
%Entity{
  entity_id: "sword_001",           # Unique instance ID
  asset_id: "weapon_sword",         # Asset type
  hash: "abc123...",                # Mod hash
  player_id: "Player1",             # Current owner
  created_at: ~U[2025-01-15 10:00:00Z],
  last_transferred: ~U[2025-01-15 10:05:00Z]
}
```

**Use Case Example**:
```
Player1 has: fire_sword.zip (hash: AAA)
Player2 has: ice_sword.zip (hash: BBB)

1. Both join session and pre-select their mods
2. Player1 downloads ice_sword.zip from Player2
3. Player2 downloads fire_sword.zip from Player1
4. Game starts

5. Player1 creates entity: register_entity("sword_1", "weapon", "Player1", "AAA")
6. Player2 sees fire sword ✓ (has the mod)

7. Player1 gets ice sword: register_entity("sword_2", "weapon", "Player1", "BBB")
8. Player2 sees Player1 using ice sword ✓ (everyone has all mods)

9. Player1 drops ice sword: transfer_entity("sword_2", "Player2")
10. Player2 picks it up ✓ (entity ownership transferred)
```

**Key Operations**:
- `put_entity(ledger, entity)`: Add/update entity
- `get_entity(ledger, entity_id)`: Retrieve entity
- `get_entities_by_player(ledger, player_id)`: Get all entities owned by player
- `get_entities_by_hash(ledger, hash)`: Get all entities using a mod
- `merge(local, remote)`: Sync ledgers between peers

---

### 4. FTC (File Transfer Component)

**Purpose**: Handles mod file transfers between peers

**Location**: `lib/modcast/file_transfer_component.ex`

**Transfer Protocol**:
```elixir
# Request mod
{:request_mod, hash, filename, requestor_id}

# Send mod file (includes session_id for validation)
{:mod_file, session_id, hash, filename, binary_data}
```

**Safety Features**:
- **Session validation**: Rejects mods from wrong session
- **Hash verification**: MD5 check before and after transfer
- **Deduplication**: Checks if file exists before downloading
- **Size limits**: Max 10MB per file (configurable)
- **Integrity checking**: Validates hash after writing to disk

**Transfer Flow**:
```
Peer A                          Peer B
  │                               │
  │ 1. Announces: [hashX]         │
  │──────────────────────────────>│
  │                               │ 2. Checks: needs hashX
  │ 3. request_mod(hashX)         │
  │<──────────────────────────────│
  │                               │
  │ 4. Reads ./mods/mod.zip       │
  │ 5. Computes MD5: hashX        │
  │ 6. {:mod_file, session, hashX, data}
  │──────────────────────────────>│
  │                               │ 7. Receives data
  │                               │ 8. Verifies MD5: hashX ✓
  │                               │ 9. Saves to ./mods/mod.zip
  │                               │10. Updates available_mods
```

---

### 5. Persistence Layer (DETS Storage) (not in use)

**Purpose**: Session state persistence and recovery using DETS (Disk-based Erlang Term Storage)

**Location**: `lib/modcast/persistence.ex`

**Storage Backend**: DETS (Erlang's built-in disk-based key-value store)

**Storage Location**: `./data/modcast_state.dets`

**What is Persisted**:
```elixir
%{
  ssl: SyncStatusLedger,              # All entities
  players: %{player_id => info},      # Player registry
  phase: :loading | :in_game,         # Current phase
  mod_metadata: %{hash => data},      # Mod information
  player_selections: %{pid => mods},  # What each player selected
  timestamp: DateTime                 # When saved
}
```

**Key Operations**:
- `save_session(session_id, state)`: Persist current session state
- `load_session(session_id)`: Recover previous session state

**Use Cases**:

1. **Crash Recovery**:
   ```
   Server crashes → Restart → load_session("game_123") → Resume
   ```

2. **Session Continuity**:
   ```
   Players disconnect → Come back later → State preserved
   ```

3. **Debugging**:
   ```
   Inspect saved state → Understand what happened
   ```

**Storage Format**:
- **Type**: `:set` (key-value pairs, one entry per session)
- **Key**: `session_id` (string)
- **Value**: Map with session state
- **File**: `./data/modcast_state.dets` (binary format)

**Lifecycle**:
```elixir
# On Application Start
Persistence.start_link([])
# Opens DETS file, creates ./data/ if needed

# During Session
GameStateComponent.save_snapshot()
# → Persistence.save_session(session_id, state)

# On Recovery
{:ok, saved_state} = Persistence.load_session("game_123")
# → Restore SSL, players, phase, etc.
```

**Data Integrity**:
- DETS provides atomic writes
- File automatically synced to disk
- Survives process crashes
- Not replicated (single node only)


---

### 6. Modcast Mod File (MMF)

**Format**: Standard ZIP archive

**Naming Convention**: `mod_name.zip`

**Contents**: Game-specific assets (textures, models, sounds, etc.)

**Hash**: MD5 of entire ZIP file
- Used as unique identifier
- Ensures file integrity
- Enables deduplication

**Example**:
```
fire_sword.zip (3.2 MB)
├── textures/
│   ├── blade_fire.png
│   └── handle_wood.png
├── models/
│   └── sword.obj
└── metadata.json
```

**Hash Calculation**:
```elixir
hash = :crypto.hash(:md5, file_data) |> Base.encode16(case: :lower)
# Result: "a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6"
```

---

### 7. Persistence Layer (File System)

**Storage Location**: `./mods/` (shared folder)

**Structure**:
```
./mods/
├── fire_sword.zip          (hash: AAA...)
├── ice_sword.zip           (hash: BBB...)
├── desert_map.zip          (hash: CCC...)
└── laser_weapon.zip        (hash: DDD...)
```

**Lifecycle**:
- **On Init**: Scan folder, compute hashes → `available_mods`
- **On Download**: Save to folder, add to `available_mods`
- **Between Sessions**: Mods persist, no cleanup
- **On Next Session**: Rescan folder (might have new mods added externally)

**Benefits**:
- ✅ No redundant downloads
- ✅ Mod library grows over time
- ✅ Faster session startup (reuse existing mods)
- ✅ Works across different sessions/games

---

## Network Protocol

### Message Types

**Session Management**:
```elixir
{:handshake, session_id, player_id}
{:handshake_response, player_id}
{:handshake_response_with_peers, player_id, peer_list}
{:new_peer_joined, player_id, port}
{:player_left, player_id}
```

**Mod Synchronization (CORRECTED)**:
```elixir
# Only selected mods are announced (not entire folder)
{:selected_mods, player_id, [hash1, hash2, ...]}
{:available_mods, player_id, [hash1, hash2, ...]}  # Same as selected
{:request_mod, hash, filename, requestor_id}
{:mod_file, session_id, hash, filename, binary_data}
```

**Entity Management**:
```elixir
{:entity_created, %Entity{}}
{:entity_transferred, entity_id, new_player_id}
{:full_sync, %SyncStatusLedger{}}
```

**Game Control**:
```elixir
{:game_started}
```

### Network Topology

```
        Player1 (Host)
           /  \
          /    \
         /      \
    Player2-----Player3
         \      /
          \    /
           \  /
        (Mesh Network)

Each player maintains direct connections to all other players
```

---

## Testing

### Automated Test Suite

**Location**: `tests/multiple_instance_2.py`

**Tests Included**:
1. **Basic Mod Sharing**: 2 players, 1 mod each (corrected flow)
2. **Multiple Mods**: Multiple mods per player (corrected flow)
3. **Three Players**: Full mesh network test (corrected flow)

**Test Changes (December 2025)**:
- ✅ Mods created BEFORE starting Elixir
- ✅ Elixir scans mods on startup
- ✅ Tests query Elixir for actual hashes
- ✅ Pre-selection workflow implemented
- ✅ Selective sharing verified

**Run Tests**:
```bash
cd tests
python multiple_instance_2.py
```

**Expected Output**:
```
=== TEST 1: Basic Mod Sharing (FLUJO CORRECTO) ===
[Alice] ✓ Mod creado: epic_sword.zip (hash: 7e1e5d51...)
[Bob] ✓ Mod creado: divine_shield.zip (hash: a2b3c4d5...)
[Alice] ✓ 1 mod(s) escaneado(s)
[Bob] ✓ 1 mod(s) escaneado(s)
[Alice] PRE-SELECTING mods (before joining session)
[Bob] PRE-SELECTING mods (before joining session)
[Alice] ✓ Session started
[Bob] ✓ Joined session
  📦 [Alice] Mod descargado: Divine Shield
  📦 [Bob] Mod descargado: Epic Sword
✓ TEST PASSED!
```

---

## API Reference

### MSAPI Commands

#### start_session
```json
{"action": "start_session", "session": "my_game", "player": "Alice"}
```
**Requirements**: Player must have pre-selected mods
**Response**: `{"response": "ok", "message": "Session started"}`
**Errors**: 
- `"no_mods_selected"`: Must call select_mods first
- `"player_id_mismatch"`: Player ID doesn't match pre-selection

#### join_session
```json
{"action": "join_session", "session": "my_game", "player": "Bob", "host": "192.168.1.10"}
```
**Requirements**: Player must have pre-selected mods
**Response**: `{"response": "ok", "message": "Joined session"}`
**Errors**:
- `"no_mods_selected"`: Must call select_mods first
- `"player_id_mismatch"`: Player ID doesn't match pre-selection

#### select_mods
```json
{"action": "select_mods", "player": "Alice", "hashes": ["abc123", "def456"]}
```
**Phase**: Call in `:idle` (before joining session)
**Response**: `{"response": "ok", "message": "Mods selected. Missing: []"}`
**Behavior**:
- In `:idle`: Stores selection locally (pre-selection)
- In `:loading`: Announces to peers and triggers downloads

#### list_available_mods
```json
{"action": "list_available_mods"}
```
**Response**: `{"response": "ok", "message": ["hash1", "hash2", ...]}`
**Purpose**: Get actual hashes from Elixir's scan

#### start_game
```json
{"action": "start_game"}
```
**Requirements**: All required mods must be available
**Response**: `{"response": "ok", "message": "Game started"}`

#### register_entity
```json
{
  "action": "register_entity",
  "entity": "sword_1",
  "asset": "weapon",
  "player": "Alice",
  "hash": "abc123"
}
```
**Response**: `{"response": "ok", "message": "Entity created"}`

---

## Configuration

### Ports
- **MSAPI**: 5050 (Game Engine ↔ Modcast)
- **P2P Network**: 4040 (Player ↔ Player)

### File Limits
- **Max mod size**: 10 MB (configurable in `file_transfer_component.ex`)
- **Supported formats**: .zip

### Folders
- **Mods**: `./mods/` (persistent mod storage)
- **Data**: `./data/` (DETS state persistence)
  - `modcast_state.dets` - Session state snapshots

---

## Known Issues & Solutions (December 2025)

### Issue 1: Hash Mismatch Between Python and Elixir
**Status**: ✅ FIXED

**Problem**: Python calculated different MD5 hashes than Elixir for the same files.

**Root Cause**: File mode mismatch (text vs binary)

**Solution**: Tests now query Elixir for hashes instead of calculating them.

**Code**: `tests/multiple_instance_2.py:get_available_mods()`

---

### Issue 2: Incorrect Mod Selection Flow
**Status**: ✅ FIXED

**Problem**: 
- Mods selected AFTER joining session
- Entire `available_mods` folder exposed
- No privacy control

**Solution**: Implemented pre-selection in `:idle` phase

**Changes**:
- `game_state_component.ex`: Lines 147-169 (player_id validation)
- `game_state_component.ex`: Lines 63-72, 110-114 (session validation)
- `game_state_component.ex`: Lines 479-484, 564-569 (selective announcement)

---

### Issue 3: File Handle Errors in Tests
**Status**: ✅ FIXED

**Problem**: `I/O operation on closed file` when reusing instances

**Solution**: 
- Call `setup()` at start of each test
- Close previous log file before reopening
- Lines 63-67, 387-391, 516-520, 646-650

---

## Troubleshooting

### "Cannot select mods we don't have"
**Cause**: Hash mismatch or mods not scanned

**Solution**:
1. Create mods BEFORE starting Elixir
2. Query Elixir: `list_available_mods`
3. Use returned hashes for `select_mods`

### "No mods selected"
**Cause**: Trying to start/join without pre-selection

**Solution**:
```python
# CORRECT ORDER:
select_mods([hash1, hash2])  # First
start_session()              # Second
```

### "Player ID mismatch"
**Cause**: Different player_id in select_mods vs start/join

**Solution**: Use same player_id for both operations

---

## Team Members

| Name | UDC Login | GitHub |
|------|-----------|--------|
| David Javier Montes Fernández | david.j.montes | deivisi |
| Manuel Santamariña Ruiz de León | manuel.santamarina | manuelsrleon |
| Roi Millán Míguez | roi.millan.miguez | roimm1 |
| Pablo Masián Carro | pablo.masian.carro | pablomasian |
| Antón Pernas González | antonio.pernasg | antonioPernas |

**Supervised by**: David Cabrero Souto

---

## License

GNU General Public License v3.0 - See [LICENSE](LICENSE) file for details.

---

## Future Enhancements

- [ ] Use of persistence.ex
- [ ] Chunked file transfer for large mods (>10MB)
- [ ] Compression (gzip) for transfers
- [ ] NAT traversal (STUN/TURN)
- [ ] Web UI for mod management
- [ ] Bandwidth throttling
- [ ] Priority queues for mod downloads
- [ ] Mod versioning support
- [ ] Checksum alternatives (SHA-256)
- [ ] Automatic mod updates
- [ ] Mod dependency management
---

## Contact

For questions or issues, please open an issue on GitHub or contact the team members listed above.