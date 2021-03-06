%%--------------------------------------------------------------------
%% Copyright (c) 2013-2018 EMQ Enterprise, Inc. (http://emqtt.io)
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%--------------------------------------------------------------------

-module(emq_redis_hook).

-include_lib("emqttd/include/emqttd.hrl").

-include("emq_redis_hook.hrl").

-export([load/0, unload/0]).

-export([on_client_connected/3, on_client_disconnected/3]).

-export([on_client_subscribe/4, on_client_unsubscribe/4]).

-export([on_session_created/3, on_session_subscribed/4, on_session_unsubscribed/4,
         on_session_terminated/4]).

-export([on_message_publish/2, on_message_delivered/4, on_message_acked/4]).

-define(LOG(Level, Format, Args), lager:Level("Redis Hook: " ++ Format, Args)).

load() ->
    lists:foreach(fun({Hook, Fun, Filter}) ->
        load_(Hook, binary_to_atom(Fun, utf8), Filter, {Filter})
    end, parse_rule(application:get_env(?APP, rules, []))).

unload() ->
    lists:foreach(fun({Hook, Fun, Filter}) ->
        unload_(Hook, binary_to_atom(Fun, utf8), Filter)
    end, parse_rule(application:get_env(?APP, rules, []))).

%%--------------------------------------------------------------------
%% Client connected
%%--------------------------------------------------------------------

on_client_connected(0, Client = #mqtt_client{client_id = ClientId, username = Username}, _Env) ->
%    Params = [{action, client_connected},
%             {client_id, ClientId},
%              {username, Username},
%              {conn_ack, 0}],
    ?LOG(info, "on_client_connected: ~s ",  [ClientId]),
    send_redis_request_value("true", ClientId),
    add_redis_client_value(ClientId),
    {ok, Client};

on_client_connected(_, Client = #mqtt_client{}, _Env) ->
    {ok, Client}.





%%--------------------------------------------------------------------
%% Client disconnected
%%--------------------------------------------------------------------

on_client_disconnected(auth_failure, #mqtt_client{}, _Env) ->
    ok;
on_client_disconnected({shutdown, Reason}, Client, _Env) when is_atom(Reason) ->
    on_client_disconnected(Reason, Client, _Env);
on_client_disconnected(Reason, _Client = #mqtt_client{client_id = ClientId, username = Username}, _Env)
    when is_atom(Reason) ->
%    Params = [{action, client_disconnected},
%              {client_id, ClientId},
%              {username, Username},
%              {reason, Reason}],
    send_redis_request_value("false", ClientId),
    ok;

on_client_disconnected(Reason, _Client, _Env) ->
    ?LOG(error, "Client disconnected, cannot encode reason: ~p", [Reason]),
    ok.

%%--------------------------------------------------------------------
%% Client subscribe
%%--------------------------------------------------------------------

on_client_subscribe(ClientId, Username, TopicTable, {Filter}) ->
    lists:foreach(fun({Topic, Opts}) ->
        with_filter(fun() ->
            Params = [{action, client_subscribe},
                      {client_id, ClientId},
                      {username, Username},
                      {topic, Topic},
                      {opts, Opts}],
            send_redis_request(Params)
        end, Topic, Filter)
    end, TopicTable).

%%--------------------------------------------------------------------
%% Client unsubscribe
%%--------------------------------------------------------------------

on_client_unsubscribe(ClientId, Username, TopicTable, {Filter}) ->
    lists:foreach(fun({Topic, Opts}) ->
        with_filter(fun() ->
            Params = [{action, client_unsubscribe},
                      {client_id, ClientId},
                      {username, Username},
                      {topic, Topic},
                      {opts, Opts}],
            send_redis_request(Params)
        end, Topic, Filter)
    end, TopicTable).

%%--------------------------------------------------------------------
%% Session created
%%--------------------------------------------------------------------

on_session_created(ClientId, Username, _Env) ->
    Params = [{action, session_created},
              {client_id, ClientId},
              {username, Username}],
    send_redis_request(Params),
    ok.

%%--------------------------------------------------------------------
%% Session subscribed
%%--------------------------------------------------------------------

on_session_subscribed(ClientId, Username, {Topic, Opts}, {Filter}) ->
    with_filter(fun() ->
        Params = [{action, session_subscribed},
                  {client_id, ClientId},
                  {username, Username},
                  {topic, Topic},
                  {opts, Opts}],
        send_redis_request(Params)
    end, Topic, Filter).

%%--------------------------------------------------------------------
%% Session unsubscribed
%%--------------------------------------------------------------------

on_session_unsubscribed(ClientId, Username, {Topic, _Opts}, {Filter}) ->
    with_filter(fun() ->
        Params = [{action, session_unsubscribed},
                  {client_id, ClientId},
                  {username, Username},
                  {topic, Topic}],
        send_redis_request(Params)
    end, Topic, Filter).

%%--------------------------------------------------------------------
%% Session terminated
%%--------------------------------------------------------------------

on_session_terminated(ClientId, Username, {shutdown, Reason}, Env) when is_atom(Reason) ->
    on_session_terminated(ClientId, Username, Reason, Env);
on_session_terminated(ClientId, Username, Reason, _Env) when is_atom(Reason) ->
    Params = [{action, session_terminated},
              {client_id, ClientId},
              {username, Username},
              {reason, Reason}],
    send_redis_request(Params),
    ok;
on_session_terminated(_ClientId, _Username, Reason, _Env) ->
    ?LOG(error, "Session terminated, cannot encode the reason: ~p", [Reason]),
    ok.

%%--------------------------------------------------------------------
%% Message publish
%%--------------------------------------------------------------------

on_message_publish(Message = #mqtt_message{topic = <<"$SYS/", _/binary>>}, _Env) ->
    {ok, Message};
on_message_publish(Message = #mqtt_message{topic = Topic}, {Filter}) ->
    with_filter(fun() ->
        {FromClientId, FromUsername} = format_from(Message#mqtt_message.from),
        Params = [{action, message_publish},
                  {from_client_id, FromClientId},
                  {from_username, FromUsername},
                  {topic, Message#mqtt_message.topic},
                  {qos, Message#mqtt_message.qos},
                  {retain, Message#mqtt_message.retain},
                  {payload, Message#mqtt_message.payload},
                  {ts, emqttd_time:now_secs(Message#mqtt_message.timestamp)}],
        send_redis_request(Params),
        {ok, Message}
    end, Message, Topic, Filter).

%%--------------------------------------------------------------------
%% Message delivered
%%--------------------------------------------------------------------

on_message_delivered(ClientId, Username, Message = #mqtt_message{topic = Topic}, {Filter}) ->
    with_filter(fun() ->
        {FromClientId, FromUsername} = format_from(Message#mqtt_message.from),
        Params = [{action, message_delivered},
                  {client_id, ClientId},
                  {username, Username},
                  {from_client_id, FromClientId},
                  {from_username, FromUsername},
                  {topic, Message#mqtt_message.topic},
                  {qos, Message#mqtt_message.qos},
                  {retain, Message#mqtt_message.retain},
                  {payload, Message#mqtt_message.payload},
                  {ts, emqttd_time:now_secs(Message#mqtt_message.timestamp)}],
        send_redis_request(Params)
    end, Topic, Filter).

%%--------------------------------------------------------------------
%% Message acked
%%--------------------------------------------------------------------

on_message_acked(ClientId, Username, Message = #mqtt_message{topic = Topic}, {Filter}) ->
    with_filter(fun() ->
        {FromClientId, FromUsername} = format_from(Message#mqtt_message.from),
        Params = [{action, message_acked},
                  {client_id, ClientId},
                  {username, Username},
                  {from_client_id, FromClientId},
                  {from_username, FromUsername},
                  {topic, Message#mqtt_message.topic},
                  {qos, Message#mqtt_message.qos},
                  {retain, Message#mqtt_message.retain},
                  {payload, Message#mqtt_message.payload},
                  {ts, emqttd_time:now_secs(Message#mqtt_message.timestamp)}],
        send_redis_request(Params)
    end, Topic, Filter).

%%--------------------------------------------------------------------
%% Internal functions
%%--------------------------------------------------------------------

send_redis_request(Params) ->
  ?LOG(debug, "Params: ~p ", [Params]),
  Params1 = jsx:encode(Params),
  Key = application:get_env(?APP, key, "message"),
  ?LOG(debug, "Params1: ~p  key: ~p ", [Params, Key]),
  case emq_redis_hook_cli:q(["LPUSH", Key, Params1]) of
        {ok, _} -> 
            ok;
        {error, Reason} ->
      ?LOG(error, "Redis lpush error: ~p", [Reason]), ok
    end.

send_redis_request_value(Value, ClientId) ->
  %Key = application:get_env(?APP, key, "emqmessage"),
  Keycon = "LINE:"++ClientId,
  BinValue=list_to_binary(Value),
  case emq_redis_hook_cli:q(["GET", Keycon]) of
    {ok, BinValue} ->
    	ok;
    {error, Reason} ->
      ?LOG(error, "send_redis_request_value edis get error: ~p", [Reason]), ok;
    {ok, _} ->
      %?LOG(error, "Redis get ok _:~p",[Keycon]),
      set_redis_client_value(Keycon, Value)

  end.

set_redis_client_value(Key, Value) ->
 case emq_redis_hook_cli:q(["SET", Key, Value]) of
    {ok, _} ->
      % ?LOG(error, "Redis set ok _ key:~p value:~p ",[Key, Value]),i
      ok;
    {error, Reason} ->
      ?LOG(error, "set_redis_client_value Redis set error: ~p", [Reason]), ok
  end.

add_redis_client_value(Key) ->
  case string:tokens(binary_to_list(Key), "/") of
	[Nsrsbh, Fjh] -> 
  		%?LOG(error, "string tokens narsbh:~p fjh:~p ", [Nsrsbh,Fjh]),
		KeyNsr = "CONNECTED:"++Nsrsbh,
		BinFjh = list_to_binary(Fjh),
		case emq_redis_hook_cli:q(["GET", KeyNsr]) of
    			{ok, BinFjh} ->
        			%?LOG(error, "add_redis_client_value no use to ring tokens narsbh:~p fjh:~p ", [Nsrsbh,Fjh]),
				ok;
    			{error, Reason} ->
      				?LOG(error, "add_redis_client_value edis get error: ~p", [Reason]), ok;
    			{ok, _} ->
				%?LOG(error, "add_redis_client_value string tokens narsbh:~p fjh:~p ", [Nsrsbh,Fjh]),
				set_redis_client_value(KeyNsr,Fjh)
		end;
	_ -> 
		?LOG(error, "add_redis_client_value tokerns err,the Key value is:~s \n",[Key])
  end.


parse_rule(Rules) ->
    parse_rule(Rules, []).
parse_rule([], Acc) ->
    lists:reverse(Acc);
parse_rule([{Rule, Conf} | Rules], Acc) ->
    {_, Params} = mochijson2:decode(Conf),
    Action = proplists:get_value(<<"action">>, Params),
    Filter = proplists:get_value(<<"topic">>, Params),
    parse_rule(Rules, [{list_to_atom(Rule), Action, Filter} | Acc]).

with_filter(Fun, _, undefined) ->
    Fun(), ok;
with_filter(Fun, Topic, Filter) ->
    case emqttd_topic:match(Topic, Filter) of
        true  -> Fun(), ok;
        false -> ok
    end.

with_filter(Fun, _, _, undefined) ->
    Fun();
with_filter(Fun, Msg, Topic, Filter) ->
    case emqttd_topic:match(Topic, Filter) of
        true  -> Fun();
        false -> {ok, Msg}
    end.

format_from({ClientId, Username}) ->
    {ClientId, Username};
format_from(From) when is_atom(From) ->
    {a2b(From), a2b(From)};
format_from(_) ->
    {<<>>, <<>>}.

a2b(A) -> erlang:atom_to_binary(A, utf8).

load_(Hook, Fun, Filter, Params) ->
    case Hook of
        'client.connected'    -> emqttd:hook(Hook, {Filter, fun ?MODULE:Fun/3}, [Params]);
        'client.disconnected' -> emqttd:hook(Hook, {Filter, fun ?MODULE:Fun/3}, [Params]);
        'client.subscribe'    -> emqttd:hook(Hook, {Filter, fun ?MODULE:Fun/4}, [Params]);
        'client.unsubscribe'  -> emqttd:hook(Hook, {Filter, fun ?MODULE:Fun/4}, [Params]);
        'session.created'     -> emqttd:hook(Hook, {Filter, fun ?MODULE:Fun/3}, [Params]);
        'session.subscribed'  -> emqttd:hook(Hook, {Filter, fun ?MODULE:Fun/4}, [Params]);
        'session.unsubscribed'-> emqttd:hook(Hook, {Filter, fun ?MODULE:Fun/4}, [Params]);
        'session.terminated'  -> emqttd:hook(Hook, {Filter, fun ?MODULE:Fun/4}, [Params]);
        'message.publish'     -> emqttd:hook(Hook, {Filter, fun ?MODULE:Fun/2}, [Params]);
        'message.acked'       -> emqttd:hook(Hook, {Filter, fun ?MODULE:Fun/4}, [Params]);
        'message.delivered'   -> emqttd:hook(Hook, {Filter, fun ?MODULE:Fun/4}, [Params])
    end.

unload_(Hook, Fun, Filter) ->
    case Hook of
        'client.connected'    -> emqttd:unhook(Hook, {Filter, fun ?MODULE:Fun/3});
        'client.disconnected' -> emqttd:unhook(Hook, {Filter, fun ?MODULE:Fun/3});
        'client.subscribe'    -> emqttd:unhook(Hook, {Filter, fun ?MODULE:Fun/4});
        'client.unsubscribe'  -> emqttd:unhook(Hook, {Filter, fun ?MODULE:Fun/4});
        'session.created'     -> emqttd:unhook(Hook, {Filter, fun ?MODULE:Fun/3});
        'session.subscribed'  -> emqttd:unhook(Hook, {Filter, fun ?MODULE:Fun/4});
        'session.unsubscribed'-> emqttd:unhook(Hook, {Filter, fun ?MODULE:Fun/4});
        'session.terminated'  -> emqttd:unhook(Hook, {Filter, fun ?MODULE:Fun/4});
        'message.publish'     -> emqttd:unhook(Hook, {Filter, fun ?MODULE:Fun/2});
        'message.acked'       -> emqttd:unhook(Hook, {Filter, fun ?MODULE:Fun/4});
        'message.delivered'   -> emqttd:unhook(Hook, {Filter, fun ?MODULE:Fun/4})
    end.

