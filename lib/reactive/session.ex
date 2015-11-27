defmodule Reactive.Session do
  use Reactive.Entity

  defmodule State do
    defstruct [
      user: :none,
      vars: %{},
      session_id: 0,
      connection_monitors: %{},
      connected: :false
    ]
  end

  def init([sessionId]) do
    {:ok,%State{
      session_id: sessionId
    },%{}}
  end

  def request({:get,name},state,_from,_rid) do
    case state.user do
      :none -> Map.get(state.vars,name,:undefined)
      pid -> Reactive.User.get(pid,name)
    end
  end
  def request({:set,name, value},state,_from,_rid) do
    r=case state.user do
      :none -> {:reply, :ok, %{state | vars: Map.put(state.vars,name,value)}}
      pid -> Reactive.User.set(pid,name,value)
        {:reply,:ok,state}
    end
    Reactive.Entity.notify_observers(:vars,{:set,name,value})
    Reactive.Entity.notify_observers([:vars,name],{:set,name,value})
    r
  end
  def request({:login, userId},state,_from,_rid) do
    user=[Reactive.User,userId]
    if state.user==user do
      {:reply,user,state}
    else
      Reactive.User.mergeSessionVars(user,state.vars)
      nstate=%{state | user: user}
      observe(user,:roles)
      #on_login_change(nstate)
      save_me()
      {:reply,user,nstate}
    end
  end
  def request({:logout},state,_from,_rid) do
    case state.user do
      user ->
        nstate=%{state | user: :none}
        unobserve(user,:roles)
        on_login_change(nstate)
        save_me()
        {:reply,:ok,nstate}
      :none ->
        {:reply,:ok,state}
    end
  end
  def request({:get_context, context, module, args},state,_from,_rid) do
    id=case context do
      :session -> [module|[state.session_id | args]]
    end
    {:reply,id,state}
  end
  def get(:login_status,state) do
    st=case state.user do
      :none -> :not_logged_in
      user=[module|args] ->
        %{
          id: user,
          roles: Reactive.Entity.get(user,:roles)
        }
    end
    {:reply,st,state}
  end

  def notify(_user=[Reactive.User|_],:roles,{:set,[roles]},state) do
    case state.user do
      :none -> state
      user=[module | args] ->
        st=%{
          id: user,
          roles: roles
        }
        notify_observers(:login_status,{:set,[st]})
        state
    end
  end

  defp on_login_change(state) do
    st=case state.user do
      :none -> :not_logged_in
      user=[module | args] ->
        %{
          id: user,
          roles: Reactive.Entity.get(user,:roles)
        }
    end
    notify_observers(:login_status,{:set,[st]})
  end

  ### API:
  def get_value(pid,name, defaultValue \\ :undefined) do
    case Reactive.Entity.request(pid,{:get,name}) do
      :undefined -> defaultValue
      v -> v
    end
  end
  def get_context(pid,context,module,args) do
    Reactive.Entity.request(pid,{:get_context,context,module,args})
  end
  def set_value(pid,name, value) do
    Reactive.Entity.request(pid,{:set,name,value})
    :ok
  end
  def login(pid,userId) do
    Reactive.Entity.request(pid,{:login, userId})
  end
  def logout(pid) do
    Reactive.Entity.request(pid,{:logout})
  end

end