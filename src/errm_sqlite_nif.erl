-module(errm_sqlite_nif).
-export([open/1, close/1, prepare/2, bind/2, step/1, finalize/1, exec/2, changes/1, last_insert_rowid/1]).
-on_load(init/0).
-include("include/errm_sqlite.hrl").

-spec init() -> ok.
init() ->
  NifPath = case code:priv_dir(errm_sqlite) of
    PrivDir when is_list(PrivDir) ->
      io:format("Found priv_dir~n"),
      io:format("priv_dir: ~p~n", [PrivDir]),
      filename:join([PrivDir, "errm_sqlite_nif"]);
    {error, bad_name} ->
      io:format("Could not find priv_dir~n"),
      case code:lib_dir(errm_sqlite) of
        {ok, LibDir} ->
          io:format("Found lib_dir~n"),
          io:format("lib_dir: ~p~n", [LibDir]),
          filename:join([LibDir, "priv", "errm_sqlite_nif"]);
        _ ->
          io:format("Could not find lib_dir~n"),
          "./priv/errm_sqlite_nif"
      end;
    _ ->
      io:format("Could not find priv_dir, and it wasnt bad_name~n"),
      "./priv/errm_sqlite_nif"
    end,

    NifPathStr = case NifPath of
      Path when is_list(Path) -> Path
    end,
    case erlang:load_nif(NifPathStr, 0) of
      ok -> ok;
      {error, Reason} -> erlang:error({nif_load_failed, Reason})
    end.

-spec open(Path :: string()) -> {ok, DbHandle :: db_handle()} | {error, Reason :: term()}.
open(_Path) -> erlang:nif_error(nif_not_loaded).

-spec close(DbHandle :: db_handle()) -> ok | busy.
close(_DbHandle) -> erlang:nif_error(nif_not_loaded).

-spec prepare(DbHandle :: db_handle(), Sql :: string()) -> {ok, StmtHandle :: stmt_handle()} | {error, Reason :: term()}.
prepare(_DbHandle, _Sql) -> erlang:nif_error(nif_not_loaded).

-spec bind(StmtHandle :: stmt_handle(), Params :: [term()]) -> ok | {error, Reason :: term()}.
bind(_StmtHandle, _Params) -> erlang:nif_error(nif_not_loaded).

-spec step(StmtHandle :: stmt_handle()) -> {ok, Columns :: map()} | {error, Reason :: term()} | done.
step(_StmtHandle) -> erlang:nif_error(nif_not_loaded).

-spec finalize(StmtHandle :: stmt_handle()) -> ok.
finalize(_StmtHandle) -> erlang:nif_error(nif_not_loaded).

-spec exec(DbHandle :: db_handle(), Sql :: string()) -> {ok, Changes :: integer()} | {error, Reason :: term()}.
exec(_DbHandle, _Sql) -> erlang:nif_error(nif_not_loaded).

-spec changes(DbHandle :: db_handle()) -> {ok, Changes :: integer()}.
changes(_DbHandle) -> erlang:nif_error(nif_not_loaded).

-spec last_insert_rowid(DbHandle :: db_handle()) -> {ok, RowId :: integer()}.
last_insert_rowid(_DbHandle) -> erlang:nif_error(nif_not_loaded).
