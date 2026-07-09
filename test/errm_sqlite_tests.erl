-module (errm_sqlite_tests).
-include_lib("eunit/include/eunit.hrl").

db_path() -> ":memory:".

with_db(Fun) ->
  {ok, Db} = errm_sqlite_nif:open(db_path()),
  try Fun(Db) after
    errm_sqlite_nif:close(Db)
  end.


open_test() ->
  {ok, Db} = errm_sqlite_nif:open(db_path()),
  ?assert(is_reference(Db)),
  errm_sqlite_nif:close(Db).

close_on_fresh_db_test() ->
  {ok, Db} = errm_sqlite_nif:open(db_path()),
  ?assertEqual(ok, errm_sqlite_nif:close(Db)).

close_twice_test() ->
  {ok, Db} = errm_sqlite_nif:open(db_path()),
  ok = errm_sqlite_nif:close(Db),
  ?assertEqual(ok, errm_sqlite_nif:close(Db)).

open_bad_path_test() ->
  {error, _} = errm_sqlite_nif:open("/nonexistent/dir/test.db").

exec_create_table_test() ->
  with_db(fun(Db) ->
    {ok, 0} = errm_sqlite_nif:exec(Db,
      "CREATE TABLE test (id INTEGER PRIMARY KEY, name TEXT)")
  end).

exec_insert_test() ->
  with_db(fun(Db) ->
    {ok, _} = errm_sqlite_nif:exec(Db,
      "CREATE TABLE test (id INTEGER PRIMARY KEY, name TEXT)"),
    {ok, _} = errm_sqlite_nif:exec(Db,
      "INSERT INTO test (name) VALUES ('Alice')"),
    {ok, _} = errm_sqlite_nif:exec(Db,
      "INSERT INTO test (name) VALUES ('Bob')"),
    {ok, 1} = errm_sqlite_nif:changes(Db)
  end).

last_insert_rowid_test() ->
  with_db(fun(Db) ->
    {ok, _} = errm_sqlite_nif:exec(Db,
      "CREATE TABLE test (id INTEGER PRIMARY KEY, name TEXT)"),
    {ok, _} = errm_sqlite_nif:exec(Db,
      "INSERT INTO test (name) VALUES ('Alice')"),
    {ok, 1} = errm_sqlite_nif:last_insert_rowid(Db),
    {ok, _} = errm_sqlite_nif:exec(Db,
      "INSERT INTO test (name) VALUES ('Bob')"),
    {ok, 2} = errm_sqlite_nif:last_insert_rowid(Db)
  end).

prepare_bind_step_test() ->
  with_db(fun(Db) ->
    {ok, _} = errm_sqlite_nif:exec(Db,
      "CREATE TABLE test (id INTEGER PRIMARY KEY, name TEXT)"),
    {ok, _} = errm_sqlite_nif:exec(Db,
      "INSERT INTO test (id, name) VALUES (1, 'Alice'), (2, 'Bob')"),

    {ok, Stmt} = errm_sqlite_nif:prepare(Db,
      "SELECT * FROM test WHERE id = ?"),
    ?assert(is_reference(Stmt)),

    ok = errm_sqlite_nif:bind(Stmt, [1]),
    {ok, #{}} = errm_sqlite_nif:step(Stmt),
    ?assertEqual(done, errm_sqlite_nif:step(Stmt)),
    ok = errm_sqlite_nif:finalize(Stmt)
  end).

bind_null_test() ->
  with_db(fun(Db) ->
    {ok, _} = errm_sqlite_nif:exec(Db,
      "CREATE TABLE t (x)"),
    {ok, Stmt} = errm_sqlite_nif:prepare(Db,
      "INSERT INTO t VALUES (?)"),
    ok = errm_sqlite_nif:bind(Stmt, [null]),
    done = errm_sqlite_nif:step(Stmt),
    ok = errm_sqlite_nif:finalize(Stmt),

    {ok, 1} = errm_sqlite:exec(Db,
      "SELECT * FROM t")
  end).

bind_all_types_test() ->
  with_db(fun(Db) ->
    {ok, _} = errm_sqlite_nif:exec(Db,
      "CREATE TABLE t (i INTEGER, f FLOAT, t TEXT, b BLOB)"),
    {ok, Stmt} = errm_sqlite_nif:prepare(Db,
      "INSERT INTO t VALUES (?, ?, ?, ?)"),
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

exec_error_test() ->
  with_db(fun(Db) ->
    {error, _} = errm_sqlite_nif:exec(Db, "SELECT * FROM nonexistent_table")
  end).

prepare_bind_finalize_no_leak_test() ->
  with_db(fun(Db) ->
    {ok, Stmt} = errm_sqlite_nif:prepare(Db, "SELECT 1"),
    ok = errm_sqlite_nif:bind(Stmt, []),
    ok = errm_sqlite_nif:finalize(Stmt),

    {ok, _} = errm_sqlite_nif:exec(Db, "SELECT 1")
  end).

create_fixture(Db) ->
  {ok, _} = errm_sqlite_nif:exec(Db,
    "CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT, age INTEGER)"),
  {ok, _} = errm_sqlite_nif:exec(Db,
    "INSERT INTO users (id, name, age) VALUES (1, 'Alice', 30), (2, 'Bob', 25), (3, 'Charlie', 35)").

query_all_test() ->
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

query_with_args_test() ->
  with_db(fun(Db) ->
    create_fixture(Db),
    {ok, [Row]} = errm_sqlite:query(Db,
      "SELECT * FROM users WHERE id = ?", [2]),
    ?assertEqual(2, maps:get("id", Row)),
    ?assertEqual("Bob", maps:get("name", Row))
  end).

query_empty_test() ->
  with_db(fun(Db) ->
    {ok, _} = errm_sqlite_nif:exec(Db,
      "CREATE TABLE empty (x INTEGER)"),
    {ok, []} = errm_sqlite:query(Db, "SELECT * FROM empty")
  end).

exec_test() ->
  with_db(fun(Db) ->
    create_fixture(Db),
    {ok, 1} = errm_sqlite:exec(Db,
      "UPDATE users SET age = age + 1 where age < 30")
  end).

exec_with_args_test() ->
  with_db(fun(Db) ->
    create_fixture(Db),
    {ok, 1} = errm_sqlite:exec(Db,
      "DELETE FROM users WHERE name = ?", [~"Bob"])
  end).

transaction_commit_test() ->
  with_db(fun(Db) ->
    create_fixture(Db),
    {ok, Result} = errm_sqlite:transaction(Db, fun(Db1) ->
      {ok, _} = errm_sqlite:exec(Db1,
        "INSERT INTO users (name, age) VALUES ('Dave', 40)"),
      {ok, [Row]} = errm_sqlite:query(Db1, "SELECT COUNT(*) AS cnt FROM users"),
      maps:get("cnt", Row)
    end),
    ?assertEqual(4, Result),

    {ok, [DaveRow]} = errm_sqlite:query(Db,
      "SELECT name FROM users WHERE name = 'Dave'"),
    ?assertEqual("Dave", maps:get("name", DaveRow))
  end).

transaction_rollback_test() ->
  with_db(fun(Db) ->
    create_fixture(Db),
    {error, {throw, testing, _}} = errm_sqlite:transaction(Db, fun(Db1) ->
      {ok, _} = errm_sqlite:exec(Db1,
        "INSERT INTO users (name, age) VALUES ('Dave', 40)"),
      throw(testing)
    end),

    {ok, []} = errm_sqlite:query(Db,
      "SELECT name FROM users WHERE name = 'Dave'")
  end).

fold_test() ->
  with_db(fun(Db) ->
    create_fixture(Db),
    {ok, Names} = errm_sqlite:fold(Db,
      "SELECT name FROM users ORDER BY id",
      [], [],
      fun(Row, Acc) -> [maps:get("name", Row) | Acc]
    end),
    ?assertEqual(["Charlie", "Bob", "Alice"], Names)
  end).

foreach_test() ->
  with_db(fun(Db) ->
    create_fixture(Db),
    Ref = make_ref(),
    Self = self(),
    ok = errm_sqlite:foreach(Db,
      "SELECT name FROM users ORDER BY id",
      fun(Row) -> Self ! {Ref, maps:get("name", Row)} end),

    ?assertEqual({Ref, "Alice"}, receive {Ref, Name} -> {Ref, Name} after 1000 -> timeout end),
    ?assertEqual({Ref, "Bob"}, receive {Ref, Name} -> {Ref, Name} after 1000 -> timeout end),
    ?assertEqual({Ref, "Charlie"}, receive {Ref, Name} -> {Ref, Name} after 1000 -> timeout end)
  end).

map_test() ->
  with_db(fun(Db) ->
    create_fixture(Db),
    {ok, Names} = errm_sqlite:map(Db,
      "SELECT name FROM users ORDER BY id",
      fun(Row) -> maps:get("name", Row) end),
    ?assertEqual(["Alice", "Bob", "Charlie"], Names)
  end).

first_found_test() ->
  with_db(fun(Db) ->
    create_fixture(Db),
    {ok, Row} = errm_sqlite:first(Db,
      "SELECT * FROM users WHERE id = ?", [2]),
    ?assertEqual("Bob", maps:get("name", Row))
  end).

first_not_found_test() ->
  with_db(fun(Db) ->
    create_fixture(Db),
    {error, not_found} = errm_sqlite:first(Db,
      "SELECT * FROM users WHERE id = ?", [999])
  end).

scalar_test() ->
  with_db(fun(Db) ->
    create_fixture(Db),
    {ok, 35} = errm_sqlite:scalar(Db,
      "SELECT MAX(age) FROM users")
  end).

scalare_wrong_column_count_test() ->
  with_db(fun(Db) ->
    create_fixture(Db),
    {error, not_a_single_column} = errm_sqlite:scalar(Db,
      "SELECT id, name FROM users LIMIT 1")
  end).

close_test() ->
  {ok, Db} = errm_sqlite_nif:open(db_path()),
  ok = errm_sqlite_nif:close(Db).

migrate_test() ->
  with_db(fun(Db) ->
    file:make_dir("test_migrations"),
    file:write_file("test_migrations/001_create_users.sql", "CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT);"),
    file:write_file("test_migrations/002_add_age.sql", "ALTER TABLE users ADD COLUMN age INTEGER;"),

    ok = errm_sqlite_migrate:migrate(Db, "test_migrations"),
    ok = errm_sqlite_migrate:migrate(Db, "test_migrations"),

    {ok, _} = errm_sqlite:exec(Db, "INSERT INTO users (name, age) VALUES ('Alice', 30)"),

    ok = file:delete("test_migrations/001_create_users.sql"),
    ok = file:delete("test_migrations/002_add_age.sql"),
    ok = file:del_dir("test_migrations")
  end).

prepare_error_test() ->
  with_db(fun(Db) ->
    {error, _} = errm_sqlite_nif:prepare(Db, "SELECT * FROM")
  end).

exec_multi_stmt_test() ->
  with_db(fun(Db) ->
    {ok, _} = errm_sqlite_nif:exec(Db,
      "CREATE TABLE t (x); INSERT INTO t VALUES (1); INSERT INTO t VALUES (2)"),
    {ok, _} = errm_sqlite_nif:exec(Db, "SELECT * FROM t")
  end).

exec_invalid_sql_test() ->
  with_db(fun(Db) ->
    {ok, _} = errm_sqlite_nif:exec(Db, "CREATE TABLE t (x)"),
    {error, _} = errm_sqlite_nif:exec(Db, "INSERT INTO t VALUES (")
  end).

last_insert_rowid_empty_test() ->
  with_db(fun(Db) ->
    {ok, 0} = errm_sqlite_nif:last_insert_rowid(Db)
  end).

exec_invalid_sql_helper_test() ->
  with_db(fun(Db) ->
    {error, _} = errm_sqlite_nif:exec(Db, "SELECT * FROM")
  end).

fold_empty_test() ->
  with_db(fun(Db) ->
    {ok, _} = errm_sqlite_nif:exec(Db, "CREATE TABLE t (x INTEGER)"),
    {ok, Acc} = errm_sqlite:fold(Db, "SELECT * FROM t", [], [], fun(Row, Acc0) -> [Row | Acc0] end),
    ?assertEqual([], Acc)
  end).

scalar_null_test() ->
  with_db(fun(Db) ->
    {ok, _} = errm_sqlite_nif:exec(Db,"CREATE TABLE t (x INTEGER)"),
    {ok, null} = errm_sqlite:scalar(Db, "SELECT MAX(x) FROM t")
  end).

migrate_empty_dir_test() ->
  with_db(fun(Db) ->
    ok = file:make_dir("test_empty_migrations"),
    ok = errm_sqlite_migrate:migrate(Db, "test_empty_migrations"),
    ok = file:del_dir("test_empty_migrations")
  end).

migrate_custom_table_test() ->
  with_db(fun(Db) ->
    ok = file:make_dir("test_custom_migrations"),
    ok = file:write_file("test_custom_migrations/001_create.sql", "CREATE TABLE foo (x INTEGER);"),
    ok = errm_sqlite_migrate:migrate(Db, "test_custom_migrations", #{table => "my_migrations"}),
    ok = file:delete("test_custom_migrations/001_create.sql"),
    ok = file:del_dir("test_custom_migrations")
  end).
