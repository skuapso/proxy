-module(proxy_deliver).

-behaviour(gen_server).

%% API
-export([
  start_link/3,
  send/3,
  recv/2,
  close/2
  ]).

%% gen_server callbacks
-export([init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         terminate/2,
         code_change/3]).

-record(state, {socket, data = << >>}).

-include_lib("logger/include/log.hrl").

-define(TCP_OPTIONS_ONCE, [binary, {active, once}, {reuseaddr, true}]).
-define(TCP_OPTIONS_FALSE, [binary, {active, false}, {reuseaddr, true}]).
%%%===================================================================
%%% API
%%%===================================================================
send(Pid, Data, _Timeout) when is_binary(Data) ->
  gen_server:cast(Pid, {send, Data}).

recv(Pid, Timeout) ->
  gen_server:call(Pid, recv, Timeout).

close(Pid, _Timeout) ->
  gen_server:cast(Pid, close).

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @spec start_link() -> {ok, Pid} | ignore | {error, Error}
%% @end
%%--------------------------------------------------------------------
start_link(Pid, Srv, Timeout) ->
  gen_server:start_link(?MODULE, {Pid, Srv}, [{timeout, Timeout}]).

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
init({_Pid, Server}) ->
  trace("init"),
  connect(),
  {ok, Server}.

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
handle_call(recv, _From, #state{data=Data} = State) when (is_binary(Data) and (Data =/= << >>)) ->
  {reply, {ok, Data}, State};
handle_call(recv, _From, #state{socket=Socket} = State) when is_port(Socket) ->
  inet:setopts(Socket, ?TCP_OPTIONS_FALSE),
  {ok, Data} = gen_tcp:recv(Socket, 0),
  inet:setopts(Socket, ?TCP_OPTIONS_ONCE),
  {reply, {ok, Data}, State};
handle_call(Request, From, State) ->
  warning("unhandled request ~w from ~w", [Request, From]),
  {stop, unhandled, State}.

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
handle_cast(connect, {Host, Port}) ->
  debug("connecting to ~w:~w", [Host, Port]),
  {ok, Socket} = gen_tcp:connect(Host, Port, ?TCP_OPTIONS_ONCE),
  debug("connected"),
  {noreply, #state{socket=Socket}};
handle_cast(close, State) ->
  {stop, normal, State};
handle_cast({send, Data}, #state{socket=Socket} = State) ->
  ok = gen_tcp:send(Socket, Data),
  {noreply, State};
handle_cast(Msg, State) ->
  warning("unhandled msg ~w", [Msg]),
  {stop, unhandled, State}.

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
handle_info({tcp, Socket, Data}, #state{socket=Socket, data=OldData} = State) ->
  {noreply, State#state{data = <<OldData/binary, Data/binary>>}};
handle_info({tcp_closed, Socket}, #state{socket=Socket, data=Data} = State) when (is_binary(Data) and (Data =/= << >>)) ->
  {noreply, State#state{socket = unhandled}};
handle_info({tcp_closed, Socket}, #state{socket=Socket, data = << >>} = State) ->
  {stop, normal, State#state{socket = unhandled}};
handle_info(Info, State) ->
  warning("unhandled info ~w", [Info]),
  {stop, unhandled, State}.

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
terminate(_Reason, #state{socket=Socket}) when is_port(Socket) ->
  gen_tcp:close(Socket),
  ok;
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
connect() ->
  gen_server:cast(self(), connect).
