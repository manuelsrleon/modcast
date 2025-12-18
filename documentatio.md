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
│  │  │  • Mod Selection & Announcement                        │  │
│  │  • Required Mods Tracking                                 │  │
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
│                   PERSISTENT STORAGE                     │
│   ./mods/  (Shared across sessions, MD5-indexed)        │
└─────────────────────────────────────────────────────────┘
```

---

## Core Components

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
┌──────┐  start_session()   ┌─────────┐  select_mods()   ┌─────────┐
│ IDLE │───────────────────>│ LOADING │─────────────────>│ IN_GAME │
└──────┘                     └─────────┘  start_game()    └─────────┘
   ▲                             │                             │
   │         leave_session()     │                             │
   └─────────────────────────────┴─────────────────────────────┘
```

**Mod Selection Flow**:
1. Player scans local `./mods` folder → `available_mods`
2. Player calls `select_mods([hash1, hash2])` → announces to peers
3. System adds to `required_mods` (union of all player selections)
4. System calculates `missing = required_mods - available_mods`
5. System requests missing mods from peers who have them
6. Once all mods available, game can start

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

1. Both join session and select their mods
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

### 5. Modcast Mod File (MMF)

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

### 6. Persistence Layer

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
{:player_left, player_id}
```

**Mod Synchronization**:
```elixir
{:selected_mods, player_id, [hash1, hash2, ...]}
{:available_mods, player_id, [hash1, hash2, ...]}
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
    Player2    Player3
         \      /
          \    /
           \  /
        (Mesh Network)

Each player maintains direct connections to all other players
```

---

## Usage Example

### 1. Start Modcast

```bash
iex -S mix
```

### 2. Game Engine Integration (Python example)

```python
import socket
import json

# Connect to Modcast
sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
sock.connect(("127.0.0.1", 5050))

# Host a session
command = {"action": "start_session", "session": "game_123", "player": "Alice"}
sock.send((json.dumps(command) + "\n").encode())

# Select mods for this session
command = {"action": "select_mods", "player": "Alice", "hashes": ["abc123", "def456"]}
sock.send((json.dumps(command) + "\n").encode())

# Start game once all mods ready
command = {"action": "start_game"}
sock.send((json.dumps(command) + "\n").encode())

# Register entity in game
command = {
    "action": "register_entity",
    "entity": "sword_1",
    "asset": "weapon_sword",
    "player": "Alice",
    "hash": "abc123"
}
sock.send((json.dumps(command) + "\n").encode())

# Listen for events
while True:
    data = sock.recv(4096).decode()
    event = json.loads(data)
    if event["event"] == "mod_ready":
        print(f"Mod ready: {event['data']['filename']}")
    elif event["event"] == "game_started":
        print("Game started!")
        break
```

---

## Testing

### Automated Test Suite

**Location**: `tests/test_file_transfer.py`

**Tests Included**:
1. **Basic Mod Sharing**: 2 players, 1 mod each
2. **Multiple Mods**: Multiple mods per player
3. **Three Players**: Full mesh network test
4. **Persistence**: Mods reused across sessions
5. **Selective Sharing**: Only selected mods are shared

**Run Tests**:
```bash
cd tests
python test_file_transfer.py
```

**Expected Output**:
```
=== TEST 1: Basic Mod Sharing ===
[Host] ✓ Created mod: espada_fuego.zip (hash: 7e1e5d51...)
[Client] ✓ Created mod: espada_hielo.zip (hash: a2b3c4d5...)
[Host] ✓ Session started
[Client] ✓ Joined session
[Host] 📦 Mod descargado: Espada Hielo
[Client] 📦 Mod descargado: Espada Fuego
✓ TEST PASSED!

RESULT: 5/5 tests passed (100%)
```

---

## API Reference

### MSAPI Commands

#### start_session
```json
{"action": "start_session", "session": "my_game", "player": "Alice"}
```
**Response**: `{"response": "ok", "message": "Session started"}`

#### join_session
```json
{"action": "join_session", "session": "my_game", "player": "Bob", "host": "192.168.1.10"}
```
**Response**: `{"response": "ok", "message": "Joined session"}`

#### select_mods
```json
{"action": "select_mods", "player": "Alice", "hashes": ["abc123", "def456"]}
```
**Response**: `{"response": "ok", "message": "Mods selected. Missing: []"}`

#### start_game
```json
{"action": "start_game"}
```
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
- **Mods**: `./mods/` (persistent storage)
- **Data**: `./data/` (DETS persistence)

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

- [ ] Chunked file transfer for large mods (>10MB)
- [ ] Compression (gzip) for transfers
- [ ] NAT traversal (STUN/TURN)
- [ ] Web UI for mod management
- [ ] Bandwidth throttling
- [ ] Priority queues for mod downloads
- [ ] Mod versioning support
- [ ] Checksum alternatives (SHA-256)

---

## Contact

For questions or issues, please open an issue on GitHub or contact the team members listed above.
