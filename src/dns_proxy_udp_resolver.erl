%%%-------------------------------------------------------------------
%%% @author Feather.et.ELF <andelf@gmail.com>
%%% @copyright (C) 2013, Feather.et.ELF
%%% @doc
%%%
%%% @end
%%% Created : 25 Apr 2013 by Feather.et.ELF <andelf@gmail.com>
%%%-------------------------------------------------------------------
-module(dns_proxy_udp_resolver).

-behaviour(gen_server).

%% API
-export([start_link/1]).
%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
	 terminate/2, code_change/3]).

-include_lib("kernel/src/inet_dns.hrl").
-define(SERVER, ?MODULE). 

-record(state, {sock,
		timeout,
		server_ip,
		server_port}).

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @spec start_link() -> {ok, Pid} | ignore | {error, Error}
%% @end
%%--------------------------------------------------------------------
start_link(Args) ->
    %% register with name
    %%gen_server:start_link({local, ?SERVER}, ?MODULE, Args, []).
    %% no register
    gen_server:start_link(?MODULE, Args, []).

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
    {stop, "conf can't be empty"};
init(Args) ->
    case proplists:get_value(ip, Args) of
	undefined ->
	    IPAddr = dns_utils:random_select(proplists:get_value(ip_pool, Args));
	_IP ->
	    IPAddr = _IP
    end,
    {ok, IP} = inet:ip(IPAddr),
    Port = 53,
    Timeout = proplists:get_value(timeout, Args, 3000),
    {ok, Sock} = gen_udp:open(0, [binary,{active,false}]),
    {ok, #state{sock=Sock, server_ip=IP, server_port=Port,
		timeout=Timeout}}.


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
handle_call({sync_send_dns_packet, Packet}, _From, State =
		#state{sock=Sock, server_ip=IP, server_port=Port,
		       timeout=Timeout}) when is_record(Packet, dns_rec) ->
    Id = (Packet#dns_rec.header)#dns_header.id,
    Data = inet_dns:encode(Packet),
    gen_udp:send(Sock, IP, Port, Data),
    Reply = handle_dns_response(Sock, Id, Timeout),
    {reply, Reply, State}.


handle_dns_response(Sock, Id, Timeout) ->
    case catch receive_dns_response(Sock, Id, Timeout) of
	{ok, Packet} ->
	    {ok, Packet};
	{error, timeout} ->
	    {error, timeout};
	{'EXIT', _} ->
	    %% skip bad packets in buffer
	    handle_dns_response(Sock, Id, Timeout)
    end.


receive_dns_response(Sock, Id, Timeout) ->
    case gen_udp:recv(Sock, 0, Timeout) of
	{ok, {_IP, _Port, Data}} ->
	    {ok, Packet} = inet_dns:decode(Data),
	    #dns_rec{header = #dns_header{id = Id, qr = true}} = Packet,
	    {ok, Packet};
	{error, timeout} ->
	    {error, timeout};
	{error, Other} ->
	    io:format("error ~p~n", [Other]),
	    {error, Other}
    end.
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
handle_cast(_Msg, State) ->
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
handle_info(_Info, State) ->
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
    
