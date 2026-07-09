#include <erl_nif.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include <sqlite3.h>

typedef ErlNifBinary erl_nif_binary_t;
typedef ErlNifEnv erl_nif_env_t;
typedef ERL_NIF_TERM erl_nif_term_t;
typedef ErlNifFunc erl_nif_func_t;
typedef ErlNifResourceType erl_nif_resource_type_t;
typedef ErlNifSInt64 erl_nif_i64_t;
typedef ErlNifUInt64 erl_nif_u64_t;
typedef ErlNifSInt erl_nif_i32_t;
typedef ErlNifUInt erl_nif_u32_t;

typedef char cstr;
typedef int64_t i64;
typedef uint64_t u64;
typedef int32_t i32;
typedef uint32_t u32;
#define null NULL

static erl_nif_resource_type_t *DB_RESOURCE;
static erl_nif_resource_type_t *STMT_RESOURCE;

typedef struct {
  sqlite3 *db;
} db_handle_t;

typedef struct {
  sqlite3_stmt *stmt;
} stmt_handle_t;

static erl_nif_term_t make_error(erl_nif_env_t *env, const cstr *message) {
  return enif_make_tuple2(env, enif_make_atom(env, "error"),
                          enif_make_string(env, message, ERL_NIF_LATIN1));
}

static erl_nif_term_t make_error_with_arg(erl_nif_env_t *env,
                                          erl_nif_term_t arg) {
  return enif_make_tuple2(env, enif_make_atom(env, "error"), arg);
}

static erl_nif_term_t make_ok(erl_nif_env_t *env) {
  return enif_make_atom(env, "ok");
}

static erl_nif_term_t make_ok_with_arg(erl_nif_env_t *env, erl_nif_term_t arg) {
  return enif_make_tuple2(env, enif_make_atom(env, "ok"), arg);
}

static void db_resource_dtor(erl_nif_env_t *env, void *arg) {
  (void)env;

  db_handle_t *db_handle = (db_handle_t *)arg;
  if (db_handle->db) {
    sqlite3_close(db_handle->db);
    db_handle->db = null;
  }
}

static void stmt_resource_dtor(erl_nif_env_t *env, void *arg) {
  (void)env;

  stmt_handle_t *stmt_handle = (stmt_handle_t *)arg;
  if (stmt_handle->stmt) {
    sqlite3_finalize(stmt_handle->stmt);
    stmt_handle->stmt = null;
  }
}

static int load(erl_nif_env_t *env, void **priv_data, ERL_NIF_TERM load_info) {
  DB_RESOURCE =
      enif_open_resource_type(env, null, "db_handle", &db_resource_dtor,
                              ERL_NIF_RT_CREATE | ERL_NIF_RT_TAKEOVER, null);
  STMT_RESOURCE =
      enif_open_resource_type(env, null, "stmt_handle", &stmt_resource_dtor,
                              ERL_NIF_RT_CREATE | ERL_NIF_RT_TAKEOVER, null);

  if (!DB_RESOURCE || !STMT_RESOURCE)
    return -1;

  sqlite3_config(SQLITE_CONFIG_MULTITHREAD);
  sqlite3_initialize();
  return 0;
}

static void unload(erl_nif_env_t *env, void *priv_data) {
  (void)env;
  (void)priv_data;
  sqlite3_shutdown();
}

static erl_nif_term_t nif_open(erl_nif_env_t *env, i32 argc,
                               const erl_nif_term_t argv[]) {
  if (argc != 1) {
    fprintf(stderr, "errm_sqlite_nif: open: arity error, expected 1 param\n");
    return enif_make_badarg(env);
  }

  cstr path[1024];
  const cstr *message;
  i32 rc;

  if (!enif_get_string(env, argv[0], path, sizeof(path), ERL_NIF_LATIN1)) {
    fprintf(stderr, "errm_sqlite_nif: open: unable to get path\n");
    return enif_make_badarg(env);
  }

  db_handle_t *db_handle =
      enif_alloc_resource(DB_RESOURCE, sizeof(db_handle_t));
  if ((rc = sqlite3_open(path, &db_handle->db)) != SQLITE_OK) {
    message = sqlite3_errmsg(db_handle->db);
    goto fail;
  }

  erl_nif_term_t res = enif_make_resource(env, db_handle);
  enif_release_resource(db_handle);
  return make_ok_with_arg(env, res);

fail:
  sqlite3_close(db_handle->db);
  enif_release_resource(db_handle);
  return make_error(env, message);
}

static erl_nif_term_t nif_close(erl_nif_env_t *env, i32 argc,
                                const erl_nif_term_t argv[]) {
  if (argc != 1) {
    fprintf(stderr, "errm_sqlite_nif: close: arity error, expected 1 param\n");
    return enif_make_badarg(env);
  }

  db_handle_t *db_handle;
  if (!enif_get_resource(env, argv[0], DB_RESOURCE, (void **)&db_handle)) {
    fprintf(stderr, "errm_sqlite_nif: close: unable to get db handle\n");
    return enif_make_badarg(env);
  }

  i32 rc = sqlite3_close(db_handle->db);
  if (rc == SQLITE_BUSY)
    return enif_make_atom(env, "busy");

  return make_ok(env);
}

static erl_nif_term_t nif_prepare(erl_nif_env_t *env, i32 argc,
                                  const erl_nif_term_t argv[]) {
  if (argc != 2) {
    fprintf(stderr,
            "errm_sqlite_nif: prepare: arity error, expected 2 params\n");
    return enif_make_badarg(env);
  }

  db_handle_t *db_handle;
  i32 rc;

  if (!enif_get_resource(env, argv[0], DB_RESOURCE, (void **)&db_handle)) {
    fprintf(stderr, "errm_sqlite_nif: prepare: unable to get db handle\n");
    return enif_make_badarg(env);
  }

  cstr sql[4096]; // if your statement is larger than this, you shouldn't use
                  // SQLite in the first place.
  if (!enif_get_string(env, argv[1], sql, sizeof(sql), ERL_NIF_LATIN1)) {
    fprintf(stderr, "errm_sqlite_nif: prepare: unable to get sql\n");
    return enif_make_badarg(env);
  }

  sqlite3_stmt *stmt;
  if ((rc = sqlite3_prepare_v2(db_handle->db, sql, -1, &stmt, null)) !=
      SQLITE_OK)
    return make_error(env, sqlite3_errmsg(db_handle->db));

  stmt_handle_t *stmt_handle =
      enif_alloc_resource(STMT_RESOURCE, sizeof(stmt_handle_t));
  stmt_handle->stmt = stmt;

  erl_nif_term_t res = enif_make_resource(env, stmt_handle);
  enif_release_resource(stmt_handle);

  return make_ok_with_arg(env, res);
}

static erl_nif_term_t nif_bind(erl_nif_env_t *env, i32 argc,
                               const erl_nif_term_t argv[]) {
  if (argc != 2) {
    fprintf(stderr, "errm_sqlite_nif: bind: arity error, expected 2 params\n");
    return enif_make_badarg(env);
  }

  stmt_handle_t *stmt_handle;
  i32 rc;

  if (!enif_get_resource(env, argv[0], STMT_RESOURCE, (void **)&stmt_handle)) {
    fprintf(stderr, "errm_sqlite_nif: bind: unable to get stmt handle\n");
    return enif_make_badarg(env);
  }

  if ((rc = sqlite3_reset(stmt_handle->stmt)) != SQLITE_OK)
    return make_error(env,
                      sqlite3_errmsg(sqlite3_db_handle(stmt_handle->stmt)));

  erl_nif_term_t list = argv[1];
  u32 list_len = 0;
  if (!enif_get_list_length(env, list, &list_len)) {
    fprintf(stderr, "errm_sqlite_nif: bind: unable to get list length\n");
    return enif_make_badarg(env);
  }

  i32 index = 1;
  erl_nif_term_t head, tail;

  while (enif_get_list_cell(env, list, &head, &tail)) {
    if (enif_is_atom(env, head)) {
      u32 atom_len = 0;
      cstr atom_buf[256];
      if (!enif_get_atom_length(env, head, &atom_len, ERL_NIF_LATIN1))
        return make_error(env, "errm_sqlite_nif: bind: unable to get atom len");

      if (!enif_get_atom(env, head, atom_buf, sizeof(atom_buf), ERL_NIF_LATIN1))
        return make_error(env, "errm_sqlite_nif: bind: unable to get atom");

      if ((atom_len == 4 && memcmp(atom_buf, "null", 4) == 0) ||
          (atom_len == 3 && memcmp(atom_buf, "nil", 3) == 0))
        rc = sqlite3_bind_null(stmt_handle->stmt, index);
      else
        return make_error(env, "errm_sqlite_nif: bind: invalid atom type, "
                               "supported types are null and nil");
    } else if (enif_is_number(env, head)) {
      erl_nif_i64_t i64_val;
      erl_nif_i32_t i32_val;
      int i_val;
      double d_val;

      if (enif_get_int64(env, head, &i64_val))
        rc = sqlite3_bind_int64(stmt_handle->stmt, index, i64_val);
      else if (enif_get_long(env, head, &i32_val))
        rc = sqlite3_bind_int(stmt_handle->stmt, index, i32_val);
      else if (enif_get_int(env, head, &i_val))
        rc = sqlite3_bind_int(stmt_handle->stmt, index, i_val);
      else if (enif_get_double(env, head, &d_val))
        rc = sqlite3_bind_double(stmt_handle->stmt, index, d_val);
      else
        return make_error(env, "errm_sqlite_nif: bind: unable to get number");
    } else if (enif_is_binary(env, head)) {
      erl_nif_binary_t bin;
      if (!enif_inspect_binary(env, head, &bin))
        return make_error(env,
                          "errm_sqlite_nif: bind: unable to inspect binary");

      rc = sqlite3_bind_text(stmt_handle->stmt, index, (const cstr *)bin.data,
                             bin.size, SQLITE_TRANSIENT);
    } else
      return make_error(env, "errm_sqlite_nif: bind: unsupported type, did you "
                             "accidentally pass a list instead of binary?");

    if (rc != SQLITE_OK)
      return make_error(env,
                        sqlite3_errmsg(sqlite3_db_handle(stmt_handle->stmt)));

    list = tail;
    index++;
  }

  return make_ok(env);
}

static erl_nif_term_t nif_step(erl_nif_env_t *env, i32 argc,
                               const erl_nif_term_t argv[]) {
  if (argc != 1) {
    fprintf(stderr, "errm_sqlite_nif: step: arity error, expected 1 param\n");
    return enif_make_badarg(env);
  }

  stmt_handle_t *stmt_handle;
  i32 rc;

  if (!enif_get_resource(env, argv[0], STMT_RESOURCE, (void **)&stmt_handle)) {
    fprintf(stderr, "errm_sqlite_nif: step: unable to get stmt handle\n");
    return enif_make_badarg(env);
  }

  rc = sqlite3_step(stmt_handle->stmt);
  if (rc == SQLITE_ROW) {
    i32 cols = sqlite3_column_count(stmt_handle->stmt);
    erl_nif_term_t *keys = enif_alloc(sizeof(ERL_NIF_TERM) * cols);
    erl_nif_term_t *values = enif_alloc(sizeof(ERL_NIF_TERM) * cols);

    for (i32 i = 0; i < cols; i++) {
      keys[i] = enif_make_string(env, sqlite3_column_name(stmt_handle->stmt, i),
                                 ERL_NIF_LATIN1);

      switch (sqlite3_column_type(stmt_handle->stmt, i)) {
      case SQLITE_INTEGER:
        values[i] =
            enif_make_int64(env, sqlite3_column_int64(stmt_handle->stmt, i));
        break;
      case SQLITE_FLOAT:
        values[i] =
            enif_make_double(env, sqlite3_column_double(stmt_handle->stmt, i));
        break;
      case SQLITE_TEXT: {
        const cstr *text =
            (const cstr *)sqlite3_column_text(stmt_handle->stmt, i);
        values[i] = enif_make_string(env, text, ERL_NIF_LATIN1);
      } break;
      case SQLITE_BLOB: {
        erl_nif_binary_t bin;
        enif_alloc_binary(sqlite3_column_bytes(stmt_handle->stmt, i), &bin);
        memcpy(bin.data, sqlite3_column_blob(stmt_handle->stmt, i), bin.size);
        values[i] = enif_make_binary(env, &bin);
      } break;
      default:
        values[i] = enif_make_atom(env, "null");
      }
    }

    erl_nif_term_t map;
    enif_make_map_from_arrays(env, keys, values, cols, &map);
    enif_free(keys);
    enif_free(values);

    return make_ok_with_arg(env, map);
  }

  if (rc == SQLITE_DONE)
    return enif_make_atom(env, "done");

  return make_error(env, sqlite3_errmsg(sqlite3_db_handle(stmt_handle->stmt)));
}

static erl_nif_term_t nif_finalize(erl_nif_env_t *env, i32 argc,
                                   const erl_nif_term_t argv[]) {
  if (argc != 1) {
    fprintf(stderr,
            "errm_sqlite_nif: finalize: arity error, expected 1 param\n");
    return enif_make_badarg(env);
  }

  stmt_handle_t *stmt_handle;
  if (!enif_get_resource(env, argv[0], STMT_RESOURCE, (void **)&stmt_handle)) {
    fprintf(stderr, "errm_sqlite_nif: finalize: unable to get stmt handle\n");
    return enif_make_badarg(env);
  }

  sqlite3_finalize(stmt_handle->stmt);
  stmt_handle->stmt = NULL;
  return make_ok(env);
}

static erl_nif_term_t nif_exec(erl_nif_env_t *env, i32 argc,
                               const erl_nif_term_t argv[]) {
  if (argc != 2) {
    fprintf(stderr, "errm_sqlite_nif: exec: arity error, expected 2 params\n");
    return enif_make_badarg(env);
  }

  db_handle_t *db_handle;
  if (!enif_get_resource(env, argv[0], DB_RESOURCE, (void **)&db_handle)) {
    fprintf(stderr, "errm_sqlite_nif: exec: unable to get db handle\n");
    return enif_make_badarg(env);
  }

  cstr sql[4096]; // if your statement is larger than this, you shouldn't use
                  // SQLite in the first place.
  if (!enif_get_string(env, argv[1], sql, sizeof(sql), ERL_NIF_LATIN1)) {
    fprintf(stderr, "errm_sqlite_nif: exec: unable to get sql\n");
    return enif_make_badarg(env);
  }

  i32 rc;
  cstr *errmsg;

  if ((rc = sqlite3_exec(db_handle->db, sql, NULL, NULL, &errmsg)) !=
      SQLITE_OK) {
    erl_nif_term_t error = enif_make_string(env, errmsg, ERL_NIF_LATIN1);
    sqlite3_free(errmsg);
    return make_error_with_arg(env, error);
  }

  erl_nif_term_t changes = enif_make_int64(env, sqlite3_changes(db_handle->db));
  return make_ok_with_arg(env, changes);
}

static erl_nif_term_t nif_changes(erl_nif_env_t *env, i32 argc,
                                  const erl_nif_term_t argv[]) {
  if (argc != 1) {
    fprintf(stderr,
            "errm_sqlite_nif: changes: arity error, expected 1 param\n");
    return enif_make_badarg(env);
  }

  db_handle_t *db_handle;
  if (!enif_get_resource(env, argv[0], DB_RESOURCE, (void **)&db_handle)) {
    fprintf(stderr, "errm_sqlite_nif: changes: unable to get db handle\n");
    return enif_make_badarg(env);
  }

  erl_nif_term_t changes = enif_make_int64(env, sqlite3_changes(db_handle->db));
  return make_ok_with_arg(env, changes);
}

static erl_nif_term_t nif_last_insert_rowid(erl_nif_env_t *env, i32 argc,
                                            const erl_nif_term_t argv[]) {
  if (argc != 1) {
    fprintf(
        stderr,
        "errm_sqlite_nif: last_insert_rowid: arity error, expected 1 param\n");
    return enif_make_badarg(env);
  }

  db_handle_t *db_handle;
  if (!enif_get_resource(env, argv[0], DB_RESOURCE, (void **)&db_handle)) {
    fprintf(stderr,
            "errm_sqlite_nif: last_insert_rowid: unable to get db handle\n");
    return enif_make_badarg(env);
  }

  erl_nif_term_t rowid =
      enif_make_int64(env, sqlite3_last_insert_rowid(db_handle->db));
  return make_ok_with_arg(env, rowid);
}

static erl_nif_func_t nif_funcs[] = {
    {"open", 1, nif_open, ERL_NIF_DIRTY_JOB_IO_BOUND},
    {"close", 1, nif_close, ERL_NIF_DIRTY_JOB_IO_BOUND},
    {"prepare", 2, nif_prepare, ERL_NIF_DIRTY_JOB_IO_BOUND},
    {"bind", 2, nif_bind, ERL_NIF_DIRTY_JOB_IO_BOUND},
    {"step", 1, nif_step, ERL_NIF_DIRTY_JOB_IO_BOUND},
    {"finalize", 1, nif_finalize, ERL_NIF_DIRTY_JOB_IO_BOUND},
    {"exec", 2, nif_exec, ERL_NIF_DIRTY_JOB_IO_BOUND},
    {"changes", 1, nif_changes, ERL_NIF_DIRTY_JOB_IO_BOUND},
    {"last_insert_rowid", 1, nif_last_insert_rowid, ERL_NIF_DIRTY_JOB_IO_BOUND},
};

ERL_NIF_INIT(errm_sqlite_nif, nif_funcs, &load, null, null, &unload);
