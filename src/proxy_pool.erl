-module(proxy_pool).

-behaviour(gen_server).

%% API
-export([
  start_link/0,
  start_deliver/6
  ]).

%% gen_server callbacks
-export([init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         terminate/2,
         code_change/3]).

-export([
  add_protocol/2,
  add_port/2,
  rules/0
  ]).

-record(state, {protocols = [], ports = []}).

-include_lib("logger/include/log.hrl").
%%%===================================================================
%%% API
%%%===================================================================
add_protocol(Proto, Srv) ->
  gen_server:cast(?MODULE, {add_protocol, Proto, Srv}).

add_port(Port, Srv) ->
  gen_server:cast(?MODULE, {add_port, Port, Srv}).

rules() ->
  gen_server:call(?MODULE, rules).

start_deliver(Proto, _RemoteIP, _RemotePort, _LocalIP, LocalPort, Timeout) ->
  gen_server:call(?MODULE, {start, self(), Proto, LocalPort, Timeout}).

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @spec start_link() -> {ok, Pid} | ignore | {error, Error}
%% @end
%%--------------------------------------------------------------------
start_link() ->
  gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initializes the server
%%
%% @spec init(Args) -> {ok, State} |
%%                     {ok, State, Timeout} |
%%                     ignore |
%%                     {stop, Reason}
%% @end
%%--------------------------------------------------------------------
init([]) ->
  trace("init"),
  process_flag(trap_exit, true),
  {ok, #state{}}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @spec handle_call(Request, From, State) ->
%%                                   {reply, Reply, State} |
%%                                   {reply, Reply, State, Timeout} |
%%                                   {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, Reply, State} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_call({start, Pid, Proto, Port, Timeout}, _From, #state{protocols=Protocols, ports=Ports} = State) ->
  Reply = case proplists:get_value(Port, Ports, proplists:get_value(Proto, Protocols)) of
    undefined -> undefined;
    Srv ->
      proxy_deliver:start_link(Pid, Srv, Timeout)
  end,
  {reply, Reply, State};
handle_call(rules, _From, State) ->
  {reply, State, State};
handle_call(Request, From, State) ->
  warning("unhandled request ~w from ~w", [Request, From]),
  {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%%
%% @spec handle_cast(Msg, State) -> {noreply, State} |
%%                                  {noreply, State, Timeout} |
%%                                  {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_cast({add_protocol, Proto, Srv}, #state{protocols=P} = State)->
  {noreply, State#state{protocols=[{Proto, Srv} | P]}};
handle_cast({add_port, Port, Srv}, #state{ports = P} = State) ->
  {noreply, State#state{ports = [{Port, Srv} | P]}};
handle_cast(Msg, State) ->
  warning("unhandled msg: ~w", [Msg]),
  {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages
%%
%% @spec handle_info(Info, State) -> {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_info({'EXIT', _Pid, _Reason}, State) ->
  {noreply, State};
handle_info(Info, State) ->
  warning("unhandled info: ~w", [Info]),
  {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%%
%% @spec terminate(Reason, State) -> void()
%% @end
%%--------------------------------------------------------------------
terminate(_Reason, _State) ->
  ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @spec code_change(OldVsn, State, Extra) -> {ok, NewState}
%% @end
%%--------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
