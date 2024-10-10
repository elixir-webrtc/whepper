defmodule Mix.Tasks.Whepper do
  @shortdoc "Run a WHEP stress test"
  @moduledoc """
  # Name

  `mix whepper` - #{@shortdoc}

  # Synopsis

  ```
  mix whepper [--url <url>] [--clients <count>]
              [--time <seconds>] [--spawn-interval <milliseconds>]
  ```

  # Description

  Mix task for running stress-tests on a media server using WHEP.

  This tool primarily tests the load handling capability and performance
  of the media server. The test simulates multiple WHEP clients connecting to the server
  concurrently over a specified duration.

  # Available options

  * `--url <url>` - URL of the WHEP endpoint
  * `--clients <count>` - Number of client connections to simulate. Defaults to 500
  * `--time <seconds>` - Duration of the test. Defaults to 300 seconds
  * `--spawn-interval <milliseconds>` - Interval at which to spawn new clients. Defaults to 200 milliseconds

  # Notes

  This tool opens two new sockets (one for TCP and one for UDP) for every simulated client.
  Users should ensure that both the system running the WHEP server and the one running this tool
  are prepared to handle this many connections. This may necessitate:

  * increasing the open port limit, e.g. using `ulimit -n 65536`
  * increasing the number of ports the Erlang VM can use, e.g. by setting the environment variable
  `ELIXIR_ERL_OPTIONS="+Q 65536"`

  # Example command

  `mix whepper --url https://example.org/whep --clients 300 --time 600`
  """

  use Mix.Task

  alias Whepper.Coordinator

  @impl true
  def run(argv) do
    Application.ensure_all_started(:whepper)

    {opts, _argv, _errors} =
      OptionParser.parse(argv,
        strict: [
          url: :string,
          clients: :integer,
          time: :integer,
          spawn_interval: :integer
        ]
      )

    coordinator_config = struct!(Coordinator.Config, opts)

    Coordinator.run_test(coordinator_config)
  end
end
