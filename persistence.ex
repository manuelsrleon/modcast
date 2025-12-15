defmodule Modcast.Persistence do
  @moduledoc """
  Simple session persistence using DETS for state recovery.
  """
  
  use GenServer
  
  @dets_file "modcast_state.dets"
  
  def start_link(_opts), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)
  def save_session(session_id, state), do: GenServer.cast(__MODULE__, {:save_session, session_id, state})
  def load_session(session_id), do: GenServer.call(__MODULE__, {:load_session, session_id})
  
  @impl true
  def init(_) do
    File.mkdir_p!("./data")
    {:ok, _} = :dets.open_file(:modcast_store, [{:file, "./data/#{@dets_file}"}, {:type, :set}])
    {:ok, %{}}
  end
  
  @impl true
  def handle_cast({:save_session, session_id, state}, store_state) do
    data = %{
      ssl: state.ssl,
      players: state.players,
      phase: state.phase,
      mod_metadata: state.mod_metadata,
      player_selections: state.player_selections,
      timestamp: DateTime.utc_now()
    }
    :dets.insert(:modcast_store, {session_id, data})
    {:noreply, store_state}
  end
  
  @impl true
  def handle_call({:load_session, session_id}, _from, store_state) do
    case :dets.lookup(:modcast_store, session_id) do
      [{^session_id, data}] -> {:reply, {:ok, data}, store_state}
      [] -> {:reply, {:error, :not_found}, store_state}
    end
  end
end