defmodule Modcast.MSAPI do
  @moduledoc """
  Main interface for the game engine.
  It acts as a local TCP server to receive commands and send events.
  """
  use GenServer
  require Logger
  alias Modcast.GameState.GameStateComponent

  @game_port 5050

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    
    case GameStateComponent.start_link(callback_handler: __MODULE__) do
      {:ok, _gsc_pid} ->
        Logger.info("[MSAPI] GameStateComponent started")
      {:error, {:already_started, _pid}} ->
        Logger.info("[MSAPI] GameStateComponent already running")
    end
    
    # Open Listening socket
    {:ok, listen_socket} = :gen_tcp.listen(@game_port, [:binary, packet: :line, active: true, reuseaddr: true])
    Logger.info("[MSAPI] Listening for Game Engine on port #{@game_port}")

    # GenServer pid
    parent_pid = self()

    # Arrancamos unha tarefa para ACEPTAR conexións
    Task.start_link(fn -> accept_loop(listen_socket, parent_pid) end)

    {:ok, %{socket: nil, listen_socket: listen_socket}}
  end

  # Private function to accept conections
  defp accept_loop(listen_socket, parent_pid) do
    case :gen_tcp.accept(listen_socket) do
      {:ok, client_socket} ->
        # We transfer socket control to the GenServer
        :gen_tcp.controlling_process(client_socket, parent_pid)

        # New client
        send(parent_pid, {:incoming_connection, client_socket})
        accept_loop(listen_socket, parent_pid)
      {:error, reason} ->
        Logger.error("[MSAPI] Accept error: #{inspect(reason)}")
    end
  end

  # --- GSC CALLBACKS ---
  def on_entity_created(entity), do: send_event("entity_created", entity)
  def on_entity_transferred(entity), do: send_event("entity_transferred", entity)
  def on_game_started(), do: send_event("game_started", %{})
  def on_mod_ready(hash, mod_data), do: send_event("mod_ready", Map.put(mod_data, :hash, hash))

  defp send_event(type, data) do
    GenServer.cast(__MODULE__, {:send_to_game, type, data})
  end

  # --- MESSAGE MANAGER ---

  @impl true
  def handle_info({:tcp, _socket, data}, state) do

    case Jason.decode(data) do
      {:ok, command} -> handle_game_command(command, state)
      {:error, _} ->
        Logger.warning("[MSAPI] Invalid JSON received")
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:tcp_closed, _socket}, state) do
    Logger.info("[MSAPI] Game Engine disconnected")
    {:noreply, %{state | socket: nil}}
  end

  @impl true
  def handle_info({:incoming_connection, socket}, state) do
    Logger.info("[MSAPI] Game Engine connected!")
    {:noreply, %{state | socket: socket}}
  end

  # --- GAME COMMANDS ---
  #{"action":"start_session", "session": session_id, "player":player_id}
  defp handle_game_command(%{"action" => "start_session", "session" => s, "player" => p}, state) do
    Logger.info("[MSAPI] Command start_host received")

    GameStateComponent.start_link(callback_handler: __MODULE__)

    case GameStateComponent.start_session(s, p) do
      {:ok, _} -> reply_to_game(state, "ok", "Session started")
      {:error, r} -> reply_to_game(state, "error", inspect(r))
    end
    {:noreply, state}
  end

  #{"action":"join_session", "session": session_id, "player":player_id, "host":host_id}
  defp handle_game_command(%{"action" => "join_session", "session" => s, "player" => p, "host" => h}, state) do
    Logger.info("[MSAPI] Command join_session received")
    GameStateComponent.start_link(callback_handler: __MODULE__)

    case GameStateComponent.join_session(s, p, h, 4040) do
      {:ok, _} -> reply_to_game(state, "ok", "Joining session...")
      {:error, r} -> reply_to_game(state, "error", inspect(r))
    end
    {:noreply, state}
  end
  # {"action":"leave_session"}
  defp handle_game_command(%{"action" => "leave_session"}, state) do # FALLA EN EL GCS. SUPONGO QUE HACE FALTA MANDAR ID DE LA SESSION (y jugador en caso de que se intente desconectar solo a un jugador)
    Logger.info("[MSAPI] Command leave_session received")
    GameStateComponent.leave_session()
    {:noreply, state}
  end


  #{"action":"register_entity", "entity": entity_id, "asset":asset_id, "player":player_id, "hash":hash}
  defp handle_game_command(%{"action" => "register_entity", "entity" => entity, "asset" => asset, "player" => p, "hash" => h}, state) do #FALLO EN EL GCS
    GameStateComponent.register_entity(entity, asset, p, h)
    {:noreply, state}
  end

  #{"action":"transfer_entity", "entity": entity_id, "new_player":player_id}
  defp handle_game_command(%{"action" => "transfer_entity", "entity" => entity, "new_player" => p}, state) do
    GameStateComponent.transfer_entity(entity, p)
    {:noreply, state}
  end


  defp handle_game_command(cmd, state) do
    Logger.warning("[MSAPI] Unknown command: #{inspect(cmd)}")
    {:noreply, state}
  end

  # --- RESPONSES TO THE GAME ---

  @impl true
  def handle_cast({:send_to_game, type, payload}, %{socket: socket} = state) when not is_nil(socket) do
    json = Jason.encode!(%{event: type, data: payload})
    :gen_tcp.send(socket, json <> "\n")
    {:noreply, state}
  end
  def handle_cast({:send_to_game, _, _}, state), do: {:noreply, state}

  defp reply_to_game(%{socket: socket}, status, msg) when not is_nil(socket) do
    response = Jason.encode!(%{response: status, message: msg})
    :gen_tcp.send(socket, response <> "\n")
  end
  defp reply_to_game(_, _, _), do: :ok
end
