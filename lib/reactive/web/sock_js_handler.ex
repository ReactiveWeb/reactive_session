defmodule Reactive.Web.SockJsHandler do
  require Logger

  defmodule State do
    defstruct session: :false, api: :false
  end

  def handle(_conn, :init, state) do
    #Logger.debug("SockJS init in state #{inspect state} PID=#{inspect self()}")
    {:new_connection, api} = state
    Logger.debug("LOAD API!!!")
    api.load_api()
    {:ok, %State{ api: api }}
  end
  def handle(conn, {:recv, data}, state) do
    #Logger.debug("SockJS data #{data} in state #{inspect state}")
    message=:jsx.decode(data,[labels: :existing_atom])  ### TODO: SECURITY! :existing_atom
    {megasecs,secs,microsecs} =  :os.timestamp()
    ts = megasecs*1_000_000_000+secs*1_000+div(microsecs,1_000)
    tmessage=Map.put(message,:server_recv_ts,ts)
    case message(tmessage,conn,state) do
      {:reply, reply, rState} ->
        encoded = :jsx.encode(reply)
     #   Logger.debug("SockJS reply #{encoded} in state #{inspect rState}")
        :sockjs.send(encoded, conn)
        {:ok, rState}
      {:ok, rState} ->
        {:ok, rState}
    end
  end
  def handle(conn, {:info, info}, state) do
    Logger.debug("SockJS info #{inspect info} in state #{inspect state}")
    case info(info,conn,state) do
      {:reply, reply, rState} ->
        encoded = :jsx.encode(reply)
   #     Logger.debug("SockJS send #{encoded} in state #{inspect rState}")
        :sockjs.send(encoded, conn)
        {:ok, rState}
      {:ok, rState} ->
        {:ok, rState}
    end
  end
  def handle(_conn, :closed, state) do
   # Logger.debug("SockJS close in state #{inspect state}")
    {:ok, state}
  end

  def message(%{type: "ping"}, req, state) do
    {:reply, %{type: "pong"}, state}
  end
  def message(%{type: "timeSync", server_recv_ts: recv_ts, client_send_ts: send_ts }, req, state) do
    {:reply, %{type: "timeSync", server_recv_ts: recv_ts, client_send_ts: send_ts, server_send_ts: recv_ts }, state}
  end
  def message(%{type: "initializeSession", sessionId: session_id},req,state=%State{ session: false}) do
    Logger.debug("LOAD API!!!")
    state.api.load_api()
    cond do
      byte_size(session_id)>100 -> {:error, "too long sessionId"}
      byte_size(session_id)<10 -> {:error, "too short sessionId"}
      true -> {:ok, %State{state | session: [Reactive.Session,session_id]}}
    end
    ## TODO SECURITY: check for too much sessions/connections from one IP!
  end
  def message(_,_req,_state=%State{ session: false}) do
    {:error, :not_authenticated}
  end
  def message(%{ type: "request", to: [module | margs], method: method, args: args, requestId: request_id }, req, state) do
    moda=:erlang.binary_to_existing_atom(module,:utf8)
    mta=:erlang.binary_to_existing_atom(method,:utf8)
    reply=state.api.request([moda |map_args(margs)],mta,args,contexts(req,state))
    {:reply, %{type: "response", response: reply, responseId: request_id} , state}
  end
  def message(%{ type: "event", to: [module | margs], method: method, args: args }, req, state) do
    moda=:erlang.binary_to_existing_atom( module,:utf8)
    mta=:erlang.binary_to_existing_atom(method,:utf8)
    state.api.event([moda|map_args(margs)],mta,args,contexts(req,state))
    {:ok, state}
  end
  def message(%{ type: "observe", to: [module | args], what: what }, req, state) do
    moda=:erlang.binary_to_existing_atom( module,:utf8)
    wha=:erlang.binary_to_existing_atom(what,:utf8)
    state.api.observe([moda|map_args(args)],wha,contexts(req,state))
    {:ok, state}
  end
  def message(%{ type: "unobserve", to: [module | args], what: what }, req, state) do
    moda=:erlang.binary_to_existing_atom( module,:utf8)
    wha=:erlang.binary_to_existing_atom(what,:utf8)
    state.api.unobserve([moda|map_args(args)],wha,contexts(req,state))
    {:ok, state}
  end
  def message(%{ type: "get", to: [module | margs], what: what, requestId: request_id }, req, state) do
    moda=:erlang.binary_to_existing_atom(module,:utf8)
    wha=:erlang.binary_to_existing_atom(what,:utf8)
    reply=state.api.get([moda |map_args(margs)],wha,contexts(req,state))
    {:reply, %{type: "response", response: reply, responseId: request_id} , state}
  end
  def message(msg,_req,_state) do
    :io.format("unknown ws message ~p ~n",[msg])
    throw "unknown ws message"
  end
  defp map_args(args) do
    Enum.map(args,fn
      (x = ("Elixir." <> name)) -> :erlang.binary_to_existing_atom(x,:utf8)
      (x) -> x
    end)
  end

  def contexts(_req,state) do
    %{
      session: state.session,
      socket: self()
    }
  end

  def info({:notify,from,what,{signal,args}},req,state) do
    data=%{
                 type: "notify",
                 from: from,
                 what: what,
                 signal: signal,
                 args: args
               }
   # :io.format("term notification: ~p ~n",[data])

    {:reply, data, state}
  end
  def info(message, req, state) when is_map(message) do
  #  :io.format("sending message to client ~p ~n", [message])
    {:reply, message, state}
  end
  def info(info, _req, state) do
   # :io.format("unknown info received ~p in state ~p ~n", [info, state])
    {:error, :unknown_info}
  end
end