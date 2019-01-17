defmodule Fluxter.Conn do
  @moduledoc false

  use GenServer

  alias Fluxter.Packet

  require Logger

  defstruct [:sock, :header, :port, :host]

  def new(host, port) when is_binary(host) do
    new(string_to_charlist(host), port)
  end

  def new(host, port) when is_list(host) or is_tuple(host) do
    {:ok, addr} = :inet.getaddr(host, :inet)
    header = Packet.header(addr, port)
    %__MODULE__{header: header, port: port, host: host}
  end

  def start_link(%__MODULE__{} = conn, worker) do
    GenServer.start_link(__MODULE__, conn, [name: worker])
  end

  def write(worker, name, tags, fields)
      when (is_binary(name) or is_list(name)) and is_list(tags) and is_list(fields) do
    # TODO: Remove `try` wrapping when we depend on Elixir ~> 1.3
    try do
      IO.puts "writing measurement #{name}"
      GenServer.cast(worker, {:write, name, tags, fields})
    catch
      _, _ -> :ok
    end
  end

  @spec init(%{
          host:
            atom()
            | char_list()
            | {:local, binary() | char_list()}
            | {byte(), byte(), byte(), byte()}
            | {char(), char(), char(), char(), char(), char(), char(), char()},
          port: char(),
          sock: any()
        }) ::
          {:ok,
           %{
             host:
               atom()
               | char_list()
               | {:local, binary() | [any()]}
               | {byte(), byte(), byte(), byte()}
               | {char(), char(), char(), char(), char(), char(), char(), char()},
             port: char(),
             sock: port()
           }}
  def init(conn) do
    IO.inspect conn
    #{:ok, socket} = :gen_tcp.listen(port, [:binary, packet: :line, active: false, reuseaddr: true])
    #{:ok, sock} = :gen_tcp.fdopen(0, [active: false])
    {:ok, sock} = :gen_tcp.connect(conn.host, conn.port, [active: false])
    IO.inspect sock
    IO.puts "here"

    #{:ok, sock} = :gen_udp.open(0, [active: false])
    {:ok, %{conn | sock: sock}}
  end

  def handle_cast({:write, name, tags, fields}, conn) do
    packet = Packet.build(conn.header, name, tags, fields)
    send(conn.sock, {self(), {:command, packet}})
    {:noreply, conn}
  end

  def handle_info({:inet_reply, _sock, :ok}, conn) do
    {:noreply, conn}
  end

  def handle_info({:inet_reply, _sock, {:error, reason}}, conn) do
    Logger.error [
      "Failed to send metric, reason: ",
      ?", :inet.format_error(reason), ?",
    ]
    {:noreply, conn}
  end

  if Version.match?(System.version(), ">= 1.3.0") do
    defp string_to_charlist(string), do: String.to_charlist(string)
  else
    defp string_to_charlist(string), do: String.to_char_list(string)
  end
end
