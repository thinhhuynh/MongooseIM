%%%-------------------------------------------------------------------
%%% @author ludwikbukowski
%%% @copyright (C) 2018, Erlang Solutions Ltd.
%%% @doc
%%%
%%% @end
%%% Created : 30. Jan 2018 16:59
%%%-------------------------------------------------------------------
-module(mod_inbox_rdbms).
-author("ludwikbukowski").
-include("jlib.hrl").
-include("mongoose.hrl").
-include("mod_inbox.hrl").

%% API
-export([get_inbox/3,
         init/2,
         set_inbox/7,
         set_inbox_incr_unread/6,
         reset_unread/4,
         remove_inbox/3,
         clear_inbox/2]).

%% For specific backends
-export([esc_string/1, esc_int/1]).

%% ----------------------------------------------------------------------
%% API
%% ----------------------------------------------------------------------

init(VHost, _Options) ->
    %% To verify if current RDBMS backend is supported
    rdbms_specific_backend(VHost),
    ok.

-spec get_inbox(LUsername :: jid:luser(),
                LServer :: jid:lserver(),
                Params :: mod_inbox:get_inbox_params()) -> get_inbox_res().
get_inbox(LUsername, LServer, Params) ->
    case get_inbox_rdbms(LUsername, LServer, Params) of
        {selected, []} ->
            [];
        {selected, Res} ->
            [decode_row(LServer, R) || R <- Res]
    end.


-spec get_inbox_rdbms(LUser :: jid:luser(),
                      LServer :: jid:lserver(),
                      Params :: mod_inbox:get_inbox_params()) ->
    query_result().
get_inbox_rdbms(LUser, LServer, #{ order := Order } = Params) ->
    OrderSQL = order_to_sql(Order),
    BeginSQL = sql_and_where_timestamp(">=", maps:get(start, Params, undefined)),
    EndSQL = sql_and_where_timestamp("<=", maps:get('end', Params, undefined)),
    HiddenSQL = sql_and_where_unread_count(maps:get(hidden_read, Params, false)),
    Query = ["SELECT remote_bare_jid, content, unread_count, timestamp FROM inbox "
                 "WHERE luser=", esc_string(LUser),
                 " AND lserver=", esc_string(LServer),
                 BeginSQL, EndSQL, HiddenSQL,
                 " ORDER BY timestamp ", OrderSQL, ";"],
    mongoose_rdbms:sql_query(LServer, Query).

-spec set_inbox(Username, Server, ToBareJid, Content,
                Count, MsgId, Timestamp) -> inbox_write_res() when
                Username :: jid:luser(),
                Server :: jid:lserver(),
                ToBareJid :: binary(),
                Content :: binary(),
                Count :: binary(),
                MsgId :: binary(),
                Timestamp :: erlang:timestamp().
set_inbox(Username, Server, ToBareJid, Content, Count, MsgId, Timestamp) ->
    LUsername = jid:nodeprep(Username),
    LServer = jid:nameprep(Server),
    LToBareJid = jid:nameprep(ToBareJid),
    BackendModule = rdbms_specific_backend(Server),
    NumericTimestamp = usec:from_now(Timestamp),
    Res = BackendModule:set_inbox(LUsername, LServer, LToBareJid,
                                  Content, Count, MsgId, NumericTimestamp),
    %% MySQL returns 1 when an upsert is an insert
    %% and 2, when an upsert acts as update
    ok = check_result(Res, [1, 2]).

-spec remove_inbox(User :: binary(),
    Server :: binary(),
    ToBareJid :: binary()) -> ok.
remove_inbox(Username, Server, ToBareJid) ->
    LUsername = jid:nodeprep(Username),
    LServer = jid:nameprep(Server),
    LToBareJid = jid:nameprep(ToBareJid),
    Res = remove_inbox_rdbms(LUsername, LServer, LToBareJid),
    check_result(Res).

-spec remove_inbox_rdbms(Username :: jid:luser(),
                         Server :: jid:lserver(),
                         ToBareJid :: binary()) -> query_result().
remove_inbox_rdbms(Username, Server, ToBareJid) ->
    mongoose_rdbms:sql_query(Server, ["delete from inbox where luser=",
        esc_string(Username), " and lserver=", esc_string(Server),
        " and remote_bare_jid=",
        esc_string(ToBareJid), ";"]).

-spec set_inbox_incr_unread(Username :: binary(),
                            Server :: binary(),
                            ToBareJid :: binary(),
                            Content :: binary(),
                            MsgId :: binary(),
                            Timestamp :: erlang:timestamp()) -> ok.
set_inbox_incr_unread(Username, Server, ToBareJid, Content, MsgId, Timestamp) ->
    LUsername = jid:nodeprep(Username),
    LServer = jid:nameprep(Server),
    LToBareJid = jid:nameprep(ToBareJid),
    BackendModule = rdbms_specific_backend(Server),
    NumericTimestamp = usec:from_now(Timestamp),
    Res = BackendModule:set_inbox_incr_unread(LUsername, LServer, LToBareJid,
                                              Content, MsgId, NumericTimestamp),
    %% psql will always return {updated, 1}
    %% but mysql will return {updated, 2} if it overwrites the row
    check_result(Res).

-spec reset_unread(User :: binary(),
                   Server :: binary(),
                   BareJid :: binary(),
                   MsgId :: binary()) -> ok.
reset_unread(Username, Server, ToBareJid, MsgId) ->
    LUsername = jid:nodeprep(Username),
    LServer = jid:nameprep(Server),
    LToBareJid = jid:nameprep(ToBareJid),
    Res = reset_inbox_unread_rdbms(LUsername, LServer, LToBareJid, MsgId),
    check_result(Res).

-spec reset_inbox_unread_rdbms(Username :: jid:luser(),
                               Server :: jid:lserver(),
                               ToBareJid :: binary(),
                               MsgId :: binary()) -> query_result().
reset_inbox_unread_rdbms(Username, Server, ToBareJid, MsgId) ->
    mongoose_rdbms:sql_query(Server, ["update inbox set unread_count=0 where luser=",
        esc_string(Username), " and lserver=", esc_string(Server), " and remote_bare_jid=",
        esc_string(ToBareJid), " and msg_id=", esc_string(MsgId), ";"]).

-spec clear_inbox(Username :: binary(), Server :: binary()) -> ok.
clear_inbox(Username, Server) ->
    LUsername = jid:nodeprep(Username),
    LServer = jid:nameprep(Server),
    Res = clear_inbox_rdbms(LUsername, LServer),
    check_result(Res).

-spec esc_string(binary() | string()) -> mongoose_rdbms:sql_query_part().
esc_string(String) ->
    mongoose_rdbms:use_escaped_string(mongoose_rdbms:escape_string(String)).

-spec esc_int(integer()) -> mongoose_rdbms:sql_query_part().
esc_int(Integer) ->
    mongoose_rdbms:use_escaped_integer(mongoose_rdbms:escape_integer(Integer)).


%% ----------------------------------------------------------------------
%% Internal functions
%% ----------------------------------------------------------------------

-spec order_to_sql(Order :: asc | desc) -> binary().
order_to_sql(asc) -> <<"ASC">>;
order_to_sql(desc) -> <<"DESC">>.

-spec sql_and_where_timestamp(Operator :: string(), Timestamp :: erlang:timestamp()) -> iolist().
sql_and_where_timestamp(_Operator, undefined) ->
    [];
sql_and_where_timestamp(Operator, Timestamp) ->
    NumericTimestamp = usec:from_now(Timestamp),
    [" AND timestamp ", Operator, esc_int(NumericTimestamp)].

-spec sql_and_where_unread_count(HiddenRead :: boolean()) -> iolist().
sql_and_where_unread_count(true) ->
    [" AND  unread_count ", " > ", <<"0">>];
sql_and_where_unread_count(_) ->
    [].

-spec clear_inbox_rdbms(Username :: jid:luser(), Server :: jid:lserver()) -> query_result().
clear_inbox_rdbms(Username, Server) ->
    mongoose_rdbms:sql_query(Server, ["delete from inbox where luser=",
        esc_string(Username), " and lserver=", esc_string(Server), ";"]).

-spec decode_row(host(), {username(), binary(), count_bin(), non_neg_integer() | binary()}) ->
    inbox_res().
decode_row(LServer, {Username, Content, Count, Timestamp}) ->
    Pool = mongoose_rdbms_sup:pool(LServer),
    Data = mongoose_rdbms:unescape_binary(Pool, Content),
    BCount = count_to_bin(Count),
    NumericTimestamp = mongoose_rdbms:result_to_integer(Timestamp),
    {Username, Data, BCount, usec:to_now(NumericTimestamp)}.


rdbms_specific_backend(Host) ->
    case {mongoose_rdbms:db_engine(Host), mongoose_rdbms_type:get()} of
        {mysql, _} -> mod_inbox_rdbms_mysql;
        {pgsql, _} -> mod_inbox_rdbms_pgsql;
        {odbc, mssql} -> mod_inbox_rdbms_mssql;
        NotSupported -> erlang:error({rdbms_not_supported, NotSupported})
    end.

count_to_bin(Count) when is_integer(Count) -> integer_to_binary(Count);
count_to_bin(Count) when is_binary(Count) -> Count.

check_result({updated, Val}, ValList) when is_list(ValList) ->
    case lists:member(Val, ValList) of
        true ->
            ok;
        _ ->
            {error, {expected_does_not_match, Val, ValList}}
    end;
check_result({updated, Val}, Val) ->
    ok;
check_result({updated, Res}, Exp) ->
    {error, {expected_does_not_match, Exp, Res}};
check_result(Result, _) ->
    {error, {bad_result, Result}}.

%% TODO
check_result({updated, _, [{Val}]}) ->
    {ok, Val};

check_result({updated, _}) ->
    ok;
check_result(Result) ->
    {error, {bad_result, Result}}.
