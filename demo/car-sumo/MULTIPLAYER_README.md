# Car-SUMO Multiplayer - Setup Guide

This guide explains how to set up and play the car racing game with WebRTC P2P multiplayer support.

## Features

- **WebRTC P2P Networking**: Direct peer-to-peer connections between players
- **IP-Based Joining**: Join games by entering the host's IP address
- **Admin Privileges**: Host can start/stop game, kick players, with automatic host migration
- **Full Synchronization**: Car positions, rotations, physics state, car models, and game events
- **In-Game Lobby**: Access multiplayer from the pause menu during gameplay

## Architecture

- **Network Topology**: Star (Host-Relay) - all peers connect to the host
- **Host Authority**: Host simulates physics for all players to prevent cheating
- **Clients**: Send input to host, receive state updates
- **Signaling Server**: Optional WebSocket server for WebRTC connection establishment

## Quick Start

### Option 1: Local Network Multiplayer (Recommended for Testing)

For local network play without a signaling server:

1. **Open the game in Godot 4.5**
   ```bash
   cd /path/to/car-sumo
   godot4 project.godot
   ```

2. **Run the game** (press F5 or click Play)

3. **Host a game**:
   - Press `ESC` to open pause menu
   - Click "Host Game"
   - You'll see the lobby with your player listed

4. **Join from another instance**:
   - Run a second instance of the game
   - Press `ESC` to open pause menu
   - Click "Join Game"
   - Enter the host's IP address (use `127.0.0.1` for localhost testing)
   - Click "Connect"

5. **Play**:
   - Select your car in the pause menu (synced across all players)
   - When ready, the host clicks "Start Game"
   - Game begins for all players!

### Option 2: With Signaling Server (For Internet Play)

For playing over the internet with WebRTC:

1. **Set up the signaling server**:
   ```bash
   cd signaling-server
   npm install
   npm start
   ```
   The server will start on port 8080 (or PORT environment variable)

2. **Update NetworkManager** (optional):
   In `scripts/network_manager.gd`, update the signaling server URL:
   ```gdscript
   var signaling_server_url: String = "ws://your-server-ip:8080"
   var use_signaling_server: bool = true
   ```

3. **Deploy signaling server** (optional):
   - Deploy to Heroku, Render, Railway, or any Node.js hosting
   - Update the URL in NetworkManager

4. **Run the game** and follow the same steps as Option 1

## Controls

### Gameplay
- **Arrow Keys / Left Stick**: Steer
- **Up Arrow / RT Trigger**: Accelerate
- **Down Arrow / LT Trigger**: Brake/Reverse
- **Space / Button A**: Jump
- **ESC / Start**: Pause Menu

### Multiplayer
- **Host Game**: Create a new multiplayer session
- **Join Game**: Join an existing session by IP
- **Start Game** (Host only): Begin the game for all players
- **Disconnect**: Leave the multiplayer session

## File Structure

```
car-sumo/
├── main.tscn                     # Main game scene with spawn points
├── main.gd                       # Spawn system for remote players
├── player.gd                     # Local player controller (modified for multiplayer)
├── multiplayer_player.tscn       # Remote player scene
├── scripts/
│   ├── network_manager.gd        # Core networking singleton
│   ├── signaling_client.gd       # WebSocket signaling client
│   ├── multiplayer_player.gd     # Remote player script
│   ├── pause_menu.gd             # UI with multiplayer controls
│   ├── car_manager.gd            # Car loading system
│   └── save_manager.gd           # Save system
├── ui/
│   └── pause_menu.tscn           # Pause menu with multiplayer UI
├── signaling-server/             # Optional WebRTC signaling server
│   ├── server.js                 # Node.js signaling server
│   ├── package.json              # Dependencies
│   └── README.md                 # Server documentation
└── MULTIPLAYER_README.md         # This file
```

## How It Works

### Connection Flow

**Host:**
1. Clicks "Host Game" → Creates WebRTCMultiplayerPeer as server
2. Waits for peers to connect
3. Spawns remote player for each connected peer
4. Broadcasts game state to all peers

**Client:**
1. Clicks "Join Game", enters host IP → Creates WebRTCMultiplayerPeer as client
2. Connects to host (via signaling server or direct)
3. Registers with host, sends player info
4. Receives player list and game state from host

### Synchronization

**Movement:**
- Client sends input to host (accelerate, reverse, steer)
- Host processes physics for all players
- Host updates player state in NetworkManager
- MultiplayerSynchronizer automatically syncs position/rotation/speed to all clients (20Hz)

**Car Selection:**
- Player selects car in pause menu
- NetworkManager broadcasts car change to all peers via RPC
- All peers update their local representation of that player's car

**Game Events:**
- Collisions, jumps detected by player
- Events broadcast via RPC to all peers
- All peers play visual/audio effects

## Admin Features

### Host Privileges
- **Start Game**: Initiate gameplay for all players
- **Kick Players**: Remove players from session (future feature)
- **Change Settings**: Modify game rules (future feature)

### Host Migration
- If host disconnects, the player with the lowest peer_id becomes the new host
- Automatic role transfer
- Game continues without interruption

## Troubleshooting

### "Failed to connect to host"
- **Check IP address**: Ensure you entered the correct IP
- **Firewall**: Make sure ports are open (WebRTC uses random UDP ports)
- **Network**: Ensure both players are on the same network (or use signaling server for internet)

### "Failed to host game"
- **WebRTC support**: Ensure Godot 4.5+ with WebRTC support
- **Port conflicts**: Another application might be using the port

### "Player not spawning"
- **Check console**: Look for errors in Godot output
- **Verify player data**: Ensure player registered with NetworkManager
- **Check spawn points**: Verify SpawnPoints node exists in main.tscn

### "Cars not syncing"
- **Check car model**: Ensure the car exists in both players' `/cars` folder
- **Network**: Verify multiplayer connection is active
- **CarManager**: Ensure CarManager is loaded as AutoLoad

### "Lag/Jittery movement"
- **Network latency**: High ping causes lag
- **Interpolation**: Adjust INTERPOLATION_SPEED in multiplayer_player.gd (default 0.3)
- **Update rate**: Modify MultiplayerSynchronizer update rate in multiplayer_player.tscn

## Advanced Configuration

### Adjust Network Settings

In `scripts/network_manager.gd`:
```gdscript
# Signaling server URL
var signaling_server_url: String = "ws://localhost:8080"

# Enable/disable signaling server
var use_signaling_server: bool = false
```

### Adjust Synchronization Rate

In `multiplayer_player.tscn`, modify the `MultiplayerSynchronizer` properties:
- Position/Rotation: 20Hz (50ms intervals) - default
- Speed/Steering: 10Hz (100ms intervals) - default

### Adjust Interpolation

In `scripts/multiplayer_player.gd`:
```gdscript
const INTERPOLATION_SPEED: float = 0.3  # Lower = smoother but laggier
```

### Add More Spawn Points

In `main.tscn`, add more `Node3D` children to `SpawnPoints` node with different positions.

## Signaling Server Deployment

### Heroku
```bash
cd signaling-server
heroku create your-app-name
git push heroku main
```

### Render
1. Create new Web Service
2. Connect GitHub repository
3. Set build command: `npm install`
4. Set start command: `npm start`

### Railway
```bash
cd signaling-server
railway init
railway up
```

Then update `network_manager.gd` with the deployed URL:
```gdscript
var signaling_server_url: String = "wss://your-app.herokuapp.com"
```

## Performance Tips

1. **Limit Players**: Recommended 2-8 players for optimal performance
2. **Local Network**: Best performance on LAN
3. **Update Rates**: Lower update rates reduce bandwidth but increase lag
4. **Interpolation**: Tune for your network conditions

## Known Limitations

1. **WebRTC NAT Traversal**: May not work behind some strict NATs without TURN server
2. **No late join**: Players must join before game starts (can be implemented)
3. **No reconnect**: If disconnected, must rejoin manually
4. **Car models**: All players must have the same car models in `/cars` folder

## Future Enhancements

- [ ] Late join support (join mid-game)
- [ ] Player names input
- [ ] Chat system
- [ ] Game settings (time limits, laps, etc.)
- [ ] Leaderboard
- [ ] Spectator mode
- [ ] TURN server for better NAT traversal
- [ ] Reconnect on disconnect
- [ ] Room codes instead of IP addresses

## License

This multiplayer implementation is part of the car-sumo demo project.

## Support

For issues, check:
1. Godot console output for errors
2. Signaling server logs (if using)
3. Network connectivity (ping test)
4. Godot version (requires 4.5+)

## Credits

Multiplayer system implemented using:
- Godot 4.5 WebRTCMultiplayerPeer
- Node.js WebSocket signaling server
- RPC system for event synchronization
- MultiplayerSynchronizer for state replication
