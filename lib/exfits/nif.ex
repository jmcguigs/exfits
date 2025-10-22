defmodule ExFITS.NIF do
  @on_load :load_nif
  @moduledoc """
  NIF interface for ExFITS providing bindings to CFITSIO library functions.
  """

  def load_nif do
    nif_path = Application.app_dir(:exfits, "priv/exfits_nif")

    case :erlang.load_nif(nif_path, 0) do
      :ok ->
        :ok

      {:error, reason} ->
        IO.warn("Failed to load NIF: #{inspect(reason)}")

        {:error, reason}
    end
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

  def write_image(_filename, _data, _width, _height, _bitpix),
    do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Convenience function to write image data (float32 binary) to a new FITS file with automatic dimensions.
  Creates a 1-row image by default.
  """
  def write_image(filename, data) do
    # Calculate dimensions assuming a single row
    # 4 bytes per float32
    num_pixels = byte_size(data) / 4
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

  def write_fits_file(_filename, _data, _headers, _bitpix, _options),
    do: :erlang.nif_error(:nif_not_loaded)

  def write_fits_file(_filename, _data, _headers, _bitpix, _options, _multi_extension),
    do: :erlang.nif_error(:nif_not_loaded)

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
