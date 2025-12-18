defmodule Modcast.GameState.GameStateComponent do
  @moduledoc """
  Game State Component - Core P2P game state manager.
  """
  use GenServer
  require Logger
  alias Modcast.SyncStatusLedger
  alias Modcast.GameState.Entity
  alias Modcast.Utils
  alias Modcast.FileTransferComponent

  defstruct [:session_id, :local_player_id, :players, :peers, :phase,
    :available_mods, :selected_mods, :required_mods,
    :callback_handler, :mods_folder, :ssl, :mod_metadata, :player_selections,
    :listener_socket, :connection_supervisor]

  # Public API
  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  def start_session(session_id, player_id, port \\ 4040), do: GenServer.call(__MODULE__, {:start_session, session_id, player_id, port})
  def join_session(session_id, player_id, host, port \\ 4040), do: GenServer.call(__MODULE__, {:join_session, session_id, player_id, host, port})
  def leave_session(session_id), do: GenServer.cast(__MODULE__, {:leave_session, session_id})
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
    mods_folder = Keyword.get(opts, :mods_folder, "./mods")
    File.mkdir_p!(mods_folder)
    {available_mods, mod_metadata} = scan_local_mods(mods_folder)

    state = %__MODULE__{
      session_id: nil, local_player_id: nil, players: %{}, peers: %{}, phase: :idle,
      available_mods: available_mods, selected_mods: MapSet.new(), required_mods: MapSet.new(),
      callback_handler: Keyword.get(opts, :callback_handler), mods_folder: mods_folder,
      ssl: SyncStatusLedger.new(), mod_metadata: mod_metadata, player_selections: %{},
      listener_socket: nil, connection_supervisor: connection_supervisor
    }
    Logger.info("[GSC] Initialized with mods folder: #{mods_folder}")
    Logger.info("[GSC] Found #{MapSet.size(available_mods)} mods in local folder")
    {:ok, state}
  end

  @impl true
  def handle_call({:start_session, session_id, player_id, port}, _from, state) do
    cond do
      state.phase != :idle -> {:reply, {:error, :already_in_session}, state}
      true ->
        {available_mods, mod_metadata} = scan_local_mods(state.mods_folder)
        case start_listener(port) do
          {:ok, listener_socket} ->
            accept_next_connection(listener_socket)
            new_state = %{state | session_id: session_id, local_player_id: player_id, phase: :loading,
              available_mods: available_mods, mod_metadata: mod_metadata, listener_socket: listener_socket,
              selected_mods: MapSet.new(), required_mods: MapSet.new(), player_selections: %{}}
            |> register_player(player_id, :connected)
            Logger.info("[GSC] Session started: #{session_id} on port #{port}")
            Logger.info("[GSC] #{MapSet.size(available_mods)} mods available. Use select_mods() to choose which to share.")
            {:reply, {:ok, :session_started}, new_state}
          {:error, reason} ->
            Logger.error("[GSC] Failed to start session: #{reason}")
            {:reply, {:error, reason}, state}
        end
    end
  end

  @impl true
  def handle_call({:join_session, session_id, player_id, host, port}, _from, state) do
    cond do
      state.phase != :idle -> {:reply, {:error, :already_in_session}, state}
      true ->
        {available_mods, mod_metadata} = scan_local_mods(state.mods_folder)
        case connect_to_peer(host, port) do
          {:ok, socket, peer_id} ->
            new_state = %{state | session_id: session_id, local_player_id: player_id, phase: :loading,
              available_mods: available_mods, mod_metadata: mod_metadata,
              selected_mods: MapSet.new(), required_mods: MapSet.new(), player_selections: %{}}
            |> register_player(player_id, :connected)
            |> add_peer(peer_id, player_id, socket)
            send_handshake(socket, session_id, player_id)
            Logger.info("[GSC] Joined session: #{session_id} at #{host}:#{port}")
            Logger.info("[GSC] #{MapSet.size(available_mods)} mods available. Use select_mods() to choose which to share.")
            {:reply, {:ok, :joined_session}, new_state}
          {:error, reason} ->
            Logger.error("[GSC] Failed to join session: #{reason}")
            {:reply, {:error, reason}, state}
        end
    end
  end

  @impl true
  def handle_call({:select_mods, player_id, mod_hashes}, _from, state) do
    cond do
      state.phase == :in_game ->
        Logger.warning("[GSC] Cannot select mods: game already started")
        {:reply, {:error, :game_already_started}, state}
      state.phase != :loading ->
        Logger.warning("[GSC] Cannot select mods: not in loading phase")
        {:reply, {:error, :wrong_phase}, state}
      player_id != state.local_player_id ->
        Logger.warning("[GSC] Cannot select mods for another player")
        {:reply, {:error, :not_local_player}, state}
      true ->
        requested = MapSet.new(mod_hashes)
        missing_locally = MapSet.difference(requested, state.available_mods)
        if MapSet.size(missing_locally) > 0 do
          Logger.warning("[GSC] Cannot select mods we don't have: #{inspect(MapSet.to_list(missing_locally))}")
          {:reply, {:error, {:mods_not_available, MapSet.to_list(missing_locally)}}, state}
        else
          new_selections = Map.put(state.player_selections, player_id, requested)
          new_state = %{state | selected_mods: requested, player_selections: new_selections,
            required_mods: MapSet.union(state.required_mods, requested)}
          broadcast_message(new_state, {:selected_mods, player_id, mod_hashes})
          broadcast_message(new_state, {:available_mods, player_id, mod_hashes})
          Logger.info("[GSC] Player #{player_id} selected #{length(mod_hashes)} mods for this session")
          missing_from_peers = MapSet.difference(state.required_mods, state.available_mods)
          if MapSet.size(missing_from_peers) > 0 do
            new_state = request_missing_mods(new_state, missing_from_peers)
            {:reply, {:ok, :mods_selected, MapSet.to_list(missing_from_peers)}, new_state}
          else
            {:reply, {:ok, :mods_selected, []}, new_state}
          end
        end
    end
  end

  @impl true
  def handle_call({:get_selected_mods, player_id}, _from, state) do
    {:reply, MapSet.to_list(Map.get(state.player_selections, player_id, MapSet.new())), state}
  end

  @impl true
  def handle_call({:register_entity, entity_id, asset_id, player_id, hash}, _from, state) do
    cond do
      state.phase != :in_game ->
        Logger.warning("[GSC] Cannot register entity: wrong phase (#{state.phase})")
        {:reply, {:error, :wrong_phase}, state}
      not MapSet.member?(state.required_mods, hash) ->
        Logger.warning("[GSC] Cannot register entity: mod not selected by anyone (#{String.slice(hash, 0, 8)}...)")
        {:reply, {:error, :mod_not_selected}, state}
      not MapSet.member?(state.available_mods, hash) ->
        Logger.warning("[GSC] Cannot register entity: mod not available locally (#{String.slice(hash, 0, 8)}...)")
        {:reply, {:error, :mod_not_available}, state}
      not Map.has_key?(state.players, player_id) ->
        Logger.warning("[GSC] Cannot register entity: player not in session (#{player_id})")
        {:reply, {:error, :player_not_in_session}, state}
      true ->
        entity = Entity.new(entity_id, asset_id, hash, player_id)
        new_ssl = SyncStatusLedger.put_entity(state.ssl, entity)
        new_state = %{state | ssl: new_ssl}
        broadcast_message(new_state, {:entity_created, entity})
        invoke_callback(state, :on_entity_created, [entity])
        Logger.info("[GSC] Entity created: #{entity_id} (asset: #{asset_id}, player: #{player_id})")
        {:reply, {:ok, entity}, new_state}
    end
  end

  @impl true
  def handle_call({:transfer_entity, entity_id, new_player_id}, _from, state) do
    case SyncStatusLedger.get_entity(state.ssl, entity_id) do
      nil -> {:reply, {:error, :entity_not_found}, state}
      entity ->
        cond do
          entity.player_id != state.local_player_id -> {:reply, {:error, :not_owner}, state}
          not Map.has_key?(state.players, new_player_id) -> {:reply, {:error, :target_player_not_in_session}, state}
          true ->
            transferred = Entity.transfer(entity, new_player_id)
            new_ssl = SyncStatusLedger.put_entity(state.ssl, transferred)
            new_state = %{state | ssl: new_ssl}
            broadcast_message(new_state, {:entity_transferred, entity_id, new_player_id})
            invoke_callback(state, :on_entity_transferred, [transferred])
            Logger.info("[GSC] Entity transferred: #{entity_id} -> #{new_player_id}")
            {:reply, {:ok, transferred}, new_state}
        end
    end
  end

  @impl true
  def handle_call({:get_entity, entity_id}, _from, state), do: {:reply, SyncStatusLedger.get_entity(state.ssl, entity_id), state}
  @impl true
  def handle_call(:get_all_entities, _from, state), do: {:reply, SyncStatusLedger.list_entities(state.ssl), state}

  @impl true
  def handle_call(:start_game, _from, state) do
    cond do
      state.phase != :loading -> {:reply, {:error, :wrong_phase}, state}
      MapSet.size(state.required_mods) == 0 ->
        Logger.warning("[GSC] Cannot start game: no mods selected by any player")
        {:reply, {:error, :no_mods_selected}, state}
      true ->
        missing = MapSet.difference(state.required_mods, state.available_mods)
        if MapSet.size(missing) == 0 do
          new_state = %{state | phase: :in_game}
          broadcast_message(new_state, :game_started)
          invoke_callback(state, :on_game_started, [])
          Logger.info("[GSC] Game started with #{MapSet.size(state.required_mods)} mods")
          {:reply, :ok, new_state}
        else
          Logger.warning("[GSC] Cannot start game, missing mods: #{inspect(MapSet.to_list(missing))}")
          {:reply, {:error, {:mods_missing, MapSet.to_list(missing)}}, state}
        end
    end
  end

  @impl true
  def handle_call(:get_phase, _from, state), do: {:reply, state.phase, state}
  @impl true
  def handle_call(:get_players, _from, state), do: {:reply, state.players, state}

  @impl true
  def handle_call(:get_stats, _from, state) do
    stats = %{
      session_id: state.session_id, local_player_id: state.local_player_id, phase: state.phase,
      num_players: map_size(state.players), num_peers: map_size(state.peers), num_entities: map_size(state.ssl.entities),
      available_mods: MapSet.size(state.available_mods), selected_mods: MapSet.size(state.selected_mods),
      required_mods: MapSet.size(state.required_mods), mods_folder: state.mods_folder
    }
    {:reply, stats, state}
  end

  @impl true
  def handle_call({:get_mod_info, hash}, _from, state), do: {:reply, Map.get(state.mod_metadata, hash), state}
  @impl true
  def handle_call({:is_mod_available, hash}, _from, state), do: {:reply, MapSet.member?(state.available_mods, hash), state}
  @impl true
  def handle_call(:list_available_mods, _from, state), do: {:reply, MapSet.to_list(state.available_mods), state}

  @impl true
  def handle_cast({:leave_session, session_id}, state) do
    cond do
      state.session_id == nil ->
        Logger.warning("[GSC] No active session to leave")
        {:noreply, state}
      state.session_id != session_id ->
        Logger.warning("[GSC] Attempt to leave wrong session: #{session_id} (current: #{state.session_id})")
        {:noreply, state}
      true ->
        broadcast_message(state, {:player_left, state.local_player_id})
        Enum.each(state.peers, fn {_, peer} -> if peer.socket, do: :gen_tcp.close(peer.socket) end)
        if state.listener_socket, do: :gen_tcp.close(state.listener_socket)
        new_state = %{state | session_id: nil, local_player_id: nil, players: %{}, peers: %{}, phase: :idle,
          selected_mods: MapSet.new(), required_mods: MapSet.new(), ssl: SyncStatusLedger.new(),
          player_selections: %{}, listener_socket: nil}
        Logger.info("[GSC] Session ended: #{session_id}")
        Logger.info("[GSC] #{MapSet.size(new_state.available_mods)} mods remain available for next session")
        {:noreply, new_state}
    end
  end

  @impl true
  def handle_cast({:peer_connected, peer_id, player_id, socket}, state) do
    new_state = add_peer(state, peer_id, player_id, socket)
    Logger.info("[GSC] Peer connected: #{peer_id} (player: #{player_id})")
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:tcp, socket, data}, state), do: {:noreply, handle_network_message(socket, data, state)}
  @impl true
  def handle_info({:tcp_closed, socket}, state) do
    Logger.warning("[GSC] TCP CLOSED detected for socket: #{inspect(socket)}")

    case find_peer_by_socket(state, socket) do
      {peer_id, peer} ->
        Logger.info("[GSC] Identified peer: #{peer.player_id} (peer_id: #{peer_id})")
      nil ->
        Logger.warning("[GSC] Socket closed but peer not found in state")
    end

    {:noreply, handle_disconnection(socket, state)}
  end
  @impl true
  def handle_info({:tcp_error, socket, reason}, state) do
    Logger.error("[GSC] TCP error from socket: #{inspect(reason)}")
    {:noreply, handle_disconnection(socket, state)}
  end

  @impl true
  def handle_info({:incoming_connection, socket}, state) do
    Task.Supervisor.start_child(state.connection_supervisor, fn -> handle_incoming_connection_safe(socket, __MODULE__) end)
    {:noreply, state}
  end

  # Private functions
  defp accept_next_connection(listener_socket) do
    Task.start(fn ->
      case :gen_tcp.accept(listener_socket, 30000) do  # ← Timeout de 30s en accept
        {:ok, client_socket} ->
          # Configurar socket con opciones adecuadas
          :inet.setopts(client_socket, [
            :binary,
            active: false,           # Pasivo para handshake controlado
            packet: 4,
            nodelay: true,
            send_timeout: 10000,     # ← Timeout de envío
            send_timeout_close: true
          ])

          # Pasar al supervisor de tareas para manejo robusto
          {:ok, pid} = Task.Supervisor.start_child(:modcast_connection_supervisor, fn ->
            handle_incoming_connection_safe(client_socket, __MODULE__)
          end)
          # Transferir el Socket al hijo
          :ok = :gen_tcp.controlling_process(client_socket, pid)
          accept_next_connection(listener_socket)

        {:error, :closed} ->
          Logger.info("[GSC] Listener socket closed")

        {:error, :timeout} ->
          Logger.debug("[GSC] Accept timeout, retrying...")
          accept_next_connection(listener_socket)

        {:error, reason} ->
          Logger.error("[GSC] Accept error: #{inspect(reason)}")
          Process.sleep(1000)
          accept_next_connection(listener_socket)
      end
    end)
  end

  defp scan_local_mods(folder) do
    if File.exists?(folder) do
      folder |> File.ls!() |> Enum.filter(&String.ends_with?(&1, ".zip"))
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

  defp find_peer_with_mod(state, hash) do
    state.peers |> Map.values()
    |> Enum.filter(fn peer -> MapSet.member?(peer.announced_mods || MapSet.new(), hash) end)
    |> case do
      [] -> nil
      peers -> Enum.random(peers)
    end
  end

  defp request_missing_mods(state, missing_mods) do
    Enum.reduce(missing_mods, state, fn hash, acc ->
      case find_peer_with_mod(acc, hash) do
        nil -> Logger.warning("[GSC] Mod #{String.slice(hash, 0, 8)}... required but no peer has it"); acc
        peer ->
          filename = get_filename_for_hash(acc, hash)
          send_message(peer.socket, {:request_mod, hash, filename, acc.local_player_id})
          Logger.info("[GSC] Requesting mod #{String.slice(hash, 0, 8)}... from #{peer.player_id}")
          acc
      end
    end)
  end

  defp get_filename_for_hash(state, hash) do
    case Map.get(state.mod_metadata, hash) do
      %{filename: filename} -> filename
      nil -> "#{hash}.zip"
    end
  end

  defp start_listener(port), do: :gen_tcp.listen(port, [:binary, active: true, packet: 4, reuseaddr: true, nodelay: true, backlog: 10])
  defp connect_to_peer(host, port) do
    case :gen_tcp.connect(String.to_charlist(host), port, [:binary, active: true, packet: 4, nodelay: true]) do
      {:ok, socket} -> {:ok, socket, Utils.generate_peer_id()}
      {:error, reason} -> {:error, reason}
    end
  end

  defp handle_incoming_connection_safe(socket, server_module) do
    try do
      # Leer handshake en modo bloqueante
      case :gen_tcp.recv(socket, 0, 10000) do
        {:ok, data} ->
          # Obtener estado actual
          state = :sys.get_state(server_module)

          case decode_message(data) do
            {:handshake, session_id, player_id} ->
              if session_id == state.session_id do
                peer_id = Utils.generate_peer_id()

                server_pid = Process.whereis(server_module)

                # Transferimos la propiedad del socket al GenServer
                :gen_tcp.controlling_process(socket, server_pid)
                # Cambiar a modo activo AHORA
                :inet.setopts(socket, [active: true])

                # Notificar al GenServer
                GenServer.cast(server_module, {:peer_connected, peer_id, player_id, socket})

                # Enviar respuestas
                send_message(socket, {:handshake_response, state.local_player_id})
                send_message(socket, {:full_sync, state.ssl})

                if MapSet.size(state.selected_mods) > 0 do
                  send_message(socket, {:available_mods, state.local_player_id, MapSet.to_list(state.selected_mods)})
                  send_message(socket, {:selected_mods, state.local_player_id, MapSet.to_list(state.selected_mods)})
                end

                Logger.info("[GSC] Successfully accepted connection from #{player_id}")
              else
                Logger.warning("[GSC] Session mismatch: expected #{state.session_id}, got #{session_id}")
                :gen_tcp.close(socket)
              end

            invalid ->
              Logger.warning("[GSC] Invalid handshake message: #{inspect(invalid)}")
              :gen_tcp.close(socket)
          end

        {:error, :timeout} ->
          Logger.warning("[GSC] Handshake recv timeout")
          :gen_tcp.close(socket)

        {:error, reason} ->
          Logger.warning("[GSC] Handshake recv error: #{inspect(reason)}")
          :gen_tcp.close(socket)
      end
    rescue
      error ->
        Logger.error("[GSC] Exception in handle_incoming_connection: #{inspect(error)}")
        Logger.error("[GSC] Stacktrace: #{inspect(__STACKTRACE__)}")
        :gen_tcp.close(socket)
    end
  end


  defp handle_network_message(socket, data, state) do
    case decode_message(data) do
      {:handshake_response, remote_player_id} ->
        if peer_id = find_peer_id_by_socket(state, socket) do
          new_state = update_peer_player_id(state, peer_id, remote_player_id)
          if MapSet.size(state.selected_mods) > 0 do
            send_message(socket, {:available_mods, state.local_player_id, MapSet.to_list(state.selected_mods)})
            send_message(socket, {:selected_mods, state.local_player_id, MapSet.to_list(state.selected_mods)})
          end
          Logger.info("[GSC] Handshake completed with #{remote_player_id}")
          new_state
        else
          state
        end
      {:available_mods, player_id, mod_list} ->
        case find_peer_by_socket(state, socket) do
          {peer_id, peer} ->
            updated_peer = %{peer | announced_mods: MapSet.new(mod_list)}
            new_peers = Map.put(state.peers, peer_id, updated_peer)
            Logger.info("[GSC] Peer #{player_id} announced #{length(mod_list)} available mods")
            %{state | peers: new_peers}
          nil -> state
        end
      {:selected_mods, player_id, mod_hashes} ->
        if state.phase == :loading do
          new_mods = MapSet.new(mod_hashes)
          new_required = MapSet.union(state.required_mods, new_mods)
          new_selections = Map.put(state.player_selections, player_id, new_mods)
          new_state = %{state | required_mods: new_required, player_selections: new_selections}
          missing = MapSet.difference(new_mods, state.available_mods)
          if MapSet.size(missing) > 0 do
            Logger.info("[GSC] Peer #{player_id} selected #{length(mod_hashes)} mods, we need #{MapSet.size(missing)}")
            request_missing_mods(new_state, missing)
          else
            Logger.info("[GSC] Peer #{player_id} selected #{length(mod_hashes)} mods (we have all)")
            new_state
          end
        else
          Logger.warning("[GSC] Ignoring mod selection outside loading phase")
          state
        end
      {:request_mod, hash, filename, requesting_player} ->
        FileTransferComponent.handle_mod_request(hash, filename, requesting_player, socket, state)
        state
      {:mod_file, session_id, hash, filename, file_data} ->
        if session_id != state.session_id do
          Logger.warning("[GSC] Rejected mod from wrong session")
          state
        else
          case FileTransferComponent.handle_mod_received(hash, filename, file_data, session_id, state) do
            {:ok, new_state} -> new_state
            {:error, _, new_state} -> new_state
          end
        end
      {:entity_created, entity} ->
        new_ssl = SyncStatusLedger.put_entity(state.ssl, entity)
        invoke_callback(state, :on_entity_created, [entity])
        %{state | ssl: new_ssl}
      {:entity_transferred, entity_id, new_player_id} ->
        case SyncStatusLedger.get_entity(state.ssl, entity_id) do
          nil -> state
          entity ->
            transferred = Entity.transfer(entity, new_player_id)
            new_ssl = SyncStatusLedger.put_entity(state.ssl, transferred)
            invoke_callback(state, :on_entity_transferred, [transferred])
            %{state | ssl: new_ssl}
        end
      {:player_left, player_id} ->
        Logger.info("[GSC] Player left: #{player_id}")
        %{state | players: Map.delete(state.players, player_id)}
      {:game_started} ->
        invoke_callback(state, :on_game_started, [])
        %{state | phase: :in_game}
      {:full_sync, remote_ssl} ->
        %{state | ssl: SyncStatusLedger.merge(state.ssl, remote_ssl)}
      _ ->
        Logger.warning("[GSC] Unknown message received")
        state
    end
  end

  defp handle_disconnection(socket, state) do
    case find_peer_by_socket(state, socket) do
      {peer_id, peer} ->
        Logger.info("[GSC] Peer disconnected: #{peer.player_id}")
        new_players = Map.delete(state.players, peer.player_id)
        new_state = remove_peer(state, peer_id)
        %{new_state | players: new_players}
      nil -> state
    end
  end

  defp add_peer(state, peer_id, player_id, socket) do
    peer_info = %{player_id: player_id, socket: socket, connected_at: DateTime.utc_now(), announced_mods: MapSet.new()}
    %{state | peers: Map.put(state.peers, peer_id, peer_info)}
  end

  defp remove_peer(state, peer_id), do: %{state | peers: Map.delete(state.peers, peer_id)}
  defp find_peer_by_socket(state, socket), do: Enum.find(state.peers, fn {_, peer} -> peer.socket == socket end)
  defp find_peer_id_by_socket(state, socket) do
    case find_peer_by_socket(state, socket) do
      {id, _} -> id
      nil -> nil
    end
  end

  defp update_peer_player_id(state, peer_id, player_id) do
    new_peers = Map.update!(state.peers, peer_id, fn peer -> %{peer | player_id: player_id} end)
    %{state | peers: new_peers}
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
    if state.callback_handler do
      apply(state.callback_handler, callback, args)
    end
  rescue
    e -> Logger.error("[GSC] Callback error (#{callback}): #{inspect(e)}")
  end
end
