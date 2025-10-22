#!/bin/sh
set -e

# Skip if NIF already exists
if [ -f "priv/exfits_nif.so" ]; then
  echo "NIF library already exists, skipping compilation"
  exit 0
fi

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
    
    # Force disable curl to avoid compilation issues
    # The network capabilities aren't needed for most FITS operations
    echo "Building CFITSIO without curl support for stability"
    ./configure --prefix=$(pwd)/local --disable-curl
    
    # Apply a patch to ensure curl is properly disabled
    if grep -q "curl_off_t" drvrnet.c; then
      echo "Applying patch to drvrnet.c to fix curl-related definitions"
      # Create a backup
      cp drvrnet.c drvrnet.c.bak
      
      # Remove or comment out curl functionality in drvrnet.c
      # Use platform-specific sed syntax (macOS requires an extension with -i)
      if [ "$(uname)" = "Darwin" ]; then
        sed -i '' 's/curl_off_t/off_t/g' drvrnet.c
      else
        sed -i 's/curl_off_t/off_t/g' drvrnet.c
      fi
    fi
    
    make
    make install
    cd ..
    CFITSIO_LIBDIR="./cfitsio/local/lib"
    CFITSIO_INCDIR1="./cfitsio/local/include"
    CFITSIO_INCDIR2="./cfitsio"
  fi
fi

# NIF include path detection - focusing specifically on asdf installs
if [ -n "$ERL_NIF_INCLUDE" ]; then
  NIF_INCLUDE="$ERL_NIF_INCLUDE"
else
  # Check specifically for asdf Erlang installations
  if [ -d "$HOME/.asdf/installs/erlang" ]; then
    # Find the latest Erlang version (sorting by version number)
    LATEST_ERLANG=$(ls -1 "$HOME/.asdf/installs/erlang" | sort -V | tail -n1)
    
    # First try the usr/include directory
    if [ -f "$HOME/.asdf/installs/erlang/$LATEST_ERLANG/usr/include/erl_nif.h" ]; then
      NIF_INCLUDE="$HOME/.asdf/installs/erlang/$LATEST_ERLANG/usr/include"
    
    # Next try to find ERTS include directory
    else
      # Find all erts directories
      ERTS_DIRS=$(find "$HOME/.asdf/installs/erlang/$LATEST_ERLANG" -type d -name "erts-*" 2>/dev/null)
      for dir in $ERTS_DIRS; do
        if [ -f "$dir/include/erl_nif.h" ]; then
          NIF_INCLUDE="$dir/include"
          break
        fi
      done
    fi
  fi
  
  # If still not found, fallback to a direct search
  if [ -z "$NIF_INCLUDE" ]; then
    # Use find command with more precise targeting to avoid long searches
    SEARCH_PATHS="$HOME/.asdf /usr/local/lib/erlang /usr/lib/erlang /opt/erlang"
    for path in $SEARCH_PATHS; do
      if [ -d "$path" ]; then
        SEARCH_RESULT=$(find "$path" -name "erl_nif.h" 2>/dev/null | head -n1)
        if [ -n "$SEARCH_RESULT" ]; then
          NIF_INCLUDE=$(dirname "$SEARCH_RESULT")
          break
        fi
      fi
    done
  fi
  
  # Hard-code the path as a last resort for your specific setup
  if [ -z "$NIF_INCLUDE" ]; then
    if [ -f "$HOME/.asdf/installs/erlang/28.0-rc2/usr/include/erl_nif.h" ]; then
      NIF_INCLUDE="$HOME/.asdf/installs/erlang/28.0-rc2/usr/include"
    elif [ -f "$HOME/.asdf/installs/erlang/28.0-rc2/erts-16.0/include/erl_nif.h" ]; then
      NIF_INCLUDE="$HOME/.asdf/installs/erlang/28.0-rc2/erts-16.0/include"
    elif [ -f "$HOME/.asdf/installs/erlang/27.2/usr/include/erl_nif.h" ]; then
      NIF_INCLUDE="$HOME/.asdf/installs/erlang/27.2/usr/include"
    fi
  fi
  
  # If all else fails
  if [ -z "$NIF_INCLUDE" ]; then
    echo "Error: Could not find Erlang NIF include directory."
    exit 1
  fi
fi

echo "Found Erlang NIF include path: $NIF_INCLUDE"
echo "Found CFITSIO include paths: $CFITSIO_INCDIR1 $CFITSIO_INCDIR2"
echo "Found CFITSIO library path: $CFITSIO_LIBDIR"

# Ensure priv directory exists (should already be created by mix task)
mkdir -p priv

# Compile the NIF
echo "Compiling exfits_nif.so..."
if [ "$(uname)" = "Darwin" ]; then
  gcc -dynamiclib -undefined dynamic_lookup -fPIC -o priv/exfits_nif.so c_src/exfits_nif.c -I$NIF_INCLUDE ${CFITSIO_INCDIR1:+-I$CFITSIO_INCDIR1} ${CFITSIO_INCDIR2:+-I$CFITSIO_INCDIR2} -L$CFITSIO_LIBDIR -lcfitsio
else
  gcc -fPIC -shared -o priv/exfits_nif.so c_src/exfits_nif.c -I$NIF_INCLUDE ${CFITSIO_INCDIR1:+-I$CFITSIO_INCDIR1} ${CFITSIO_INCDIR2:+-I$CFITSIO_INCDIR2} -L$CFITSIO_LIBDIR -lcfitsio
fi
