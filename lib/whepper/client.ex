defmodule Whepper.Client do
  @moduledoc false

  use GenServer, restart: :temporary

  alias ExWebRTC.{ICECandidate, PeerConnection, SessionDescription}
  alias Whepper.Client.ConnectionManager

  @pc_opts [
    ice_servers: [%{urls: "stun:stun.l.google.com:19302"}]
  ]

  @spec start_link(URI.t()) :: GenServer.on_start()
  def start_link(uri) do
    GenServer.start_link(__MODULE__, uri)
  end

  @impl true
  def init(uri) do
    path = uri.path || "/"
    base_uri = Map.put(uri, :path, nil)

    {:ok, conn_manager} = ConnectionManager.start_link(base_uri)

    state = %{
      conn_manager: conn_manager,
      pc: nil,
      whep_endpoint: path,
      patch_endpoint: nil
    }

    {:ok, state, {:continue, :start_whep}}
  end

  @impl true
  def handle_continue(:start_whep, state) do
    {:ok, pc} = PeerConnection.start_link(@pc_opts ++ [controlling_process: self()])

    PeerConnection.add_transceiver(pc, :video, direction: :recvonly)
    PeerConnection.add_transceiver(pc, :audio, direction: :recvonly)

    {:ok, offer} = PeerConnection.create_offer(pc)
    :ok = PeerConnection.set_local_description(pc, offer)

    {:ok, %{status: 201} = resp} =
      ConnectionManager.post(
        state.conn_manager,
        state.whep_endpoint,
        [
          {"Accept", "application/sdp"},
          {"Content-Type", "application/sdp"}
        ],
        offer.sdp
      )

    :ok =
      PeerConnection.set_remote_description(pc, %SessionDescription{type: :answer, sdp: resp.data})

    {_location, patch_endpoint} =
      Enum.find(resp.headers, fn {k, _v} -> String.downcase(k) == "location" end)

    {:noreply, %{state | pc: pc, patch_endpoint: patch_endpoint}}
  end

  @impl true
  def handle_info({:ex_webrtc, pc, {:ice_candidate, candidate}}, %{pc: pc} = state) do
    body =
      candidate
      |> ICECandidate.to_json()
      |> Jason.encode!()

    ConnectionManager.patch(
      state.conn_manager,
      state.patch_endpoint,
      [
        {"Content-Type", "application/trickle-ice-sdpfrag"}
      ],
      body
    )

    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end
end
