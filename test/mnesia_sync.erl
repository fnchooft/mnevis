%% The contents of this file are subject to the Mozilla Public License
%% Version 1.1 (the "License"); you may not use this file except in
%% compliance with the License. You may obtain a copy of the License
%% at http://www.mozilla.org/MPL/
%%
%% Software distributed under the License is distributed on an "AS IS"
%% basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See
%% the License for the specific language governing rights and
%% limitations under the License.
%%
%% The Original Code is RabbitMQ.
%%
%% The Initial Developer of the Original Code is GoPivotal, Inc.
%% Copyright (c) 2007-2017 Pivotal Software, Inc.  All rights reserved.
%%

-module(mnesia_sync).

%% mnesia:sync_transaction/3 fails to guarantee that the log is flushed to disk
%% at commit. This module is an attempt to minimise the risk of data loss by
%% performing a coalesced log fsync. Unfortunately this is performed regardless
%% of whether or not the log was appended to.

-behaviour(gen_server).

-export([sync/0, get_time/0]).

-export([start_link/0, init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-define(SERVER, ?MODULE).

-record(state, {waiting, disc_node, time = 0}).

%%----------------------------------------------------------------------------

-spec sync() -> 'ok'.

%%----------------------------------------------------------------------------

start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

sync() ->
    gen_server:call(?SERVER, sync, infinity).

get_time() ->
    gen_server:call(?SERVER, get_time, infinity).

%%----------------------------------------------------------------------------

init([]) ->
    {ok, #state{disc_node = mnesia:system_info(use_dir), waiting = []}}.

handle_call(sync, _From, #state{disc_node = false} = State) ->
    {reply, ok, State};
handle_call(sync, From, #state{waiting = Waiting} = State) ->
    {noreply, State#state{waiting = [From | Waiting]}, 0};
handle_call(get_time, From, #state{time = Time} = State) ->
    {reply, Time, State#state{time = 0}};
handle_call(Request, _From, State) ->
    {stop, {unhandled_call, Request}, State}.

handle_cast(Request, State) ->
    {stop, {unhandled_cast, Request}, State}.

handle_info(timeout, #state{waiting = Waiting} = State) ->
    {Time, ok} = timer:tc(fun() ->
    ok = disk_log:sync(latest_log)
    end),
    _ = [gen_server:reply(From, ok) || From <- Waiting],
    {noreply, State#state{waiting = [], time = Time + State#state.time}};
handle_info(Message, State) ->
    {stop, {unhandled_info, Message}, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.
