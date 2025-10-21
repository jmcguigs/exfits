defmodule ExFITS.FITS do
  @moduledoc """
  High-level functions for working with FITS files through the ExFITS.NIF module.

  ## Example Usage

  Reading a FITS file:

  ```
  # Read header information
  {:ok, header} = ExFITS.FITS.read_header("example.fits")

  # Read image data with dimensions
  {:ok, {width, height, data}} = ExFITS.FITS.read_image("example.fits")

  # Read both header and image data
  {:ok, %{header: header, data: data, width: width, height: height}} = ExFITS.FITS.read("example.fits")
  ```

  Writing a FITS file:

  ```
  # Write a FITS file with just image data
  :ok = ExFITS.FITS.write_image("new_image.fits", data, width, height)

  # Write a complete FITS file with header information and image data
  :ok = ExFITS.FITS.write_fits("new_image.fits", data, width, height, header, bitpix: 8)

  # Copy a FITS file preserving all header information
  :ok = ExFITS.FITS.copy_with_header("example.fits", "example_copy.fits")
  ```
  """

  alias ExFITS.NIF

  @doc """
  Open a FITS file to verify it exists and is a valid FITS file.

  ## Parameters

  - path: Path to the FITS file

  ## Returns

  - :ok on success
  - {:error, status} on failure
  """
  def open(path) when is_binary(path) do
    NIF.open_fits(path)
  end

  @doc """
  Read image data from a FITS file.

  ## Parameters

  - path: Path to the FITS file

  ## Returns

  - {:ok, {width, height, data}} where data is a binary containing float32 values
  - {:ok, data} when using older NIF version (for backward compatibility)
  - {:error, status} on failure
  """
  def read_image(path) when is_binary(path) do
    case NIF.read_image(path) do
      {:ok, {width, height, data}} when is_integer(width) and is_integer(height) and is_binary(data) ->
        {:ok, {width, height, data}}
      {:ok, data} when is_binary(data) ->
        # Handle backward compatibility
        IO.puts("Warning: Using older NIF version without dimension information")
        {:ok, data}
      error -> error
    end
  end

  @doc """
  Read header data from a FITS file.

  ## Parameters

  - path: Path to the FITS file

  ## Returns

  - {:ok, header} where header is a map of keyword-value pairs
  - {:error, status} on failure
  """
  def read_header(path) when is_binary(path) do
    NIF.read_header(path)
  end

  @doc """
  Read both header and image data from a FITS file.

  ## Parameters

  - path: Path to the FITS file

  ## Returns

  - {:ok, %{header: header, data: data, width: width, height: height}} on success
  - {:ok, %{header: header, data: data}} with older NIF version
  - {:error, status} on failure
  """
  def read(path) when is_binary(path) do
    with {:ok, header} <- read_header(path),
         read_result <- read_image(path) do
      case read_result do
        {:ok, {width, height, data}} ->
          {:ok, %{header: header, data: data, width: width, height: height}}
        {:ok, data} ->
          # Backward compatibility - try to get dimensions from header
          try do
            {width, height} = get_dimensions(header)
            {:ok, %{header: header, data: data, width: width, height: height}}
          rescue
            _ -> {:ok, %{header: header, data: data}}
          end
        error -> error
      end
    end
  end

  @doc """
  Write image data to a new FITS file with specified dimensions.

  ## Parameters

  - path: Path to create the new FITS file
  - data: Binary containing float32 pixel data
  - width: Width of the image in pixels
  - height: Height of the image in pixels

  ## Returns

  - :ok on success
  - {:error, status} or {:error, :dimensions_mismatch} on failure
  """
  def write_image(path, data, width, height) when is_binary(path) and is_integer(width) and is_integer(height) do
    NIF.write_image(path, data, width, height)
  end

  @doc """
  Create a 2D image from a list of lists of floats.

  ## Parameters

  - data: A list of lists of floats, where each inner list represents a row

  ## Returns

  - {binary, width, height} tuple containing the binary data and dimensions
  """
  def create_image_from_lists(data) when is_list(data) and is_list(hd(data)) do
    height = length(data)
    width = length(hd(data))

    # Verify all rows have the same width
    if Enum.any?(data, fn row -> length(row) != width end) do
      raise ArgumentError, "All rows must have the same length"
    end

    # Flatten and convert to binary using native endianness (same as CFITSIO)
    binary = data
    |> List.flatten()
    |> Enum.map(fn x -> <<x::float-32-native>> end)
    |> IO.iodata_to_binary()

    {binary, width, height}
  end

  @doc """
  Write a 2D image from a list of lists of floats to a FITS file.

  ## Parameters

  - path: Path to create the new FITS file
  - data: A list of lists of floats, where each inner list represents a row

  ## Returns

  - :ok on success
  - {:error, status} on failure
  """
  def write_image_from_lists(path, data) when is_binary(path) and is_list(data) do
    {binary, width, height} = create_image_from_lists(data)
    write_image(path, binary, width, height)
  end

  @doc """
  Extract dimensions from the header of a FITS file.

  ## Parameters

  - header: FITS header map as returned by read_header/1

  ## Returns

  - {width, height} tuple
  """
  def get_dimensions(header) do
    width = Map.get(header, :"NAXIS1")
    height = Map.get(header, :"NAXIS2")
    {width, height}
  end

  @doc """
  Copy a FITS file with its image data and header information.

  ## Parameters

  - source_path: Path to the source FITS file
  - dest_path: Path to the destination FITS file
  - preserve_bitpix: Whether to preserve the original bit depth (default: true)

  ## Returns

  - :ok on success
  - {:error, reason} on failure
  """
  def copy(source_path, dest_path, preserve_bitpix \\ true) when is_binary(source_path) and is_binary(dest_path) do
    with {:ok, header} <- read_header(source_path),
         read_result <- read_image(source_path) do

      # Get the original BITPIX value if we're preserving it
      bitpix = if preserve_bitpix, do: Map.get(header, :BITPIX, -32), else: -32 # Default to float if not preserving

      case read_result do
        {:ok, {width, height, data}} ->
          # Write with the original BITPIX value
          case NIF.write_image(dest_path, data, width, height, bitpix) do
            :ok ->
              # If image write is successful, copy the header cards
              case copy_header_cards(source_path, dest_path, header) do
                :ok -> :ok
                error -> error
              end
            error -> error
          end

        {:ok, data} ->
          # No dimensions, get them from the header
          {width, height} = get_dimensions(header)
          case NIF.write_image(dest_path, data, width, height, bitpix) do
            :ok ->
              # If image write is successful, copy the header cards
              case copy_header_cards(source_path, dest_path, header) do
                :ok -> :ok
                error -> error
              end
            error -> error
          end

        error -> error
      end
    end
  end

  @doc """
  Copy header cards from one FITS file to another.

  ## Parameters

  - source_path: Path to the source FITS file (not used directly, header is passed separately)
  - dest_path: Path to the destination FITS file to update
  - header: Map containing header cards to copy

  ## Returns

  - :ok on success
  - {:error, reason} on failure
  """
  def copy_header_cards(_source_path, dest_path, header) when is_binary(dest_path) and is_map(header) do
    # Make sure the file exists before trying to update it
    if File.exists?(dest_path) do
      # Use the NIF function to write the header cards
      result = NIF.write_header_cards(dest_path, header)

      # Debug output
      IO.puts("Writing header cards to #{dest_path}: #{inspect(result)}")

      result
    else
      IO.puts("Cannot write header cards: file #{dest_path} does not exist")
      {:error, :file_not_found}
    end
  end

  @doc """
  Convert binary float data from a FITS file to a list of lists.

  ## Parameters

  - binary: Binary data from read_image/1
  - width: Width of the image
  - height: Height of the image

  ## Returns

  - List of lists representing the 2D image
  """
  def binary_to_lists(binary, width, height) do
    for row <- 0..(height-1) do
      for col <- 0..(width-1) do
        offset = (row * width + col) * 4
        <<value::float-32-native>> = binary_part(binary, offset, 4)
        value
      end
    end
  end

  @doc """
  Create a new FITS file with both image data and header information in a single operation.

  ## Parameters

  - path: Path to create the new FITS file
  - data: Binary containing float32 pixel data
  - width: Width of the image in pixels
  - height: Height of the image in pixels
  - header: Map of header cards to include
  - options: Keyword list of options:
    - bitpix: FITS BITPIX value (default: value from header or -32 for float)

  ## Returns

  - :ok on success
  - {:error, reason} on failure
  """
  def write_fits(path, data, width, height, header, options \\ []) do
    # Get bitpix from options, header, or default to -32 (float)
    bitpix = Keyword.get(options, :bitpix) ||
             Map.get(header, :BITPIX) ||
             -32

    # Write the file with image data and header in a single operation
    NIF.write_fits_file(path, data, width, height, bitpix, header)
  end

  @doc """
  Copy a FITS file with header preservation in a single operation.

  ## Parameters

  - source_path: Path to the source FITS file
  - dest_path: Path to the destination FITS file
  - options: Keyword list of options:
    - preserve_bitpix: Whether to preserve the original bit depth (default: true)

  ## Returns

  - :ok on success
  - {:error, reason} on failure
  """
  def copy_with_header(source_path, dest_path, options \\ []) do
    preserve_bitpix = Keyword.get(options, :preserve_bitpix, true)

    with {:ok, header} <- read_header(source_path),
         {:ok, {width, height, data}} <- read_image(source_path) do

      # Get the original BITPIX value if we're preserving it
      bitpix = if preserve_bitpix, do: Map.get(header, :BITPIX, -32), else: -32

      # Write the destination file with all header information
      write_fits(dest_path, data, width, height, header, bitpix: bitpix)
    else
      {:ok, data} ->
        # Backward compatibility - try to get dimensions from header
        with {:ok, header} <- read_header(source_path),
             {width, height} <- get_dimensions(header) do
          # Get the original BITPIX value if we're preserving it
          bitpix = if preserve_bitpix, do: Map.get(header, :BITPIX, -32), else: -32

          # Write the destination file with all header information
          write_fits(dest_path, data, width, height, header, bitpix: bitpix)
        end

      error -> error
    end
  end
end
