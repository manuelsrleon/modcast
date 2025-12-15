defmodule Modcast.GameState.GameStateComponent do
  @moduledoc """
  Game State Component - Core P2P game state manager.
  Handles session management, network connections, mod synchronization, and entity state.
  """
  
  use GenServer
  require Logger
  alias Modcast.SyncStatusLedger
  alias Modcast.GameState.Entity
  alias Modcast.Utils
  
  defstruct [
    :session_id,
    :local_player_id,
    :players,
    :peers,
    :phase,
    :available_mods,
    :required_mods,
    :callback_handler,
    :mods_folder,
    :ssl,
    :mod_metadata,
    :player_selections,
    :listener_socket,
    :connection_supervisor
  ]
  
  # Public API
  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  def start_session(session_id, player_id, port \\ 4040), do: GenServer.call(__MODULE__, {:start_session, session_id, player_id, port})
  def join_session(session_id, player_id, host, port \\ 4040), do: GenServer.call(__MODULE__, {:join_session, session_id, player_id, host, port})
  def leave_session, do: GenServer.cast(__MODULE__, :leave_session)
  def announce_required_mods(mod_hashes), do: GenServer.call(__MODULE__, {:announce_required_mods, mod_hashes})
  def select_mods(player_id, mod_hashes), do: GenServer.call(__MODULE__, {:select_mods, player_id, mod_hashes})
  def get_selected_mods(player_id), do: GenServer.call(__MODULE__, {:get_selected_mods, player_id})
  def register_entity(entity_id, asset_id, player_id, hash), do: GenServer.call(__MODULE__, {:register_entity, entity_id, asset_id, player_id, hash})
  def transfer_entity(entity_id, new_player_id), do: GenServer.call(__MODULE__, {:transfer_entity, entity_id, new_player_id})
  def get_entity(entity_id), do: GenServer.call(__MODULE__, {:get_entity, entity_id})
  def get_all_entities, do: GenServer.call(__MODULE__, :get_all_entities)
  def start_game, do: GenServer.call(__MODULE__, :start_game)
  def get_phase, do: GenServer.call(__MODULE__, :get_phase)
  def get_players, do: GenServer.call(__MODULE__, :get_players)
  def get_stats, do: GenServer.call(__MODULE__, :get_stats)
  def get_mod_info(hash), do: GenServer.call(__MODULE__, {:get_mod_info, hash})
  def is_mod_available?(hash), do: GenServer.call(__MODULE__, {:is_mod_available, hash})
  def list_available_mods, do: GenServer.call(__MODULE__, :list_available_mods)
  
  @impl true
  def init(opts) do
    {:ok, connection_supervisor} = Task.Supervisor.start_link(name: :modcast_connection_supervisor)
    state = %__MODULE__{
      session_id: nil,
      local_player_id: nil,
      players: %{},
      peers: %{},
      phase: :idle,
      available_mods: MapSet.new(),
      required_mods: MapSet.new(),
      callback_handler: Keyword.get(opts, :callback_handler),
      mods_folder: Keyword.get(opts, :mods_folder, "./mods"),
      ssl: SyncStatusLedger.new(),
      mod_metadata: %{},
      player_selections: %{},
      listener_socket: nil,
      connection_supervisor: connection_supervisor
    }
    Logger.info("[GSC] Initialized")
    {:ok, state}
  end
  
  @impl true
  def handle_call({:start_session, session_id, player_id, port}, _from, state) do
    if state.phase != :idle, do: {:reply, {:error, :already_in_session}, state}
    {available_mods, mod_metadata} = scan_local_mods(state.mods_folder)
    case start_listener(port) do
      {:ok, listener_socket} ->
        new_state = %{state | session_id: session_id, local_player_id: player_id, phase: :loading, 
          available_mods: available_mods, mod_metadata: mod_metadata, listener_socket: listener_socket}
        |> register_player(player_id, :connected)
        Logger.info("[GSC] Session started: #{session_id} on port #{port}")
        {:reply, {:ok, :session_started}, new_state}
      {:error, reason} ->
        Logger.error("[GSC] Failed to start session: #{reason}")
        {:reply, {:error, reason}, state}
    end
  end
  
  @impl true
  def handle_call({:join_session, session_id, player_id, host, port}, _from, state) do
    if state.phase != :idle, do: {:reply, {:error, :already_in_session}, state}
    {available_mods, mod_metadata} = scan_local_mods(state.mods_folder)
    case connect_to_peer(host, port) do
      {:ok, socket, peer_id} ->
        new_state = %{state | session_id: session_id, local_player_id: player_id, phase: :loading,
          available_mods: available_mods, mod_metadata: mod_metadata}
        |> register_player(player_id, :connected)
        |> add_peer(peer_id, player_id, socket)
        send_handshake(socket, session_id, player_id)
        Logger.info("[GSC] Joined session: #{session_id} at #{host}:#{port}")
        {:reply, {:ok, :joined_session}, new_state}
      {:error, reason} ->
        Logger.error("[GSC] Failed to join session: #{reason}")
        {:reply, {:error, reason}, state}
    end
  end
  
  @impl true
  def handle_cast(:leave_session, state) do
    Enum.each(state.peers, fn {_, peer} -> if peer.socket, do: :gen_tcp.close(peer.socket) end)
    if state.listener_socket, do: :gen_tcp.close(state.listener_socket)
    new_state = %{state | session_id: nil, local_player_id: nil, players: %{}, peers: %{}, 
      phase: :idle, required_mods: MapSet.new(), ssl: SyncStatusLedger.new(), 
      player_selections: %{}, listener_socket: nil}
    Logger.info("[GSC] Session ended")
    {:noreply, new_state}
  end
  
  @impl true
  def handle_call({:announce_required_mods, mod_hashes}, _from, state) do
    if state.phase != :loading, do: {:reply, {:error, :wrong_phase}, state}
    new_mods = MapSet.new(mod_hashes)
    new_required = MapSet.union(state.required_mods, new_mods)
    missing = MapSet.difference(new_mods, state.available_mods)
    new_state = %{state | required_mods: new_required}
    broadcast_message(new_state, {:required_mods, state.local_player_id, mod_hashes})
    new_state = request_missing_mods(new_state, missing)
    Logger.info("[GSC] Mods announced: #{length(mod_hashes)}, missing: #{MapSet.size(missing)}")
    {:reply, {:ok, MapSet.to_list(missing)}, new_state}
  end
  
  @impl true
  def handle_call({:select_mods, player_id, mod_hashes}, _from, state) do
    new_selections = Map.put(state.player_selections, player_id, MapSet.new(mod_hashes))
    new_state = %{state | player_selections: new_selections}
    if player_id == state.local_player_id and state.phase == :loading do
      broadcast_message(new_state, {:selected_mods, player_id, mod_hashes})
    end
    Logger.info("[GSC] Player #{player_id} selected #{length(mod_hashes)} mods")
    {:reply, :ok, new_state}
  end
  
  @impl true
  def handle_call({:register_entity, entity_id, asset_id, player_id, hash}, _from, state) do
    if state.phase != :in_game, do: {:reply, {:error, :wrong_phase}, state}
    if not MapSet.member?(state.available_mods, hash), do: {:reply, {:error, :mod_not_available}, state}
    entity = Entity.new(entity_id, asset_id, hash, player_id)
    new_ssl = SyncStatusLedger.put_entity(state.ssl, entity)
    new_state = %{state | ssl: new_ssl}
    broadcast_message(new_state, {:entity_created, entity})
    invoke_callback(state, :on_entity_created, [entity])
    Logger.info("[GSC] Entity created: #{entity_id}")
    {:reply, {:ok, entity}, new_state}
  end
  
  @impl true
  def handle_call({:transfer_entity, entity_id, new_player_id}, _from, state) do
    case SyncStatusLedger.get_entity(state.ssl, entity_id) do
      nil -> {:reply, {:error, :entity_not_found}, state}
      entity ->
        if entity.player_id != state.local_player_id, do: {:reply, {:error, :not_owner}, state}
        transferred = Entity.transfer(entity, new_player_id)
        new_ssl = SyncStatusLedger.put_entity(state.ssl, transferred)
        new_state = %{state | ssl: new_ssl}
        broadcast_message(new_state, {:entity_transferred, entity_id, new_player_id})
        invoke_callback(state, :on_entity_transferred, [transferred])
        Logger.info("[GSC] Entity transferred: #{entity_id}")
        {:reply, {:ok, transferred}, new_state}
    end
  end
  
  @impl true
  def handle_call(:start_game, _from, state) do
    if state.phase != :loading, do: {:reply, {:error, :wrong_phase}, state}
    missing = MapSet.difference(state.required_mods, state.available_mods)
    if Enum.empty?(missing) do
      new_state = %{state | phase: :in_game}
      broadcast_message(new_state, :game_started)
      invoke_callback(state, :on_game_started, [])
      Logger.info("[GSC] Game started")
      {:reply, :ok, new_state}
    else
      Logger.warning("[GSC] Cannot start game, missing mods: #{MapSet.to_list(missing)}")
      {:reply, {:error, {:mods_missing, MapSet.to_list(missing)}}, state}
    end
  end
  
  @impl true
  def handle_info({:tcp, socket, data}, state), do: handle_network_message(socket, data, state); {:noreply, state}
  @impl true
  def handle_info({:tcp_closed, socket}, state), do: handle_disconnection(socket, state); {:noreply, state}
  @impl true
  def handle_info({:tcp_error, socket, reason}, state) do
    Logger.error("[GSC] TCP error from socket: #{reason}")
    handle_disconnection(socket, state)
    {:noreply, state}
  end
  @impl true
  def handle_info({:accept_connection, socket}, state) do
    Task.Supervisor.start_child(state.connection_supervisor, fn -> handle_incoming_connection(socket, state) end)
    accept_connections(state.listener_socket)
    {:noreply, state}
  end
  
  # Private helper functions
  defp scan_local_mods(folder) do
    if File.exists?(folder) do
      folder
      |> File.ls!()
      |> Enum.filter(&String.ends_with?(&1, ".zip"))
      |> Enum.reduce({MapSet.new(), %{}}, fn filename, {hashes, metadata} ->
        path = Path.join(folder, filename)
        case Utils.compute_file_hash(path) do
          nil -> {hashes, metadata}
          hash -> 
            mod_data = %{filename: filename, display_name: Utils.get_mod_display_name(filename), 
              file_path: path, scanned_at: DateTime.utc_now()}
            {MapSet.put(hashes, hash), Map.put(metadata, hash, mod_data)}
        end
      end)
    else
      File.mkdir_p!(folder)
      {MapSet.new(), %{}}
    end
  end
  
  defp all_mods_ready?(state), do: MapSet.subset?(state.required_mods, state.available_mods)
  
  defp request_missing_mods(state, missing_mods) do
    Enum.reduce(missing_mods, state, fn hash, acc ->
      if peer = find_peer_with_mod(acc, hash) do
        filename = get_filename_for_hash(acc, hash)
        send_message(peer.socket, {:request_mod, hash, filename, state.local_player_id})
        Logger.info("[GSC] Requesting mod #{hash} from #{peer.player_id}")
      else
        Logger.warning("[GSC] Mod #{hash} required but no peer has it")
      end
      acc
    end)
  end
  
  defp get_filename_for_hash(state, hash) do
    case Map.get(state.mod_metadata, hash) do
      %{filename: filename} -> filename
      nil -> "#{hash}.zip"
    end
  end
  
  defp find_peer_with_mod(state, hash) do
    Enum.find_value(state.peers, fn {_, peer} -> peer end) # Simplified - assumes first peer has it
  end
  
  defp start_listener(port) do
    :gen_tcp.listen(port, [active: true, packet: :raw, reuseaddr: true, nodelay: true, backlog: 10])
  end
  
  defp accept_connections(socket) do
    Task.start(fn ->
      case :gen_tcp.accept(socket) do
        {:ok, client} -> GenServer.cast(__MODULE__, {:incoming_connection, client})
        {:error, reason} -> Logger.error("[GSC] Accept error: #{reason}")
      end
    end)
  end
  
  defp connect_to_peer(host, port) do
    case :gen_tcp.connect(String.to_charlist(host), port, [active: true, packet: :raw, nodelay: true]) do
      {:ok, socket} -> {:ok, socket, Utils.generate_peer_id()}
      {:error, reason} -> {:error, reason}
    end
  end
  
  defp handle_incoming_connection(socket, state) do
    receive do
      {:tcp, ^socket, data} ->
        case decode_message(data) do
          {:handshake, session_id, player_id} ->
            if session_id == state.session_id do
              peer_id = Utils.generate_peer_id()
              GenServer.cast(__MODULE__, {:peer_connected, peer_id, player_id, socket})
              send_message(socket, {:handshake_response, state.local_player_id})
              send_message(socket, {:full_sync, state.ssl})
              send_message(socket, {:available_mods, state.local_player_id, MapSet.to_list(state.available_mods)})
            else
              Logger.warning("[GSC] Connection attempt with wrong session_id")
              :gen_tcp.close(socket)
            end
          _ -> Logger.warning("[GSC] Invalid handshake"); :gen_tcp.close(socket)
        end
    after 5000 -> Logger.warning("[GSC] Handshake timeout"); :gen_tcp.close(socket)
    end
  end
  
  defp handle_network_message(socket, data, state) do
    case decode_message(data) do
      {:handshake_response, remote_player_id} ->
        if peer_id = find_peer_id_by_socket(state, socket) do
          new_state = update_peer_player_id(state, peer_id, remote_player_id)
          Logger.info("[GSC] Handshake completed with player #{remote_player_id}")
          new_state
        else
          state
        end
      {:required_mods, remote_player_id, mod_hashes} ->
        if state.phase == :loading do
          new_required = MapSet.union(state.required_mods, MapSet.new(mod_hashes))
          new_state = %{state | required_mods: new_required}
          missing = MapSet.difference(MapSet.new(mod_hashes), state.available_mods)
          Enum.each(missing, fn hash ->
            send_message(socket, {:request_mod, hash, get_filename_for_hash(state, hash), state.local_player_id})
          end)
          new_state
        else
          state
        end
      {:request_mod, hash, filename, requesting_player} ->
        case Map.get(state.mod_metadata, hash) do
          %{file_path: path} ->
            if File.exists?(path) do
              send_message(socket, {:mod_file, hash, filename, File.read!(path)})
              Logger.info("[GSC] Sending mod #{filename} to #{requesting_player}")
            else
              Logger.warning("[GSC] File not found for hash #{hash}")
            end
          nil -> Logger.warning("[GSC] Requested mod not available: #{hash}")
        end
        state
      {:mod_file, hash, filename, file_data} ->
        actual_hash = Utils.compute_data_hash(file_data)
        if actual_hash != hash do
          Logger.error("[GSC] Hash mismatch receiving mod #{filename}")
          invoke_callback(state, :on_mod_hash_mismatch, [hash, actual_hash])
          state
        else
          saved_path = save_mod_with_unique_name(state.mods_folder, filename, file_data, hash)
          mod_data = %{filename: Path.basename(saved_path), display_name: Utils.get_mod_display_name(filename),
            file_path: saved_path, ready_at: DateTime.utc_now()}
          new_available = MapSet.put(state.available_mods, hash)
          new_metadata = Map.put(state.mod_metadata, hash, mod_data)
          new_state = %{state | available_mods: new_available, mod_metadata: new_metadata}
          invoke_callback(state, :on_mod_ready, [hash, mod_data])
          if state.phase == :loading and all_mods_ready?(new_state) do
            invoke_callback(state, :on_all_mods_ready, [])
          end
          Logger.info("[GSC] Mod downloaded: #{Path.basename(saved_path)}")
          new_state
        end
      {:entity_created, entity} ->
        new_ssl = SyncStatusLedger.put_entity(state.ssl, entity)
        %{state | ssl: new_ssl}
      {:entity_transferred, entity_id, new_player_id} ->
        case SyncStatusLedger.get_entity(state.ssl, entity_id) do
          nil -> state
          entity ->
            transferred = Entity.transfer(entity, new_player_id)
            new_ssl = SyncStatusLedger.put_entity(state.ssl, transferred)
            %{state | ssl: new_ssl}
        end
      {:game_started} -> %{state | phase: :in_game}
      {:full_sync, remote_ssl} -> %{state | ssl: SyncStatusLedger.merge(state.ssl, remote_ssl)}
      _ -> Logger.warning("[GSC] Unknown message received"); state
    end
  end
  
  defp handle_disconnection(socket, state) do
    case find_peer_by_socket(state, socket) do
      {peer_id, _} -> remove_peer(state, peer_id)
      nil -> state
    end
  end
  
  defp save_mod_with_unique_name(folder, original_name, data, expected_hash) do
    if existing = Utils.find_file_by_hash(folder, expected_hash) do
      existing
    else
      unique_name = Utils.unique_filename(folder, original_name)
      path = Path.join(folder, unique_name)
      File.write!(path, data)
      path
    end
  end
  
  defp add_peer(state, peer_id, player_id, socket) do
    peer_info = %{player_id: player_id, socket: socket, connected_at: DateTime.utc_now(), announced_mods: MapSet.new()}
    %{state | peers: Map.put(state.peers, peer_id, peer_info)}
  end
  
  defp remove_peer(state, peer_id), do: %{state | peers: Map.delete(state.peers, peer_id)}
  defp find_peer_by_socket(state, socket), do: Enum.find(state.peers, fn {_, peer} -> peer.socket == socket end)
  defp find_peer_id_by_socket(state, socket), do: case find_peer_by_socket(state, socket) do {id, _} -> id; nil -> nil end
  
  defp update_peer_player_id(state, peer_id, player_id) do
    Map.update!(state.peers, peer_id, fn peer -> %{peer | player_id: player_id} end)
  end
  
  defp register_player(state, player_id, status) do
    player_info = %{status: status, joined_at: DateTime.utc_now()}
    %{state | players: Map.put(state.players, player_id, player_info)}
  end
  
  defp send_message(socket, message), do: :gen_tcp.send(socket, encode_message(message))
  defp broadcast_message(state, message), do: Enum.each(state.peers, fn {_, peer} -> send_message(peer.socket, message) end)
  defp send_handshake(socket, session_id, player_id), do: send_message(socket, {:handshake, session_id, player_id})
  defp encode_message(message), do: :erlang.term_to_binary(message)
  defp decode_message(data), do: :erlang.binary_to_term(data)
  
  defp invoke_callback(state, callback, args) do
    if state.callback_handler, do: apply(state.callback_handler, callback, args)
  rescue
    e -> Logger.error("[GSC] Callback error (#{callback}): #{inspect(e)}")
  end
end