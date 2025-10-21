defmodule ExFITS.Utils do
  @moduledoc """
  Utility functions for working with FITS files that go beyond basic read/write operations.
  """

  alias ExFITS.FITS

  @doc """
  Create a test pattern image as a list of lists.

  ## Parameters

  - width: Width of the image
  - height: Height of the image
  - pattern: Type of pattern (:gradient, :checkerboard, :diagonal)

  ## Returns

  - A list of lists containing float values
  """
  def create_test_pattern(width, height, pattern \\ :gradient) do
    case pattern do
      :gradient ->
        for y <- 0..(height-1) do
          for x <- 0..(width-1) do
            (x + y) / (width + height)
          end
        end

      :checkerboard ->
        for y <- 0..(height-1) do
          for x <- 0..(width-1) do
            rem(x + y, 2) * 1.0
          end
        end

      :diagonal ->
        for y <- 0..(height-1) do
          for x <- 0..(width-1) do
            if x == y, do: 1.0, else: 0.0
          end
        end
    end
  end

  @doc """
  Save a test pattern to a FITS file.

  ## Parameters

  - path: Path to the output file
  - width: Width of the image
  - height: Height of the image
  - pattern: Type of pattern (:gradient, :checkerboard, :diagonal)

  ## Returns

  - :ok on success
  """
  def save_test_pattern(path, width, height, pattern \\ :gradient) do
    data = create_test_pattern(width, height, pattern)
    FITS.write_image_from_lists(path, data)
  end

  @doc """
  Verify that reading and writing a FITS file preserves the image data.

  ## Parameters

  - source_path: Path to an existing FITS file
  - dest_path: Path to write the copied file

  ## Returns

  - :ok if copy is successful
  - {:error, reason} on failure
  """
  def verify_read_write(source_path, dest_path) do
    # Read the source file
    case FITS.read_image(source_path) do
      {:ok, {width, height, data}} ->
        # We have dimensions and data directly from read_image
        IO.puts("Read image with dimensions #{width}×#{height}")

        # Show sample pixel data for debugging
        sample_size = min(5, width * height)
        sample_data = for i <- 0..(sample_size-1) do
          offset = i * 4
          <<value::float-32-native>> = binary_part(data, offset, 4)
          value
        end
        IO.puts("Sample pixel values: #{inspect(sample_data, pretty: true)}")

        # Write to the destination file
        result = FITS.write_image(dest_path, data, width, height)

        # Report status
        case result do
          :ok ->
            IO.puts("Successfully copied #{source_path} to #{dest_path}")
            IO.puts("Image dimensions: #{width}×#{height}")
            :ok
          {:error, reason} ->
            IO.puts("Failed to write image: #{inspect(reason)}")
            {:error, reason}
        end

      {:ok, data} ->
        # Fallback to reading header for dimensions
        read_header_result = FITS.read_header(source_path)
        case read_header_result do
          {:ok, header} ->
            try do
              {width, height} = FITS.get_dimensions(header)

              IO.puts("Read image with dimensions #{width}×#{height} (from header)")

              # Show sample pixel data for debugging
              sample_size = min(5, width * height)
              sample_data = for i <- 0..(sample_size-1) do
                offset = i * 4
                <<value::float-32-native>> = binary_part(data, offset, 4)
                value
              end
              IO.puts("Sample pixel values: #{inspect(sample_data, pretty: true)}")

              # Write to the destination file
              result = FITS.write_image(dest_path, data, width, height)

              # Report status
              case result do
                :ok ->
                  IO.puts("Successfully copied #{source_path} to #{dest_path}")
                  IO.puts("Image dimensions: #{width}×#{height}")
                  :ok
                {:error, reason} ->
                  IO.puts("Failed to write image: #{inspect(reason)}")
                  {:error, reason}
              end
            rescue
              e ->
                IO.puts("Error getting dimensions: #{inspect(e)}")
                {:error, :dimension_error}
            end

          {:error, reason} ->
            IO.puts("Failed to read header: #{inspect(reason)}")
            {:error, reason}
        end

      error ->
        IO.puts("Failed to read image: #{inspect(error)}")
        error
    end
  end

  @doc """
  Inspect and print information about a FITS file.

  ## Parameters

  - path: Path to the FITS file

  ## Returns

  - :ok
  """
  def inspect_fits(path) do
    case FITS.read_header(path) do
      {:ok, header} ->
        IO.puts("
FITS File: #{path}")
        IO.puts("=" |> String.duplicate(40))

        # Extract basic image info
        {width, height} = FITS.get_dimensions(header)
        IO.puts("Dimensions: #{width}×#{height} (#{width * height} pixels)")

        # Print selected header fields
        important_keys = [:SIMPLE, :BITPIX, :NAXIS, :NAXIS1, :NAXIS2, :EXTEND, :BZERO, :BSCALE]

        IO.puts("
Header Information:")
        IO.puts("-" |> String.duplicate(40))

        # First print important keys in order
        for key <- important_keys, Map.has_key?(header, key) do
          value = Map.get(header, key)
          IO.puts("#{key} = #{inspect(value)}")
        end

        # Then print remaining keys
        IO.puts("
Additional Keywords:")
        IO.puts("-" |> String.duplicate(40))

        for {key, value} <- header, key not in important_keys do
          IO.puts("#{key} = #{inspect(value)}")
        end

        :ok

      {:error, reason} ->
        IO.puts("Error reading FITS header: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Compare two FITS files to see if they have the same data and header values.

  ## Parameters

  - path1: Path to the first FITS file
  - path2: Path to the second FITS file
  - check_pixels: Whether to compare pixel values (default: true)

  ## Returns

  - {:ok, :identical} if the files match
  - {:ok, differences} a list of differences found
  - {:error, reason} if any step fails
  """
  def compare_fits(path1, path2, check_pixels \\ true) do
    with {:ok, header1} <- FITS.read_header(path1),
         {:ok, header2} <- FITS.read_header(path2) do

      # Check bitpix match
      bitpix1 = Map.get(header1, :BITPIX)
      bitpix2 = Map.get(header2, :BITPIX)
      bitpix_match = bitpix1 == bitpix2

      # Check dimensions match
      {width1, height1} = FITS.get_dimensions(header1)
      {width2, height2} = FITS.get_dimensions(header2)
      dims_match = width1 == width2 and height1 == height2

      # Check pixel data if requested
      pixel_match = if check_pixels and dims_match do
        {:ok, {^width1, ^height1, data1}} = FITS.read_image(path1)
        {:ok, {^width2, ^height2, data2}} = FITS.read_image(path2)
        data1 == data2
      else
        true
      end

      # Create difference list
      differences = []
      differences = if !bitpix_match, do: [{:bitpix, {bitpix1, bitpix2}} | differences], else: differences
      differences = if !dims_match, do: [{:dimensions, {{width1, height1}, {width2, height2}}} | differences], else: differences
      differences = if !pixel_match, do: [:pixels | differences], else: differences

      # Additional header differences
      header_keys1 = Map.keys(header1)
      header_keys2 = Map.keys(header2)
      missing_keys = header_keys1 -- header_keys2
      extra_keys = header_keys2 -- header_keys1

      differences = if length(missing_keys) > 0, do: [{:missing_keys, missing_keys} | differences], else: differences
      differences = if length(extra_keys) > 0, do: [{:extra_keys, extra_keys} | differences], else: differences

      if differences == [], do: {:ok, :identical}, else: {:ok, differences}
    end
  end
end
