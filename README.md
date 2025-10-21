# ExFITS

ExFITS provides Elixir bindings to the CFITSIO library for working with FITS (Flexible Image Transport System) files, commonly used in astronomy and scientific data processing.

## Features

- Read and write FITS files
- Support for various data types (float, integer, short, etc.)
- Read and write header cards
- Helper functions for common FITS operations
- Optional integration with Nx tensors for numerical computing

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `exfits` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:exfits, "~> 0.2.0"},
    {:nx, "~> 0.6.2"}  # Optional, for tensor functionality
  ]
end
```
## CFITSIO Dependency

This library uses the [CFITSIO](https://github.com/HEASARC/cfitsio) C library via Elixir NIFs. You must have CFITSIO installed on your system. CFITSIO may also be installed from source by running `mix compile.nif`

### Install CFITSIO (macOS)

```
brew install cfitsio
```

Or build from source:

```
git clone https://github.com/HEASARC/cfitsio.git
cd cfitsio
./configure
make
sudo make install
```

### Build NIF

The NIF will be built automatically when you run:

```
mix compile
```

If you encounter build errors, ensure `cfitsio` is installed and available to your compiler/linker.

## Usage Examples

### Writing a Simple FITS File

```elixir
# Create a simple 10x10 float image with values 1.0 to 100.0
data = for y <- 1..10, x <- 1..10, do: (y - 1) * 10 + x
bin_data = :binary.list_to_bin(for val <- data, do: <<val::float-32>>)

# Generate basic FITS headers
headers = [
  "SIMPLE  =                    T / Standard FITS format",
  "BITPIX  =                  -32 / IEEE single precision floating point",
  "NAXIS   =                    2 / Number of axes",
  "NAXIS1  =                   10 / Size of axis 1",
  "NAXIS2  =                   10 / Size of axis 2", 
  "ORIGIN  = 'Elixir ExFITS'     / File origin",
  "END"
]

# Write the FITS file
{:ok, filename} = Exfits.write_fits("output.fits", bin_data, headers)
```

### Working with Nx Tensors

If you have the Nx package installed, you can easily work with FITS data as tensors:

```elixir
# Read a FITS file directly into an Nx tensor
{:ok, tensor} = ExFITS.to_nx("image.fits")

# Perform tensor operations
processed_tensor = Nx.multiply(tensor, 2.0)

# Write the tensor back to a FITS file
ExFITS.write_nx(processed_tensor, "processed_image.fits")
```

## Documentation

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc):

