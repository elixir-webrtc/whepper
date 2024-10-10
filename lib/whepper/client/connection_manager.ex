defmodule Whepper.Client.ConnectionManager do
  @moduledoc false

  use GenServer

  defstruct [:conn, :uri, requests: %{}]

  @connection_opts [protocols: [:http2]]

  @spec start_link(URI.t()) :: GenServer.on_start()
  def start_link(uri) do
    GenServer.start_link(__MODULE__, uri)
  end

  @spec get(GenServer.server(), Path.t(), Mint.Types.headers(), iodata() | nil) ::
          {:ok, map()} | {:error, Mint.Types.error()}
  def get(pid, path, headers \\ [], body \\ nil) do
    GenServer.call(pid, {:fetch, "GET", path, headers, body})
  end

  @spec post(GenServer.server(), Path.t(), Mint.Types.headers(), iodata() | nil) ::
          {:ok, map()} | {:error, Mint.Types.error()}
  def post(pid, path, headers \\ [], body \\ nil) do
    GenServer.call(pid, {:fetch, "POST", path, headers, body})
  end

  @spec patch(GenServer.server(), Path.t(), Mint.Types.headers(), iodata() | nil) ::
          {:ok, map()} | {:error, Mint.Types.error()}
  def patch(pid, path, headers \\ [], body \\ nil) do
    GenServer.call(pid, {:fetch, "PATCH", path, headers, body})
  end

  @spec reconnect(GenServer.server()) :: :ok | {:error, Mint.Types.error()}
  def reconnect(pid) do
    GenServer.call(pid, :reconnect)
  end

  @impl true
  def init(uri) do
    case connect(uri) do
      {:ok, conn} ->
        state = %__MODULE__{uri: uri, conn: conn}
        {:ok, state}

      {:error, mint_error} ->
        {:stop, mint_error}
    end
  end

  @impl true
  def handle_call(:reconnect, _from, state) do
    if Mint.HTTP.open?(state.conn) do
      {:reply, :ok, state}
    else
      case connect(state.uri) do
        {:ok, conn} ->
          {:reply, :ok, %{state | conn: conn}}

        {:error, _mint_error} = error ->
          {:reply, error, state}
      end
    end
  end

  @impl true
  def handle_call({:fetch, method, path, headers, body}, from, state) do
    case Mint.HTTP.request(state.conn, method, path, headers, body) do
      {:ok, conn, request_ref} ->
        state = put_in(state.requests[request_ref], %{from: from, response: %{}})
        {:noreply, %{state | conn: conn}}

      {:error, conn, mint_error} ->
        {:reply, {:error, mint_error}, %{state | conn: conn}}
    end
  end

  @impl true
  def handle_info(message, state) do
    case Mint.HTTP.stream(state.conn, message) do
      :unknown ->
        {:noreply, state}

      {:ok, conn, responses} ->
        state = Enum.reduce(responses, state, &process_response/2)
        {:noreply, %{state | conn: conn}}

      {:error, conn, _mint_error, responses} ->
        # The list `responses` may or may not contain the `{:error, ...}` tuple --
        # if it doesn't, we will never reply to the request, so the call will timeout
        # (if unchanged, after 5 seconds)
        #
        # Handling this case would require us to handle all timeouts
        # (if `responses` is empty, there's no easy way to get the `request_ref`
        # and lookup the `GenServer.from()` tuple we have to reply to...)
        state = Enum.reduce(responses, state, &process_response/2)
        {:noreply, %{state | conn: conn}}
    end
  end

  defp connect(uri) do
    Mint.HTTP.connect(String.to_atom(uri.scheme), uri.host, uri.port, @connection_opts)
  end

  defp process_response({:status, request_ref, status}, state) do
    put_in(state.requests[request_ref].response[:status], status)
  end

  defp process_response({:headers, request_ref, headers}, state) do
    put_in(state.requests[request_ref].response[:headers], headers)
  end

  defp process_response({:data, request_ref, new_data}, state) do
    update_in(state.requests[request_ref].response[:data], fn data -> (data || "") <> new_data end)
  end

  defp process_response({:done, request_ref}, state) do
    {%{response: response, from: from}, state} = pop_in(state.requests[request_ref])
    GenServer.reply(from, {:ok, response})

    state
  end

  defp process_response({:error, request_ref, mint_error}, state) do
    {%{from: from}, state} = pop_in(state.requests[request_ref])
    GenServer.reply(from, {:error, mint_error})

    state
  end
end
