-module(errm_sqlite_tests).
-include_lib("eunit/include/eunit.hrl").

db_path() -> ":memory:".

with_db(Fun) ->
  {ok, Db} = errm_sqlite_nif:open(db_path()),
  try Fun(Db) after
    errm_sqlite_nif:close(Db)
  end.

with_migration_dir(Fun) ->
  Dir = "test_migrations_" ++ integer_to_list(erlang:unique_integer([positive])),
  ok = file:make_dir(Dir),
  try Fun(Dir) after
    _ = file:del_dir_r(Dir)
  end.

write_migration(Dir, Name, Sql) ->
  ok = file:write_file(filename:join(Dir, Name), Sql).

create_fixture(Db) ->
  {ok, _} = errm_sqlite_nif:exec(Db,
    "CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT, age INTEGER)"),
  {ok, _} = errm_sqlite_nif:exec(Db,
    "INSERT INTO users (id, name, age) VALUES (1, 'Alice', 30), (2, 'Bob', 25), (3, 'Charlie', 35)").


%% --- connection ---

open_close() ->
  {ok, Db} = errm_sqlite_nif:open(db_path()),
  ?assert(is_reference(Db)),
  ?assertEqual(ok, errm_sqlite_nif:close(Db)).

close_twice() ->
  {ok, Db} = errm_sqlite_nif:open(db_path()),
  ok = errm_sqlite_nif:close(Db),
  ?assertEqual(ok, errm_sqlite_nif:close(Db)).

open_bad_path() ->
  {error, _} = errm_sqlite_nif:open("/nonexistent/dir/test.db").


%% --- raw nif exec ---

exec_nif_create() ->
  with_db(fun(Db) ->
    {ok, 0} = errm_sqlite_nif:exec(Db, "CREATE TABLE test (id INTEGER PRIMARY KEY, name TEXT)")
  end).

exec_nif_insert_changes() ->
  with_db(fun(Db) ->
    {ok, _} = errm_sqlite_nif:exec(Db, "CREATE TABLE test (id INTEGER PRIMARY KEY, name TEXT)"),
    {ok, _} = errm_sqlite_nif:exec(Db, "INSERT INTO test (name) VALUES ('Alice')"),
    {ok, _} = errm_sqlite_nif:exec(Db, "INSERT INTO test (name) VALUES ('Bob')"),
    {ok, 1} = errm_sqlite_nif:changes(Db)
  end).

exec_nif_multi_stmt() ->
  with_db(fun(Db) ->
    {ok, _} = errm_sqlite_nif:exec(Db,
      "CREATE TABLE t (x); INSERT INTO t VALUES (1); INSERT INTO t VALUES (2)"),
    {ok, [R1, R2]} = errm_sqlite:query(Db, "SELECT x FROM t ORDER BY x"),
    ?assertEqual(1, maps:get("x", R1)),
    ?assertEqual(2, maps:get("x", R2))
  end).

exec_nif_invalid() ->
  with_db(fun(Db) ->
    {ok, _} = errm_sqlite_nif:exec(Db, "CREATE TABLE t (x)"),
    {error, _} = errm_sqlite_nif:exec(Db, "INSERT INTO t VALUES (")
  end).

exec_nif_error() ->
  with_db(fun(Db) ->
    {error, _} = errm_sqlite_nif:exec(Db, "SELECT * FROM nonexistent_table")
  end).

last_insert_rowid() ->
  with_db(fun(Db) ->
    {ok, _} = errm_sqlite_nif:exec(Db, "CREATE TABLE test (id INTEGER PRIMARY KEY, name TEXT)"),
    {ok, _} = errm_sqlite_nif:exec(Db, "INSERT INTO test (name) VALUES ('Alice')"),
    {ok, 1} = errm_sqlite_nif:last_insert_rowid(Db),
    {ok, _} = errm_sqlite_nif:exec(Db, "INSERT INTO test (name) VALUES ('Bob')"),
    {ok, 2} = errm_sqlite_nif:last_insert_rowid(Db)
  end).

last_insert_rowid_empty() ->
  with_db(fun(Db) ->
    {ok, 0} = errm_sqlite_nif:last_insert_rowid(Db)
  end).


%% --- prepare / bind / step / finalize ---

prepare_bind_step() ->
  with_db(fun(Db) ->
    {ok, _} = errm_sqlite_nif:exec(Db, "CREATE TABLE test (id INTEGER PRIMARY KEY, name TEXT)"),
    {ok, _} = errm_sqlite_nif:exec(Db, "INSERT INTO test (id, name) VALUES (1, 'Alice'), (2, 'Bob')"),
    {ok, Stmt} = errm_sqlite_nif:prepare(Db, "SELECT * FROM test WHERE id = ?"),
    ?assert(is_reference(Stmt)),
    ok = errm_sqlite_nif:bind(Stmt, [1]),
    {ok, #{}} = errm_sqlite_nif:step(Stmt),
    ?assertEqual(done, errm_sqlite_nif:step(Stmt)),
    ok = errm_sqlite_nif:finalize(Stmt)
  end).

bind_null() ->
  with_db(fun(Db) ->
    {ok, _} = errm_sqlite_nif:exec(Db, "CREATE TABLE t (x)"),
    {ok, Stmt} = errm_sqlite_nif:prepare(Db, "INSERT INTO t VALUES (?)"),
    ok = errm_sqlite_nif:bind(Stmt, [null]),
    done = errm_sqlite_nif:step(Stmt),
    ok = errm_sqlite_nif:finalize(Stmt),
    {ok, 1} = errm_sqlite:exec(Db, "SELECT * FROM t")
  end).

bind_all_types() ->
  with_db(fun(Db) ->
    {ok, _} = errm_sqlite_nif:exec(Db, "CREATE TABLE t (i INTEGER, f FLOAT, t TEXT, b BLOB)"),
    {ok, Stmt} = errm_sqlite_nif:prepare(Db, "INSERT INTO t VALUES (?, ?, ?, ?)"),
    ok = errm_sqlite_nif:bind(Stmt, [42, 3.14, ~"hello", <<1,2,3>>]),
    done = errm_sqlite_nif:step(Stmt),
    ok = errm_sqlite_nif:finalize(Stmt),
    {ok, Stmt2} = errm_sqlite_nif:prepare(Db, "SELECT * FROM t"),
    ok = errm_sqlite_nif:bind(Stmt2, []),
    {ok, Map} = errm_sqlite_nif:step(Stmt2),
    ?assertEqual(4, map_size(Map)),
    ?assertEqual(42, maps:get("i", Map)),
    ?assertEqual(3.14, maps:get("f", Map)),
    ?assertEqual("hello", maps:get("t", Map)),
    ?assertEqual([1,2,3], maps:get("b", Map)),
    ok = errm_sqlite_nif:finalize(Stmt2)
  end).

prepare_error() ->
  with_db(fun(Db) ->
    {error, _} = errm_sqlite_nif:prepare(Db, "SELECT * FROM")
  end).

finalize_no_leak() ->
  with_db(fun(Db) ->
    {ok, Stmt} = errm_sqlite_nif:prepare(Db, "SELECT 1"),
    ok = errm_sqlite_nif:bind(Stmt, []),
    ok = errm_sqlite_nif:finalize(Stmt),
    {ok, _} = errm_sqlite_nif:exec(Db, "SELECT 1")
  end).


%% --- high level query ---

query_all() ->
  with_db(fun(Db) ->
    create_fixture(Db),
    {ok, Rows} = errm_sqlite:query(Db, "SELECT * FROM users ORDER BY id"),
    ?assertEqual(3, length(Rows)),
    [
     #{"id" := 1, "name" := "Alice",   "age" := 30},
     #{"id" := 2, "name" := "Bob",     "age" := 25},
     #{"id" := 3, "name" := "Charlie", "age" := 35}
    ] = Rows
  end).

query_with_args() ->
  with_db(fun(Db) ->
    create_fixture(Db),
    {ok, [Row]} = errm_sqlite:query(Db, "SELECT * FROM users WHERE id = ?", [2]),
    ?assertEqual(2, maps:get("id", Row)),
    ?assertEqual("Bob", maps:get("name", Row))
  end).

query_empty() ->
  with_db(fun(Db) ->
    {ok, _} = errm_sqlite_nif:exec(Db, "CREATE TABLE empty (x INTEGER)"),
    {ok, []} = errm_sqlite:query(Db, "SELECT * FROM empty")
  end).


%% --- high level exec ---

exec_update() ->
  with_db(fun(Db) ->
    create_fixture(Db),
    {ok, 1} = errm_sqlite:exec(Db, "UPDATE users SET age = age + 1 where age < 30")
  end).

exec_with_args() ->
  with_db(fun(Db) ->
    create_fixture(Db),
    {ok, 1} = errm_sqlite:exec(Db, "DELETE FROM users WHERE name = ?", [~"Bob"])
  end).

exec_multi_stmt() ->
  with_db(fun(Db) ->
    {ok, _} = errm_sqlite:exec(Db,
      "CREATE TABLE t (x); INSERT INTO t VALUES (1); INSERT INTO t VALUES (2)"),
    {ok, [R1, R2]} = errm_sqlite:query(Db, "SELECT x FROM t ORDER BY x"),
    ?assertEqual(1, maps:get("x", R1)),
    ?assertEqual(2, maps:get("x", R2))
  end).


%% --- transactions ---

transaction_commit() ->
  with_db(fun(Db) ->
    create_fixture(Db),
    {ok, Result} = errm_sqlite:transaction(Db, fun(Db1) ->
      {ok, _} = errm_sqlite:exec(Db1, "INSERT INTO users (name, age) VALUES ('Dave', 40)"),
      {ok, [Row]} = errm_sqlite:query(Db1, "SELECT COUNT(*) AS cnt FROM users"),
      maps:get("cnt", Row)
    end),
    ?assertEqual(4, Result),
    {ok, [DaveRow]} = errm_sqlite:query(Db, "SELECT name FROM users WHERE name = 'Dave'"),
    ?assertEqual("Dave", maps:get("name", DaveRow))
  end).

transaction_rollback() ->
  with_db(fun(Db) ->
    create_fixture(Db),
    {error, {throw, testing, _}} = errm_sqlite:transaction(Db, fun(Db1) ->
      {ok, _} = errm_sqlite:exec(Db1, "INSERT INTO users (name, age) VALUES ('Dave', 40)"),
      throw(testing)
    end),
    {ok, []} = errm_sqlite:query(Db, "SELECT name FROM users WHERE name = 'Dave'")
  end).


%% --- fold / foreach / map ---

fold() ->
  with_db(fun(Db) ->
    create_fixture(Db),
    {ok, Names} = errm_sqlite:fold(Db, "SELECT name FROM users ORDER BY id", [], [],
      fun(Row, Acc) -> [maps:get("name", Row) | Acc] end),
    ?assertEqual(["Charlie", "Bob", "Alice"], Names)
  end).

fold_empty() ->
  with_db(fun(Db) ->
    {ok, _} = errm_sqlite_nif:exec(Db, "CREATE TABLE t (x INTEGER)"),
    {ok, Acc} = errm_sqlite:fold(Db, "SELECT * FROM t", [], [], fun(Row, Acc0) -> [Row | Acc0] end),
    ?assertEqual([], Acc)
  end).

foreach() ->
  with_db(fun(Db) ->
    create_fixture(Db),
    Ref = make_ref(),
    Self = self(),
    ok = errm_sqlite:foreach(Db, "SELECT name FROM users ORDER BY id",
      fun(Row) -> Self ! {Ref, maps:get("name", Row)} end),
    ?assertEqual({Ref, "Alice"}, receive {Ref, Name} -> {Ref, Name} after 1000 -> timeout end),
    ?assertEqual({Ref, "Bob"}, receive {Ref, Name} -> {Ref, Name} after 1000 -> timeout end),
    ?assertEqual({Ref, "Charlie"}, receive {Ref, Name} -> {Ref, Name} after 1000 -> timeout end)
  end).

map() ->
  with_db(fun(Db) ->
    create_fixture(Db),
    {ok, Names} = errm_sqlite:map(Db, "SELECT name FROM users ORDER BY id",
      fun(Row) -> maps:get("name", Row) end),
    ?assertEqual(["Alice", "Bob", "Charlie"], Names)
  end).


%% --- first / scalar ---

first_found() ->
  with_db(fun(Db) ->
    create_fixture(Db),
    {ok, Row} = errm_sqlite:first(Db, "SELECT * FROM users WHERE id = ?", [2]),
    ?assertEqual("Bob", maps:get("name", Row))
  end).

first_not_found() ->
  with_db(fun(Db) ->
    create_fixture(Db),
    {error, not_found} = errm_sqlite:first(Db, "SELECT * FROM users WHERE id = ?", [999])
  end).

scalar() ->
  with_db(fun(Db) ->
    create_fixture(Db),
    {ok, 35} = errm_sqlite:scalar(Db, "SELECT MAX(age) FROM users")
  end).

scalar_null() ->
  with_db(fun(Db) ->
    {ok, _} = errm_sqlite_nif:exec(Db, "CREATE TABLE t (x INTEGER)"),
    {ok, null} = errm_sqlite:scalar(Db, "SELECT MAX(x) FROM t")
  end).

scalar_wrong_column_count() ->
  with_db(fun(Db) ->
    create_fixture(Db),
    {error, not_a_single_column} = errm_sqlite:scalar(Db, "SELECT id, name FROM users LIMIT 1")
  end).


%% --- migrations ---

migrate_apply_and_idempotent() ->
  with_db(fun(Db) ->
    with_migration_dir(fun(Dir) ->
      write_migration(Dir, "001_create_users.sql", "CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT);"),
      write_migration(Dir, "002_add_age.sql", "ALTER TABLE users ADD COLUMN age INTEGER;"),
      ok = errm_sqlite_migrate:migrate(Db, Dir),
      ok = errm_sqlite_migrate:migrate(Db, Dir),
      {ok, _} = errm_sqlite:exec(Db, "INSERT INTO users (name, age) VALUES ('Alice', 30)")
    end)
  end).

migrate_multiple_statements_per_file() ->
  with_db(fun(Db) ->
    with_migration_dir(fun(Dir) ->
      write_migration(Dir, "001_multi.sql",
        "CREATE TABLE a (x INTEGER); CREATE TABLE b (y INTEGER); INSERT INTO a VALUES (1);"),
      ok = errm_sqlite_migrate:migrate(Db, Dir),
      {ok, _} = errm_sqlite:query(Db, "SELECT * FROM a"),
      {ok, _} = errm_sqlite:query(Db, "SELECT * FROM b")
    end)
  end).

migrate_failure_rolls_back() ->
  with_db(fun(Db) ->
    with_migration_dir(fun(Dir) ->
      write_migration(Dir, "001_create.sql", "CREATE TABLE a (x INTEGER);"),
      write_migration(Dir, "002_bad.sql", "CREATE TABLE b (y INTEGER); CREATE TABLE b (y INTEGER);"),
      ?assertError({migration_failed, <<"002_bad.sql">>, _},
        errm_sqlite_migrate:migrate(Db, Dir)),
      {ok, [_]} = errm_sqlite:query(Db,
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'a'"),
      {ok, []} = errm_sqlite:query(Db,
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'b'"),
      {ok, [Row]} = errm_sqlite:query(Db, "SELECT name FROM _migrations"),
      ?assertEqual("001_create.sql", maps:get("name", Row))
    end)
  end).

migrate_empty_dir() ->
  with_db(fun(Db) ->
    with_migration_dir(fun(Dir) ->
      ok = errm_sqlite_migrate:migrate(Db, Dir)
    end)
  end).

migrate_custom_table() ->
  with_db(fun(Db) ->
    with_migration_dir(fun(Dir) ->
      write_migration(Dir, "001_create.sql", "CREATE TABLE foo (x INTEGER);"),
      ok = errm_sqlite_migrate:migrate(Db, Dir, #{table => "my_migrations"})
    end)
  end).


nif_test_() ->
  [ {"open/close", fun open_close/0},
    {"close twice", fun close_twice/0},
    {"open bad path", fun open_bad_path/0},
    {"exec create", fun exec_nif_create/0},
    {"exec insert changes", fun exec_nif_insert_changes/0},
    {"exec multi statement", fun exec_nif_multi_stmt/0},
    {"exec invalid", fun exec_nif_invalid/0},
    {"exec error", fun exec_nif_error/0},
    {"last_insert_rowid", fun last_insert_rowid/0},
    {"last_insert_rowid empty", fun last_insert_rowid_empty/0},
    {"prepare/bind/step", fun prepare_bind_step/0},
    {"bind null", fun bind_null/0},
    {"bind all types", fun bind_all_types/0},
    {"prepare error", fun prepare_error/0},
    {"finalize no leak", fun finalize_no_leak/0} ].

query_test_() ->
  [ {"query all", fun query_all/0},
    {"query with args", fun query_with_args/0},
    {"query empty", fun query_empty/0} ].

exec_test_() ->
  [ {"exec update", fun exec_update/0},
    {"exec with args", fun exec_with_args/0},
    {"exec multi statement", fun exec_multi_stmt/0} ].

transaction_test_() ->
  [ {"commit", fun transaction_commit/0},
    {"rollback", fun transaction_rollback/0} ].

iterate_test_() ->
  [ {"fold", fun fold/0},
    {"fold empty", fun fold_empty/0},
    {"foreach", fun foreach/0},
    {"map", fun map/0} ].

first_scalar_test_() ->
  [ {"first found", fun first_found/0},
    {"first not found", fun first_not_found/0},
    {"scalar", fun scalar/0},
    {"scalar null", fun scalar_null/0},
    {"scalar wrong column count", fun scalar_wrong_column_count/0} ].

migrate_test_() ->
  [ {"apply and idempotent", fun migrate_apply_and_idempotent/0},
    {"multiple statements per file", fun migrate_multiple_statements_per_file/0},
    {"failure rolls back", fun migrate_failure_rolls_back/0},
    {"empty dir", fun migrate_empty_dir/0},
    {"custom table", fun migrate_custom_table/0} ].
