set shell := ["bash", "-c"]
set quiet

__compile:
    gcc -o priv/errm_sqlite_nif.so -shared -fPIC -I${ERL_ROOT}/usr/include -L${ERL_ROOT}/usr/lib -lsqlite3 c_src/errm_sqlite_nif.c

bear:
    bear -- just __compile
