-module(proxy).

-behaviour(application).
-behaviour(supervisor).

%% Supervisor callbacks
-export([init/1]).
%% Application callbacks
-export([start/0, start/2, stop/1]).
%% hooks API
-export([
  connection_accepted/4,
  connection_closed/3,
  terminal_raw_data/5
  ]).
%% API
-export([
  add_protocol/2,
  add_port/2,
  rules/0,
  start_link/1,
  start_link/0
  ]).

-include_lib("logger/include/log.hrl").
%%%===================================================================
%%% API functions
%%%===================================================================
add_protocol(Protocol, Srv) ->
  proxy_pool:add_protocol(Protocol, Srv).

add_port(Port, Srv) ->
  proxy_pool:add_port(Port, Srv).

rules() ->
  proxy_pool:rules().

connection_accepted(Pid, Proto, Socket, Timeout) ->
  {ok, {RemoteIP, RemotePort}} = inet:peername(Socket),
  {ok, {LocalIP, LocalPort}} = inet:sockname(Socket),
  connect(Pid, proxy_pool:start_deliver(Proto, RemoteIP, RemotePort, LocalIP, LocalPort, Timeout), Timeout).

connection_closed(Pid, _Reason, Timeout) ->
  close(Pid, get_proxy(Pid), Timeout).

terminal_raw_data(Pid, _Module, _UIN, RawData, Timeout) ->
  process_data(Pid, RawData, get_proxy(Pid), Timeout).
%%--------------------------------------------------------------------
%% @doc
%% Starts the supervisor
%%
%% @spec start_link() -> {ok, Pid} | ignore | {error, Error}
%% @end
%%--------------------------------------------------------------------
start() ->
  application:start(?MODULE).

start(_StartType, StartArgs) ->
  start_link(StartArgs).

stop(_State) ->
  ok.

start_link() ->
  start_link([]).

start_link(StartArgs) ->
  Reply = supervisor:start_link({local, ?MODULE}, ?MODULE, StartArgs),
  Protocols = misc:get_env(?MODULE, protocol, StartArgs),
  Ports = misc:get_env(?MODULE, port, StartArgs),
  lists:map(fun({Proto, Srv}) ->
        add_protocol(Proto, Srv)
    end, Protocols),
  lists:map(fun({Port, Srv}) ->
        add_protocol(Port, Srv)
    end, Ports),
  Reply.

%%%===================================================================
%%% Supervisor callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Whenever a supervisor is started using supervisor:start_link/[2,3],
%% this function is called by the new process to find out about
%% restart strategy, maximum restart frequency and child
%% specifications.
%%
%% @spec init(Args) -> {ok, {SupFlags, [ChildSpec]}} |
%%                     ignore |
%%                     {error, Reason}
%% @end
%%--------------------------------------------------------------------
init(StartArgs) ->
  trace("init"),
  ets:new(?MODULE, [set, public, named_table]),
  Weight = misc:get_env(?MODULE, weight, StartArgs),
  hooks:install(connection_accepted, Weight, fun ?MODULE:connection_accepted/4),
  hooks:install(connection_closed, Weight, fun ?MODULE:connection_closed/3),
  hooks:install(terminal_raw_data, Weight, fun ?MODULE:terminal_raw_data/5),
  {
    ok,
    {
      {one_for_one, 5, 10},
      [
        {
          proxy_pool,
          {proxy_pool, start_link, []},
          permanent,
          2000,
          worker,
          [proxy_pool]
        }
      ]
    }
  }.

%%%===================================================================
%%% Internal functions
%%%===================================================================
get_proxy(Pid) ->
  case ets:match(?MODULE, {Pid, '$1'}) of
    [] ->
      undefined;
    [[ProxyPid]] ->
      {ok, ProxyPid}
  end.

connect(_Pid, undefined, _Timeout) ->
  ok;
connect(Pid, {ok, ProxyPid}, _Timeout) ->
  ets:insert(?MODULE, {Pid, ProxyPid}),
  ok.

close(_Pid, undefined, _Timeout) ->
  ok;
close(Pid, {ok, ProxyPid}, Timeout) ->
  proxy_deliver:close(ProxyPid, Timeout),
  ets:delete(?MODULE, Pid),
  ok.

process_data(_Pid, _RawData, undefined, _Timeout) ->
  ok;
process_data(_Pid, RawData, {ok, ProxyPid}, Timeout) ->
  proxy_deliver:send(ProxyPid, RawData, Timeout),
  {ok, Answer} = proxy_deliver:recv(ProxyPid, Timeout),
  {ok, {?MODULE, {answer, Answer}}}.
