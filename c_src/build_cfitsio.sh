#!/bin/sh
set -e

# Prefer system CFITSIO if available
if pkg-config --exists cfitsio; then
  CFITSIO_LIBDIR="$(pkg-config --variable=libdir cfitsio)"
  CFITSIO_INCDIR1="$(pkg-config --variable=includedir cfitsio)"
  CFITSIO_INCDIR2=""
else
  # Check for Homebrew or manual install
  if [ -f "/usr/local/include/fitsio.h" ]; then
    CFITSIO_LIBDIR="/usr/local/lib"
    CFITSIO_INCDIR1="/usr/local/include"
    CFITSIO_INCDIR2=""
  elif [ -f "/opt/homebrew/include/fitsio.h" ]; then
    CFITSIO_LIBDIR="/opt/homebrew/lib"
    CFITSIO_INCDIR1="/opt/homebrew/include"
    CFITSIO_INCDIR2=""
  else
    # Build from source if not found
    if [ ! -d cfitsio ]; then
      git clone https://github.com/HEASARC/cfitsio.git cfitsio
    fi
    cd cfitsio
    ./configure --prefix=$(pwd)/local
    make
    make install
    cd ..
    CFITSIO_LIBDIR="./cfitsio/local/lib"
    CFITSIO_INCDIR1="./cfitsio/local/include"
    CFITSIO_INCDIR2="./cfitsio"
  fi
fi

# NIF include path detection
if [ -n "$ERL_NIF_INCLUDE" ]; then
  NIF_INCLUDE="$ERL_NIF_INCLUDE"
else
  if [ -d "$HOME/.asdf/installs/erlang/$(ls $HOME/.asdf/installs/erlang | sort -V | tail -n1)/lib/erlang/erts-$(ls $HOME/.asdf/installs/erlang | sort -V | tail -n1 | sed 's/.*-//')/include" ]; then
    NIF_INCLUDE="$HOME/.asdf/installs/erlang/$(ls $HOME/.asdf/installs/erlang | sort -V | tail -n1)/lib/erlang/erts-$(ls $HOME/.asdf/installs/erlang | sort -V | tail -n1 | sed 's/.*-//')/include"
  elif [ -d "/usr/local/lib/erlang/erts-$(erl -noshell -eval 'io:format(\"~s\", [erlang:system_info(version)]), halt().')/include" ]; then
    NIF_INCLUDE="/usr/local/lib/erlang/erts-$(erl -noshell -eval 'io:format(\"~s\", [erlang:system_info(version)]), halt().')/include"
  elif [ -d "/usr/lib/erlang/erts-$(erl -noshell -eval 'io:format(\"~s\", [erlang:system_info(version)]), halt().')/include" ]; then
    NIF_INCLUDE="/usr/lib/erlang/erts-$(erl -noshell -eval 'io:format(\"~s\", [erlang:system_info(version)]), halt().')/include"
  else
    echo "Error: Could not find Erlang NIF include directory. Set ERL_NIF_INCLUDE to override."
    exit 1
  fi
fi

echo "Building with include paths: $NIF_INCLUDE, $CFITSIO_INCDIR1, $CFITSIO_INCDIR2"
if [ "$(uname)" = "Darwin" ]; then
  gcc -dynamiclib -undefined dynamic_lookup -fPIC -o priv/exfits_nif.so c_src/exfits_nif.c -I$NIF_INCLUDE ${CFITSIO_INCDIR1:+-I$CFITSIO_INCDIR1} ${CFITSIO_INCDIR2:+-I$CFITSIO_INCDIR2} -L$CFITSIO_LIBDIR -lcfitsio
else
  gcc -fPIC -shared -o priv/exfits_nif.so c_src/exfits_nif.c -I$NIF_INCLUDE ${CFITSIO_INCDIR1:+-I$CFITSIO_INCDIR1} ${CFITSIO_INCDIR2:+-I$CFITSIO_INCDIR2} -L$CFITSIO_LIBDIR -lcfitsio
fi
