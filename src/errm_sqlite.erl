-module(errm_sqlite).
-export([query/2, query/3, exec/2, exec/3, transaction/2, open/1, close/1]).
-export([fold/5, fold/4, foreach/4, foreach/3, map/4, map/3]).
-export([first/2, first/3, scalar/2, scalar/3]).
-export([format/2]).
-include("include/errm_sqlite.hrl").

-spec query(Db :: db_handle(), Sql :: sql()) -> {ok, Cols :: [row()]} | {error, Reason :: term()}.
query(Db, Sql) -> query(Db, Sql, []).

-spec query(Db :: db_handle(), Sql :: sql(), Args :: bind_args()) -> {ok, Rows :: [row()]}.
query(Db, Sql, Args) -> with_stmt(Db, Sql, Args, fun consume_all/1).


-spec exec(db_handle(), sql()) -> {ok, non_neg_integer()} | {error, term()}.
exec(Db, Sql) ->
    exec(Db, Sql, []).

-spec exec(db_handle(), sql(), bind_args()) -> {ok, non_neg_integer()} | {error, term()}.
exec(Db, Sql, Args) ->
  with_stmt(Db, Sql, Args, fun(Stmt) ->
    consume_until_done(Stmt),
    changes_count(Db)
  end).


-spec transaction(Db :: db_handle(), Fun :: fun((db_handle()) -> T)) -> {ok, T} | {error, Reason :: term()}.
transaction(Db, Fun) ->
  case errm_sqlite_nif:exec(Db, "BEGIN") of
    {ok, _} ->
      try Fun(Db) of
        Result -> {ok, _} = errm_sqlite_nif:exec(Db, "COMMIT"), {ok, Result}
      catch
        Class:Reason:Stack ->
          errm_sqlite_nif:exec(Db, "ROLLBACK"),
          {error, {Class, Reason, Stack}}
      end;
    Error -> Error
  end.


-spec open(Path :: string()) -> {ok, Db :: db_handle()} | {error, Reason :: term()}.
open(Path) -> errm_sqlite_nif:open(Path).

-spec close(Db :: db_handle()) -> ok | busy.
close(Db) -> errm_sqlite_nif:close(Db).


-spec fold(Db :: db_handle(), Sql :: sql(), Args :: bind_args(), Acc, Fun :: fun((row(), Acc) -> Acc)) -> {ok, Acc} | {error, Reason :: term()}.
fold(Db, Sql, Args, Acc, Fun) -> with_stmt(Db, Sql, Args, fun(Stmt) -> fold_rows(Stmt, Fun, Acc) end).

-spec fold(Db :: db_handle(), Sql :: sql(), Acc, fun((row(), Acc) -> Acc)) -> {ok, Acc} | {error, Reason :: term()}.
fold(Db, Sql, Acc, Fun) -> fold(Db, Sql, [], Acc, Fun).

-spec foreach(Db :: db_handle(), Sql :: sql(), Args :: bind_args(), Fun :: fun((row()) -> term())) ->
  ok | {error, Reason :: term()}.
foreach(Db, Sql, Args, Fun) ->
  case fold(Db, Sql, Args, ok, fun(Row, _) -> Fun(Row) end) of
    {ok, _} -> ok;
    {error, Reason} -> {error, Reason}
  end.

-spec foreach(Db :: db_handle(), Sql :: sql(), Fun :: fun((row()) -> term())) -> ok | {error, Reason :: term()}.
foreach(Db, Sql, Fun) -> foreach(Db, Sql, [], Fun).

-spec map(Db :: db_handle(), Sql :: sql(), Args :: bind_args(), Fun :: fun((row()) -> T)) -> {ok, [T]} | {error, Reason :: term()}.
map(Db, Sql, Args, Fun) -> with_stmt(Db, Sql, Args, fun(Stmt) -> map_rows(Stmt, Fun) end).

-spec map(Db :: db_handle(), Sql :: sql(), Fun :: fun((row()) -> T)) -> {ok, [T]} | {error, Reason :: term()}.
map(Db, Sql, Fun) -> map(Db, Sql, [], Fun).


-spec first(Db :: db_handle(), Sql :: sql(), Args :: bind_args()) -> {ok, row()} | {error, term()}.
first(Db, Sql, Args) ->
  case query(Db, Sql, Args) of
    {ok, [Row | _]} -> {ok, Row};
    {ok, []} -> {error, not_found};
    _ -> {error, "Failed to fetch first row"}
  end.

-spec first(Db :: db_handle(), Sql :: sql()) -> {ok, row()} | {error, term()}.
first(Db, Sql) -> first(Db, Sql, []).

-spec scalar(Db :: db_handle(), Sql :: sql(), Args :: bind_args()) -> {ok, term()} | {error, Reason :: term()}.
scalar(Db, Sql, Args) ->
  case first(Db, Sql, Args) of
    {ok, Map} when map_size(Map) =:= 1 ->
      {ok, hd(maps:values(Map))};
    {ok, _Map} ->
      {error, not_a_single_column};
    Error ->
      Error
  end.

-spec scalar(Db :: db_handle(), Sql :: sql()) -> {ok, term()} | {error, Reason :: term()}.
scalar(Db, Sql) -> scalar(Db, Sql, []).

-spec format(Fmt :: io:format(), Data :: [term()]) -> string().
  format(Fmt, Data) ->
    lists:flatten(io_lib:format(Fmt, Data)).


with_stmt(Db, Sql, Args, Fold) ->
  case errm_sqlite_nif:prepare(Db, Sql) of
    {ok, Stmt} ->
      ok = errm_sqlite_nif:bind(Stmt, Args),
      try Fold(Stmt) of
        Result -> {ok, Result}
      after
        errm_sqlite_nif:finalize(Stmt)
      end;
    Error -> Error
  end.

consume_until_done(Stmt) ->
  case errm_sqlite_nif:step(Stmt) of
    done -> ok;
    {ok, _} -> consume_until_done(Stmt);
    {error, Reason} -> throw({error, Reason})
  end.

consume_all(Stmt) ->
  case errm_sqlite_nif:step(Stmt) of
    {ok, Map} -> [Map | consume_all(Stmt)];
    done -> [];
    Error -> throw(Error)
  end.

fold_rows(Stmt, Fun, Acc) ->
  case errm_sqlite_nif:step(Stmt) of
    {ok, Map} -> fold_rows(Stmt, Fun, Fun(Map, Acc));
    done -> Acc;
    {error, Reason} -> throw({error, Reason})
  end.

map_rows(Stmt, Fun) ->
  case errm_sqlite_nif:step(Stmt) of
    {ok, Map} -> [Fun(Map) | map_rows(Stmt, Fun)];
    done -> [];
    {error, Reason} -> throw({error, Reason})
  end.

changes_count(Db) ->
  {ok, Count} = errm_sqlite_nif:changes(Db),
  Count.
