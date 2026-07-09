-ifndef(ERRM_SQLITE_HRL).
-define(ERRM_SQLITE_HRL, true).

-type db_handle() :: reference().
-type stmt_handle() :: reference().

-type row() :: #{string() => term()}.
-type sql() :: string().
-type bind_args() :: [term()].

-endif.
