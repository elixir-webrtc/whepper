defmodule Whepper.Coordinator do
  @moduledoc false

  use GenServer, restart: :temporary
  require Logger
  alias Whepper.ClientSupervisor

  defmodule Config do
    @moduledoc false

    @type t :: %__MODULE__{
            url: String.t(),
            clients: pos_integer(),
            time: pos_integer(),
            spawn_interval: pos_integer()
          }

    @enforce_keys [:url]

    defstruct @enforce_keys ++
                [
                  clients: 500,
                  time: 300,
                  spawn_interval: 200
                ]
  end

  @spec run_test(Config.t()) :: :ok | no_return()
  def run_test(config) do
    ref = Process.monitor(__MODULE__)
    GenServer.call(__MODULE__, {:run_test, config})

    receive do
      {:DOWN, ^ref, :process, _pid, reason} ->
        if reason != :normal,
          do: Logger.error("Coordinator process exited with reason #{inspect(reason)}")

        :ok
    end
  end

  @spec start_link(term()) :: GenServer.on_start()
  def start_link(_args) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  @impl true
  def init(_args) do
    Logger.info("Coordinator: Init (pid: #{inspect(self())})")

    {:ok, nil}
  end

  @impl true
  def handle_call({:run_test, config}, _from, _state) do
    Logger.info("""
    Coordinator: Start of test
      URL: #{config.url}
      Clients: #{config.clients}
      Time: #{config.time} s
      Spawn interval: #{config.spawn_interval} ms
    """)

    Process.send_after(self(), :end_test, config.time * 1000)
    send(self(), :spawn_client)

    state = %{
      uri: URI.parse(config.url),
      clients: %{max: config.clients, spawned: 0, alive: 0},
      time: config.time,
      spawn_interval: config.spawn_interval
    }

    {:reply, :ok, state}
  end

  @impl true
  def handle_info(:spawn_client, %{clients: %{max: max, spawned: max}} = state) do
    {:noreply, state}
  end

  @impl true
  def handle_info(:spawn_client, %{clients: clients} = state) do
    Process.send_after(self(), :spawn_client, state.spawn_interval)
    name = "client-#{clients.spawned + 1}"

    case ClientSupervisor.spawn_client(state.uri) do
      {:ok, pid} ->
        Logger.info("Coordinator: #{name} spawned at #{inspect(pid)}")
        _ref = Process.monitor(pid)

        clients =
          clients
          |> Map.update!(:spawned, &(&1 + 1))
          |> Map.update!(:alive, &(&1 + 1))

        {:noreply, %{state | clients: clients}}

      {:error, reason} ->
        Logger.error("Coordinator: Error spawning #{name}: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(:end_test, state) do
    Logger.info("Coordinator: End of test")
    ClientSupervisor.terminate()
    {:stop, :normal, state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, reason}, %{clients: clients} = state) do
    Logger.warning("Coordinator: Child process #{inspect(pid)} died: #{inspect(reason)}")
    clients = Map.update!(clients, :alive, &(&1 - 1))
    {:noreply, %{state | clients: clients}}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.warning("Coordinator: Received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end
end
