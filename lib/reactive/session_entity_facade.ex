defmodule Reactive.SessionEntityFacade do

  defmacro __using__(_opts) do
    quote location: :keep do
      use Reactive.TemporaryEntity

      def unobserve_entity(entity,state) do
        :lists.foreach(fn({k,v}) -> unobserve(entity,k) end,Map.to_list(state.observations))
      end

      def observe_entity(entity,state) do
        #IO.inspect {"Observe ENTITY",entity,state}
        :lists.foreach(fn({k,v}) -> observe(entity,k) end,Map.to_list(state.observations))
      end

      def notify(_from,:login_status,{:set,[status]},state) do
       # :io.format('LOGIN STATUS ~p ~n',[status])
        case state.entity do
          :null -> 0
          entity -> unobserve_entity(entity,state)
        end
        entity = case status do
          :not_logged_in -> [entity_module() | state.session]
          %{ id: user } -> [entity_module() | user]
        end
        nstate=Map.put(state,:entity,entity)
        observe_entity(entity,state)
        nstate
      end
      def notify(_from,what,signal,state) do
        case Map.get(state.observations,what,:null) do
          :null -> state
          func ->
            res = func.(Map.get(state.data,what,:null),signal)
            notify_observers(what,signal)
            %{state | data: Map.put(state.data,what,res) }
        end
      end
      def get(what,state) do
        case Map.get(state.data,what,:null) do
          :null -> {:reply,Reactive.Entity.get(state.entity,what),state}
          value -> {:reply,value,state}
        end
      end
      def observe(what,state,pid) do
        case Map.get(state.data,what,:null) do
          :null -> {:ok,state}
          value -> {:reply,{:set,[value]},state}
        end
      end

      def init([sessionId]) do
        observe([Reactive.Session,sessionId],:login_status)
        status=Reactive.Entity.get([Reactive.Session,sessionId],:login_status)
        entity = case status do
                  :not_logged_in -> [entity_module(), Reactive.Session,sessionId]
                  %{ id: user } -> [entity_module() | user]
                end
        {:ok,%{
          session: [Reactive.Session,sessionId],
          entity: entity,
          data: %{},
          observations: observations()
        },%{
          lazy_time: 30_000
        }}
      end

      def forward_list(data,{:set,[ndata]}) do
        ndata
      end
      def forward_list(data,{:updateBy,[key,value,ndata]}) do
        nlist=Enum.map(data,fn(v) ->
          if Map.get(v,key)==value do
            ndata
          else
            v
          end
        end)
        nlist
      end
      def forward_list(data,{:putBy,[key,value,ndata]}) do
        nlist=Enum.filter(data,fn(v) ->
          Map.get(v,key)!=value
        end)
        [ndata | nlist]
      end
      def forward_list(data,{:push,elements}) do
        data ++ elements
      end
      def forward_list(data,{:unshift,[element]}) do
        [element | data]
      end
      def forward_list(data,{:removeBy,[key,value]}) do
        nlist=Enum.filter(data,fn(v) ->
          if Map.get(v,key)==value do
            :false
          else
            :true
          end
        end)
        nlist
      end
      def forward_list(data,{:remove,element}) do
        Enum.filter(data,fn(x) -> element==x end)
      end
      ## TODO: more list operations
    #  def forward_list(data,signal) do
    #    IO.inspect {"Unknown signal",signal,data}
    #  end

      def forward_value(data,{:set,[ndata]}) do
        ndata
      end
    end
  end
end