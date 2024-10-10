defmodule Whepper.Application do
  @moduledoc false

  use Application
  alias Whepper.{ClientSupervisor, Coordinator}

  @impl true
  def start(_mode, _opts) do
    children = [
      ClientSupervisor,
      Coordinator
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
