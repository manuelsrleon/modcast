// WebRTC Signaling Server for Godot Multiplayer Game
// Simple WebSocket server that facilitates SDP/ICE exchange between peers

const WebSocket = require('ws');

const PORT = process.env.PORT || 8080;
const wss = new WebSocket.Server({ port: PORT });

// Store active sessions
// session_id -> { host: WebSocket, peers: [WebSocket], session_name: String }
const sessions = new Map();

// Store WebSocket to session_id mapping
const clientSessions = new Map();

// Store WebSocket to peer_id mapping
const clientPeerIds = new Map();

console.log(`WebRTC Signaling Server started on port ${PORT}`);

wss.on('connection', (ws) => {
    console.log('New client connected');

    ws.on('message', (message) => {
        try {
            const data = JSON.parse(message);
            handleMessage(ws, data);
        } catch (error) {
            console.error('Failed to parse message:', error);
            sendError(ws, 'Invalid JSON message');
        }
    });

    ws.on('close', () => {
        console.log('Client disconnected');
        handleDisconnect(ws);
    });

    ws.on('error', (error) => {
        console.error('WebSocket error:', error);
    });
});

function handleMessage(ws, data) {
    const { type } = data;

    switch (type) {
        case 'create_session':
            handleCreateSession(ws, data);
            break;

        case 'join_session':
            handleJoinSession(ws, data);
            break;

        case 'leave_session':
            handleLeaveSession(ws, data);
            break;

        case 'offer':
            handleOffer(ws, data);
            break;

        case 'answer':
            handleAnswer(ws, data);
            break;

        case 'ice_candidate':
            handleIceCandidate(ws, data);
            break;

        default:
            console.warn('Unknown message type:', type);
            sendError(ws, `Unknown message type: ${type}`);
    }
}

function handleCreateSession(ws, data) {
    const { session_name, player_name } = data;

    // Generate unique session ID
    const session_id = generateSessionId();

    // Create new session
    sessions.set(session_id, {
        host: ws,
        peers: [],
        session_name: session_name || 'Game Session',
        player_name: player_name || 'Host'
    });

    clientSessions.set(ws, session_id);
    clientPeerIds.set(ws, 1); // Host is always peer_id 1

    console.log(`Session created: ${session_id} by ${player_name}`);

    // Send confirmation to host
    send(ws, {
        type: 'session_created',
        session_id: session_id
    });
}

function handleJoinSession(ws, data) {
    const { session_id, player_name } = data;

    const session = sessions.get(session_id);
    if (!session) {
        sendError(ws, 'Session not found');
        return;
    }

    // Generate peer ID for new client
    const peer_id = generatePeerId();

    // Add to session
    session.peers.push(ws);
    clientSessions.set(ws, session_id);
    clientPeerIds.set(ws, peer_id);

    console.log(`${player_name} (peer ${peer_id}) joined session: ${session_id}`);

    // Notify client
    send(ws, {
        type: 'session_joined',
        session_id: session_id,
        peer_id: peer_id
    });

    // Notify host that peer wants to join
    send(session.host, {
        type: 'peer_wants_to_join',
        peer_id: peer_id,
        player_name: player_name || 'Player'
    });
}

function handleLeaveSession(ws, data) {
    const session_id = clientSessions.get(ws);
    if (!session_id) {
        return;
    }

    const session = sessions.get(session_id);
    if (!session) {
        return;
    }

    const peer_id = clientPeerIds.get(ws);

    // Remove from session
    if (session.host === ws) {
        // Host is leaving - notify all peers and close session
        console.log(`Host left session: ${session_id}`);

        session.peers.forEach(peer => {
            send(peer, {
                type: 'host_disconnected'
            });
        });

        sessions.delete(session_id);
    } else {
        // Peer is leaving - notify host
        const index = session.peers.indexOf(ws);
        if (index > -1) {
            session.peers.splice(index, 1);
        }

        console.log(`Peer ${peer_id} left session: ${session_id}`);

        send(session.host, {
            type: 'peer_disconnected',
            peer_id: peer_id
        });
    }

    clientSessions.delete(ws);
    clientPeerIds.delete(ws);
}

function handleOffer(ws, data) {
    const { target_peer_id, from_peer_id, sdp } = data;
    const session_id = clientSessions.get(ws);

    if (!session_id) {
        sendError(ws, 'Not in a session');
        return;
    }

    const session = sessions.get(session_id);
    if (!session) {
        sendError(ws, 'Session not found');
        return;
    }

    // Find target peer
    const targetWs = findPeerById(session, target_peer_id);
    if (!targetWs) {
        sendError(ws, 'Target peer not found');
        return;
    }

    // Forward offer to target peer
    send(targetWs, {
        type: 'offer',
        from_peer_id: from_peer_id,
        sdp: sdp
    });

    console.log(`Forwarded offer from ${from_peer_id} to ${target_peer_id}`);
}

function handleAnswer(ws, data) {
    const { target_peer_id, from_peer_id, sdp } = data;
    const session_id = clientSessions.get(ws);

    if (!session_id) {
        sendError(ws, 'Not in a session');
        return;
    }

    const session = sessions.get(session_id);
    if (!session) {
        sendError(ws, 'Session not found');
        return;
    }

    // Find target peer
    const targetWs = findPeerById(session, target_peer_id);
    if (!targetWs) {
        sendError(ws, 'Target peer not found');
        return;
    }

    // Forward answer to target peer
    send(targetWs, {
        type: 'answer',
        from_peer_id: from_peer_id,
        sdp: sdp
    });

    console.log(`Forwarded answer from ${from_peer_id} to ${target_peer_id}`);
}

function handleIceCandidate(ws, data) {
    const { target_peer_id, from_peer_id, mid, index, sdp } = data;
    const session_id = clientSessions.get(ws);

    if (!session_id) {
        sendError(ws, 'Not in a session');
        return;
    }

    const session = sessions.get(session_id);
    if (!session) {
        sendError(ws, 'Session not found');
        return;
    }

    // Find target peer
    const targetWs = findPeerById(session, target_peer_id);
    if (!targetWs) {
        // Silently ignore - ICE candidates might be sent before peer is ready
        return;
    }

    // Forward ICE candidate to target peer
    send(targetWs, {
        type: 'ice_candidate',
        from_peer_id: from_peer_id,
        mid: mid,
        index: index,
        sdp: sdp
    });

    console.log(`Forwarded ICE candidate from ${from_peer_id} to ${target_peer_id}`);
}

function handleDisconnect(ws) {
    const session_id = clientSessions.get(ws);
    if (session_id) {
        handleLeaveSession(ws, { session_id });
    }
}

function findPeerById(session, peer_id) {
    if (peer_id === 1) {
        return session.host;
    }

    for (const peer of session.peers) {
        if (clientPeerIds.get(peer) === peer_id) {
            return peer;
        }
    }

    return null;
}

function send(ws, data) {
    if (ws.readyState === WebSocket.OPEN) {
        ws.send(JSON.stringify(data));
    }
}

function sendError(ws, message) {
    send(ws, {
        type: 'error',
        message: message
    });
}

function generateSessionId() {
    return Math.random().toString(36).substring(2, 11);
}

function generatePeerId() {
    // Generate peer IDs starting from 2 (1 is reserved for host)
    return Math.floor(Math.random() * 1000000) + 2;
}

// Cleanup old sessions periodically
setInterval(() => {
    const now = Date.now();
    for (const [session_id, session] of sessions.entries()) {
        // Check if session is still active
        if (session.host.readyState !== WebSocket.OPEN) {
            console.log(`Cleaning up inactive session: ${session_id}`);
            sessions.delete(session_id);
        }
    }
}, 60000); // Every minute
