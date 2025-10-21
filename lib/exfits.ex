defmodule Exfits do
  @moduledoc """
  Exfits provides Elixir bindings to the CFITSIO library for working with FITS (Flexible Image Transport System) files.

  This module provides high-level functions for reading and writing FITS files, including support for:
  - Reading and writing FITS headers and image data
  - Support for multiple data types (float, integer, etc.)
  - Multi-extension FITS file handling
  - Header card manipulation
  """

  alias ExFITS.NIF

  # FITS BITPIX constants
  @bitpix_byte 8      # 8-bit unsigned integer
  @bitpix_short 16    # 16-bit signed integer
  @bitpix_int 32      # 32-bit signed integer
  @bitpix_float -32   # 32-bit float
  @bitpix_double -64  # 64-bit float

  @doc """
  Opens a FITS file and returns basic information about it.

  ## Parameters

  - filename: Path to the FITS file

  ## Returns

  - {:ok, info} where info contains metadata about the file
  - {:error, reason} on failure
  """
  def open(filename) do
    NIF.open_fits(filename)
  end

  @doc """
  Reads image data from a FITS file.

  ## Parameters

  - filename: Path to the FITS file

  ## Returns

  - {:ok, {width, height, data}} where data is a binary of pixel values
  - {:error, reason} on failure
  """
  def read_image(filename) do
    NIF.read_image(filename)
  end

  @doc """
  Reads header data from a FITS file.

  ## Parameters

  - filename: Path to the FITS file

  ## Returns

  - {:ok, headers} where headers is a map of header cards
  - {:error, reason} on failure
  """
  def read_header(filename) do
    NIF.read_header(filename)
  end

  @doc """
  Writes image data to a FITS file.

  ## Parameters

  - filename: Path to create the new FITS file
  - data: Binary containing pixel data
  - width: Width of the image in pixels
  - height: Height of the image in pixels
  - options: Map of options for the write operation
    - :bitpix - FITS BITPIX value (default: -32 for float)
    - :header - Map of header cards to include

  ## Returns

  - :ok on success
  - {:error, reason} on failure
  """
  def write_image(filename, data, width, height, options \\ %{}) do
    bitpix = Map.get(options, :bitpix, @bitpix_float)

    if Map.has_key?(options, :header) do
      NIF.write_fits_file(filename, data, width, height, bitpix, options.header)
    else
      NIF.write_image(filename, data, width, height, bitpix)
    end
  end

  @doc """
  Creates a FITS file with the provided image data and header cards.

  ## Parameters

  - filename: Path to create the new FITS file
  - data: Binary containing pixel data
  - headers: List of header card strings
  - options: Map of options for the write operation
    - :bitpix - FITS BITPIX value (default: -32 for float)

  ## Returns

  - {:ok, filename} on success
  - {:error, reason} on failure
  """
  def write_fits(filename, data, headers, options \\ %{}) do
    bitpix = Map.get(options, :bitpix, @bitpix_float)
    NIF.write_fits_file(filename, data, headers, bitpix, options)
  end

  @doc """
  Creates a multi-extension FITS file.

  ## Parameters

  - filename: Path to create the new FITS file
  - extensions: List of maps, each containing:
    - :data - Binary data for the extension
    - :headers - List of header card strings for the extension
  - options: Map of options for the write operation
    - :bitpix - FITS BITPIX value (default: -32 for float)

  ## Returns

  - {:ok, filename} on success
  - {:error, reason} on failure
  """
  def write_multi_extension_fits(filename, extensions, options \\ %{}) do
    bitpix = Map.get(options, :bitpix, @bitpix_float)

    # Extract data and headers lists
    data_list = Enum.map(extensions, & &1.data)
    headers_list = Enum.map(extensions, & &1.headers)

    NIF.write_multi_extension_fits(filename, data_list, headers_list, bitpix, options)
  end

  @doc """
  Returns a map of FITS BITPIX constants.

  ## Returns

  A map containing BITPIX constants for different data types:
  - :byte - 8-bit unsigned integer (8)
  - :short - 16-bit signed integer (16)
  - :int - 32-bit signed integer (32)
  - :float - 32-bit float (-32)
  - :double - 64-bit float (-64)
  """
  def bitpix do
    %{
      byte: @bitpix_byte,
      short: @bitpix_short,
      int: @bitpix_int,
      float: @bitpix_float,
      double: @bitpix_double
    }
  end
end

defmodule ExFITS.NIF do
  @on_load :load_nif

  def load_nif do
    IO.puts("Loading NIF...")
    :erlang.load_nif(Application.app_dir(:exfits, "priv/exfits_nif"), 0)
  end

  def hello, do: :erlang.nif_error(:nif_not_loaded)

  @doc "Open a FITS file (calls NIF)"
  def open_fits(_filename), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Read primary image data from a FITS file.
  Returns {:ok, {width, height, binary}} or {:error, status}
  """
  def read_image(_filename), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Read FITS header data as an Elixir map.

  ## Parameters

  - filename: Path to the FITS file

  ## Returns

  - {:ok, header_map} where header_map is a map of keyword-value pairs
  - {:error, status} on failure
  """
  def read_header(_filename), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Write image data (float32 binary) to a new FITS file with specified dimensions.

  ## Parameters

  - filename: Path to create the new FITS file
  - data: Binary containing float32 pixel data
  - width: Width of the image in pixels
  - height: Height of the image in pixels
  - bitpix: (Optional) FITS BITPIX value to use (default: -32 for float)

  ## Returns

  - :ok on success
  - {:error, status} or {:error, :dimensions_mismatch} on failure
  """
  def write_image(_filename, _data, _width, _height), do: :erlang.nif_error(:nif_not_loaded)
  def write_image(_filename, _data, _width, _height, _bitpix), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Convenience function to write image data (float32 binary) to a new FITS file with automatic dimensions.
  Creates a 1-row image by default.
  """
  def write_image(filename, data) do
    # Calculate dimensions assuming a single row
    num_pixels = byte_size(data) / 4  # 4 bytes per float32
    write_image(filename, data, trunc(num_pixels), 1)
  end

  @doc """
  Update header cards in an existing FITS file.

  ## Parameters

  - filename: Path to the FITS file to update
  - header: Map of header cards to write

  ## Returns

  - :ok on success
  - {:error, status} on failure
  """
  def write_header_cards(_filename, _header), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Write both image data and header cards to a new FITS file in a single operation.

  ## Parameters

  - filename: Path to create the new FITS file
  - data: Binary containing float32 pixel data
  - headers: List of header cards as strings
  - bitpix: FITS BITPIX value to use (-32 for float, 16 for short, etc)
  - options: (Optional) Map of options for controlling the write operation
  - multi_extension: (Optional) Boolean flag, set to true for multi-extension files

  ## Returns

  - {:ok, filename} on success
  - {:error, reason} on failure
  """
  def write_fits_file(_filename, _data, _headers, _bitpix), do: :erlang.nif_error(:nif_not_loaded)
  def write_fits_file(_filename, _data, _headers, _bitpix, _options), do: :erlang.nif_error(:nif_not_loaded)
  def write_fits_file(_filename, _data, _headers, _bitpix, _options, _multi_extension), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Write a multi-extension FITS file.

  ## Parameters

  - filename: Path to create the new FITS file
  - data_list: List of binary data for each extension
  - headers_list: List of header card lists for each extension
  - bitpix: FITS BITPIX value to use (-32 for float, 16 for short, etc)
  - options: (Optional) Map of options for controlling the write operation

  ## Returns

  - {:ok, filename} on success
  - {:error, reason} on failure
  """
  def write_multi_extension_fits(filename, data_list, headers_list, bitpix, options \\ %{}) do
    write_fits_file(filename, data_list, headers_list, bitpix, options, 1)
  end
end
