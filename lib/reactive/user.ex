defmodule Reactive.User do
  use Reactive.Entity
  use Reactive.EntityAutoIndex

  require Logger

  defmodule State do
    defstruct [
      vars: %{},
      identifiers: %{},
      credentials: %{},
      roles: []
    ]
  end

  def init(_args) do
    {:ok,%State{},%{}}
  end

  def indexed_values(state) do
    ident_list=Map.to_list(state.identifiers)
    index_list=Enum.map(ident_list,fn({k,v}) ->
      {"user_" <> :erlang.atom_to_binary(k,:utf8),v}
    end)
    :maps.from_list(index_list)
  end

  def request({:get,name},state,_from,_rid) do
    {:reply, Map.get(state.vars,name,:undefined), state}
  end
  def request({:set,name, value},state,_from,_rid) do
    r = {:reply, :ok, %{state | vars: Map.put(state.vars,name,value)}}
    r
  end
  def request({:unset,name},state,_from,_rid) do
    r = {:reply, :ok, %{state | vars: Map.delete(state.vars,name)}}
    r
  end
  def request({:set_ident,name, value},state,_from,_rid) do
    r = {:reply, :ok, %{state | identifiers: Map.put(state.identifiers,name,value)}}
    save_me()
    r
  end
  def request({:delete_ident,name},state,_from,_rid) do
    r = {:reply, :ok, %{state | identifiers: Map.delete(state.identifiers,name)}}
    save_me()
    r
  end
  def request({:merge_vars,vars},state,_from,_rid) do
    nvars=Map.merge(state.vars,vars,fn(k,uv,sv) -> Reactive.Session.Merge.merge(k,uv,sv) end)
    {:reply, :ok, %{state | vars: nvars}}
  end
  def request({:add_role,role},state,_from,_rid) do
    nstate=%{state | roles: [role | state.roles]}
    notify_observers(:roles,{:set,[nstate.roles]})
    save_me()
    {:reply,:ok,nstate}
  end
  def request({:remove_role,role},state,_from,_rid) do
    nstate=%{state | roles: Enum.filter(state.roles,fn(x) -> x!=role end)}
    notify_observers(:roles,{:set,[nstate.roles]})
    save_me()
    {:reply,:ok,nstate}
  end

  def get(:roles,state) do
    {:reply,state.roles,state}
  end

  def get(pid,name, defaultValue \\ :undefined) do
    case Reactive.Entity.request(pid,{:get,name}) do
      :undefined -> defaultValue
      v -> v
    end
  end

  def set(pid,name, value) do
    Reactive.Entity.request(pid,{:set,name,value})
    :ok
  end
  def unset(pid,name) do
    Reactive.Entity.request(pid,{:unset,name})
    :ok
  end
  def set_ident(pid,name, value) do
    Reactive.Entity.request(pid,{:set_ident,name,value})
    :ok
  end

  def delete_ident(pid,name) do
    Reactive.Entity.request(pid,{:delete_ident,name})
    :ok
  end

  def mergeSessionVars(user, vars) do
    Reactive.Entity.request(user,{:merge_vars,vars})
  end

  def save(id,state,container) do
    Reactive.EntityAutoIndex.save_auto_index(id,state,container,&indexed_values/1)
  end
  def retrive(id) do
    Reactive.EntityAutoIndex.retrive_auto_index(id,&indexed_values/1)
  end

  def version() do
    1
  end

  def convert(0,state) do
    Map.put(state,:roles,[])
  end
end