-module(errm_sqlite_migrate).
-export([migrate/1, migrate/2, migrate/3]).
-include("include/errm_sqlite.hrl").

-spec migrate(Db :: db_handle()) -> ok.
migrate(Db) ->
  migrate(Db, "migrations").

-spec migrate(Db :: db_handle(), Dir :: file:filename()) -> ok.
migrate(Db, Dir) ->
  migrate(Db, Dir, #{}).

-spec migrate(Db :: db_handle(), Dir :: file:filename(), Opts :: map()) -> ok.
migrate(Db, Dir, Opts) ->
  Table = maps:get(table, Opts, "_migrations"),
  ensure_migrations_table(Db, Table),
  Pattern0 = filename:join([Dir, "*.sql"]),
  Pattern = case Pattern0 of
    Binary when is_binary(Binary) -> binary_to_list(Binary);
    List when is_list(List) -> List
  end,
  Files = lists:sort(filelib:wildcard(Pattern)),
  lists:foreach(fun(File) -> run_migration(Db, File, Table) end, Files).


ensure_migrations_table(Db, Table) ->
  {ok, _} = errm_sqlite:exec(Db, errm_sqlite:format("CREATE TABLE IF NOT EXISTS ~s (name TEXT PRIMARY KEY, ran_at TEXT)", [Table])),
  ok.

run_migration(Db, File, Table) ->
  Name0 = filename:basename(File),
  Name = case Name0 of
    List when is_list(List) -> list_to_binary(List);
    Binary when is_binary(Binary) -> Binary
  end,
  case errm_sqlite:query(Db, errm_sqlite:format("SELECT name FROM ~s WHERE name = ?", [Table]), [Name]) of
    {ok, []} ->
      {ok, Sql} = file:read_file(File),
      errm_sqlite:transaction(Db, fun(Db1) ->
        {ok, _} = errm_sqlite:exec(Db1, binary_to_list(Sql)),
        {ok, _} = errm_sqlite:exec(Db1, errm_sqlite:format("INSERT INTO ~s (name, ran_at) VALUES (?, datetime('now'))", [Table]), [Name])
      end),
      io:format("[errm_sqlite] Applied migration: ~s~n", [Name]);
    {ok, [_]} ->
      already_applied
  end.

