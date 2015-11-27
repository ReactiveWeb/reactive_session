defmodule Reactive.Web.BulletHandler do
  defmodule State do
    defstruct session: :false, api: :false
  end

  def init(_transport, req, [_,opts], _active) do
    opts.api.load_api()
  	{:ok, req, %State{ api: opts.api }}
  end

  def stream(data, req, state) do
    :io.format("Received Data ~s~n", [Data])
    message=:jsx.decode(data,[labels: :atom])
    :io.format("Parsed as ~p~n", [message])
  	case message(message,req,state) do
      {:reply, reply, rReq, rState} ->
        {:reply, :jsx.encode(reply), rReq, rState}
      {:ok, rReq, rState} ->
        {:ok, rReq, rState}
    end
  end

  def message(%{type: "ping"},req,state) do
    {:reply, %{type: "pong"},req,state}
  end
  def message(%{type: "initializeSession", sessionId: session_id},req,state=%State{ session: false}) do
    _peer = case :cowboy_req.header(<<"X-Real-IP">>, req, :none) do
             addressString when is_binary(addressString) -> addressString
             {:none,req} ->
               {{ip,_port},req} = :cowboy_req.peer(req)
               :erlang.list_to_binary(:inet.ntoa(ip))
           end

    cond do
      byte_size(session_id)>100 -> {:error, "too long sessionId"}
      byte_size(session_id)<10 -> {:error, "too short sessionId"}
      true -> {:ok, req, %State{state | session: [Reactive.Session,session_id]}}
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
    {:reply, %{type: "response", response: reply, responseId: request_id} , req, state}
  end
  def message(%{ type: "event", to: [module | margs], method: method, args: args }, req, state) do
    moda=:erlang.binary_to_existing_atom( module,:utf8)
    mta=:erlang.binary_to_existing_atom(method,:utf8)
    state.api.event([moda|map_args(margs)],mta,args,contexts(req,state))
    {:ok, req, state}
  end
  def message(%{ type: "observe", to: [module | args], what: what }, req, state) do
    moda=:erlang.binary_to_existing_atom( module,:utf8)
    wha=:erlang.binary_to_existing_atom(what,:utf8)
    state.api.observe([moda|map_args(args)],wha,contexts(req,state))
    {:ok, req, state}
  end
  def message(%{ type: "unobserve", to: [module | args], what: what }, req, state) do
    moda=:erlang.binary_to_existing_atom( module,:utf8)
    wha=:erlang.binary_to_existing_atom(what,:utf8)
    state.api.unobserve([moda|map_args(args)],wha,contexts(req,state))
    {:ok, req, state}
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
    :io.format("term notification: ~p ~n",[data])
    encoded=:jsx.encode(data)
    :io.format("Encoded notification: ~p ~n",[encoded])
    {:reply, encoded, req, state}
  end
  def info(message, req, state) when is_map(message) do
    :io.format("sending message to client ~p ~n", [message])
    {:reply, :jsx.encode(Message), req, state}
  end
  def info(info, _req, state) do
  	:io.format("unknown info received ~p in state ~p ~n", [info, state])
  	{:error, :unknown_info}
  end

  def terminate(_req, _state) do
  	:io.format("bullet terminate~n")
  	:ok
  end

end