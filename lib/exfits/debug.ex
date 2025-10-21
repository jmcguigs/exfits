defmodule ExFITS.Debug do
  @moduledoc """
  Debug utilities for examining FITS files and diagnosing issues.
  """

  alias ExFITS.FITS

  @doc """
  Examine a binary containing float32 values and display statistics.
  Useful for debugging FITS image data.

  ## Parameters

  - binary: Binary data containing float32 values
  - width: Image width (optional)
  - height: Image height (optional)

  ## Returns

  - Map with statistics about the data
  """
  def examine_binary(binary, width \\ nil, height \\ nil) do
    byte_size = byte_size(binary)
    float_count = div(byte_size, 4)

    # Extract all float values
    values = for i <- 0..(float_count - 1) do
      offset = i * 4
      <<value::float-32-native>> = binary_part(binary, offset, 4)
      value
    end

    # Calculate statistics
    stats = %{
      byte_size: byte_size,
      float_count: float_count,
      min_value: Enum.min(values),
      max_value: Enum.max(values),
      avg_value: Enum.sum(values) / float_count,
      zeros: Enum.count(values, &(&1 == 0.0)),
      non_zeros: Enum.count(values, &(&1 != 0.0)),
      width: width,
      height: height
    }

    # Print information
    IO.puts("\nBinary Data Analysis")
    IO.puts("===================")
    IO.puts("Size: #{byte_size} bytes (#{float_count} float32 values)")

    if width != nil and height != nil do
      IO.puts("Dimensions: #{width}×#{height} (#{width * height} pixels)")
      if width * height != float_count do
        IO.puts("WARNING: Dimensions don't match data size!")
      end
    end

    IO.puts("\nValue Statistics:")
    IO.puts("- Min value: #{stats.min_value}")
    IO.puts("- Max value: #{stats.max_value}")
    IO.puts("- Average value: #{stats.avg_value}")
    IO.puts("- Zero values: #{stats.zeros} (#{stats.zeros / float_count * 100}%)")
    IO.puts("- Non-zero values: #{stats.non_zeros} (#{stats.non_zeros / float_count * 100}%)")

    # Show a sample of values
    sample_size = min(20, float_count)
    IO.puts("\nFirst #{sample_size} values:")

    values
    |> Enum.take(sample_size)
    |> Enum.with_index()
    |> Enum.each(fn {value, i} ->
      IO.puts("[#{i}]: #{value}")
    end)

    stats
  end

  @doc """
  Compare two FITS files to see if their pixel data matches.

  ## Parameters

  - path1: Path to the first FITS file
  - path2: Path to the second FITS file

  ## Returns

  - :ok if identical
  - {:error, reason} if different
  """
  def compare_fits(path1, path2) do
    with {:ok, {width1, height1, data1}} <- FITS.read_image(path1),
         {:ok, {width2, height2, data2}} <- FITS.read_image(path2) do

      # Check dimensions
      if width1 != width2 or height1 != height2 do
        {:error, "Dimensions don't match: #{width1}×#{height1} vs #{width2}×#{height2}"}
      else
        # Compare binary data
        if data1 == data2 do
          IO.puts("Files are identical")
          :ok
        else
          # Count differences
          pixel_count = width1 * height1
          diff_count = count_differences(data1, data2, pixel_count)

          percent = diff_count / pixel_count * 100
          IO.puts("Files differ in #{diff_count}/#{pixel_count} pixels (#{percent}%)")
          {:error, "#{diff_count} different pixels"}
        end
      end
    end
  end

  defp count_differences(data1, data2, pixel_count) do
    Enum.reduce(0..(pixel_count - 1), 0, fn i, count ->
      offset = i * 4
      <<v1::float-32-native>> = binary_part(data1, offset, 4)
      <<v2::float-32-native>> = binary_part(data2, offset, 4)

      if v1 == v2, do: count, else: count + 1
    end)
  end

  @doc """
  Create a simple test image and save it in both directions to diagnose read/write issues.

  ## Parameters

  - dir: Directory to save the files (default: current directory)
  """
  def create_diagnostic_files(dir \\ ".") do
    # Create test patterns
    gradient = ExFITS.Utils.create_test_pattern(64, 64, :gradient)
    checkerboard = ExFITS.Utils.create_test_pattern(64, 64, :checkerboard)

    # Save original files
    {bin_gradient, w1, h1} = FITS.create_image_from_lists(gradient)
    {bin_checkerboard, w2, h2} = FITS.create_image_from_lists(checkerboard)

    gradient_path = Path.join(dir, "gradient.fits")
    checkerboard_path = Path.join(dir, "checkerboard.fits")

    FITS.write_image(gradient_path, bin_gradient, w1, h1)
    FITS.write_image(checkerboard_path, bin_checkerboard, w2, h2)

    # Read and write back
    copy_path1 = Path.join(dir, "gradient_copy.fits")
    copy_path2 = Path.join(dir, "checkerboard_copy.fits")

    FITS.copy(gradient_path, copy_path1)
    FITS.copy(checkerboard_path, copy_path2)

    # Compare files
    IO.puts("\nComparing gradient files:")
    compare_fits(gradient_path, copy_path1)

    IO.puts("\nComparing checkerboard files:")
    compare_fits(checkerboard_path, copy_path2)

    # Return paths
    [gradient_path, checkerboard_path, copy_path1, copy_path2]
  end

  @doc """
  Copy a FITS file while preserving or changing the original format.

  ## Parameters

  - source_path: Path to the source FITS file
  - dest_path: Path to the destination FITS file
  - preserve_format: Whether to preserve the original bit depth (default: true)

  ## Returns

  - {:ok, comparison_result} showing differences or :identical
  - {:error, reason} if any step fails
  """
  def copy_with_format(source_path, dest_path, preserve_format \\ true) do
    # Get original header before copy for comparison
    {:ok, original_header} = FITS.read_header(source_path)

    case FITS.copy(source_path, dest_path, preserve_format) do
      :ok ->
        # Compare the files
        with {:ok, header2} <- FITS.read_header(dest_path) do
          # Check bitpix preservation
          bitpix1 = Map.get(original_header, :BITPIX)
          bitpix2 = Map.get(header2, :BITPIX)

          if preserve_format do
            if bitpix1 == bitpix2 do
              IO.puts("Successfully preserved BITPIX value: #{bitpix1}")
            else
              IO.puts("BITPIX changed from #{bitpix1} to #{bitpix2} despite preserve_format=true")
            end
          else
            if bitpix1 != bitpix2 do
              IO.puts("BITPIX changed from #{bitpix1} to #{bitpix2} as expected")
            else
              IO.puts("BITPIX remained #{bitpix1} despite preserve_format=false")
            end
          end

          # Compare the full files
          result = ExFITS.Utils.compare_fits(source_path, dest_path)
          {:ok, result}
        end

      error -> error
    end
  end

  @doc """
  Test copying a FITS file with both preserved and changed format.

  ## Parameters

  - source_path: Path to the source FITS file
  - output_dir: Directory to save output files (default: same as source)

  ## Returns

  - List of generated file paths
  """
  def test_format_preservation(source_path, output_dir \\ nil) do
    dir = output_dir || Path.dirname(source_path)
    base = Path.basename(source_path, ".fits")

    # Create two copies - one with format preservation, one without
    preserved_path = Path.join(dir, "#{base}_preserved.fits")
    converted_path = Path.join(dir, "#{base}_float.fits")

    IO.puts("\n=== Testing format preservation ===")
    IO.puts("Original file: #{source_path}")
    IO.puts("Preserved copy: #{preserved_path}")
    IO.puts("Float conversion: #{converted_path}\n")

    # Copy with format preservation (true)
    IO.puts("Copying with format preservation...")
    _copy_result1 = copy_with_format(source_path, preserved_path, true)

    # Copy without format preservation (false)
    IO.puts("\nCopying with float conversion...")
    _copy_result2 = copy_with_format(source_path, converted_path, false)

    # Display headers
    IO.puts("\n=== Original file header ===")
    ExFITS.Utils.inspect_fits(source_path)

    IO.puts("\n=== Preserved copy header ===")
    ExFITS.Utils.inspect_fits(preserved_path)

    IO.puts("\n=== Float conversion header ===")
    ExFITS.Utils.inspect_fits(converted_path)

    [preserved_path, converted_path]
  end

  @doc """
  Test the new unified write_fits function with debugging.

  ## Parameters

  - source_path: Path to the source FITS file
  - dest_path: Path to the destination FITS file

  ## Returns

  - :ok on success
  - {:error, reason} on failure
  """
  def test_unified_write(source_path, dest_path) do
    IO.puts("\n=== Testing unified write_fits function ===")
    IO.puts("Source: #{source_path}")
    IO.puts("Destination: #{dest_path}")

    # First read the source file
    with {:ok, header} <- FITS.read_header(source_path),
         {:ok, {width, height, data}} <- FITS.read_image(source_path) do

      # Debug the binary data before writing
      IO.puts("\n=== Source Image Data ===")
      examine_binary(data, width, height)

      # Get the original bitpix
      bitpix = Map.get(header, :BITPIX, -32)
      IO.puts("Original BITPIX: #{bitpix}")

      # Try writing with unified function
      result = FITS.write_fits(dest_path, data, width, height, header, bitpix: bitpix)
      IO.puts("Write result: #{inspect(result)}")

      # Now read back the new file
      case result do
        :ok ->
          with {:ok, new_header} <- FITS.read_header(dest_path),
               {:ok, {new_width, new_height, new_data}} <- FITS.read_image(dest_path) do

            # Check dimensions
            if new_width != width or new_height != height do
              IO.puts("ERROR: Dimensions don't match - original: #{width}x#{height}, new: #{new_width}x#{new_height}")
            else
              IO.puts("Dimensions match: #{width}x#{height}")
            end

            # Check header
            new_bitpix = Map.get(new_header, :BITPIX, -32)
            IO.puts("New BITPIX: #{new_bitpix}")

            # Debug the new data
            IO.puts("\n=== Destination Image Data ===")
            examine_binary(new_data, new_width, new_height)

            # Compare data
            if data == new_data do
              IO.puts("SUCCESS: Binary data is identical")
              :ok
            else
              # If different, analyze differences
              bytes = byte_size(data)
              diff_count = count_binary_differences(data, new_data)
              IO.puts("WARN: Binary data differs in #{diff_count} of #{bytes} bytes (#{diff_count/bytes*100}%)")

              # Report the first few differences
              IO.puts("\nFirst differences:")
              report_binary_differences(data, new_data, 5)

              {:error, :data_changed}
            end
          end

        error -> error
      end
    end
  end

  # Helper function to count byte differences between binaries
  defp count_binary_differences(bin1, bin2) do
    byte_size1 = byte_size(bin1)
    byte_size2 = byte_size(bin2)

    if byte_size1 != byte_size2 do
      IO.puts("WARNING: Binaries have different sizes: #{byte_size1} vs #{byte_size2}")
      max(byte_size1, byte_size2)  # Consider all extra bytes as differences
    else
      # Count byte by byte differences
      Enum.reduce(0..(byte_size1-1), 0, fn i, count ->
        <<_::binary-size(i), b1, _::binary>> = bin1
        <<_::binary-size(i), b2, _::binary>> = bin2
        if b1 == b2, do: count, else: count + 1
      end)
    end
  end

  # Helper to report specific differences in binaries
  defp report_binary_differences(bin1, bin2, count) do
    byte_size1 = byte_size(bin1)
    byte_size2 = byte_size(bin2)
    min_size = min(byte_size1, byte_size2)

    # Find the first 'count' differences
    diffs = Enum.reduce_while(0..(min_size-1), [], fn i, acc ->
      <<_::binary-size(i), b1, _::binary>> = bin1
      <<_::binary-size(i), b2, _::binary>> = bin2

      if b1 != b2 do
        if length(acc) < count do
          {:cont, [{i, b1, b2} | acc]}
        else
          {:halt, acc}
        end
      else
        {:cont, acc}
      end
    end)

    # Report each difference
    diffs
    |> Enum.reverse()
    |> Enum.each(fn {offset, b1, b2} ->
      IO.puts("Offset #{offset}: #{b1} vs #{b2} (0x#{Integer.to_string(b1, 16)} vs 0x#{Integer.to_string(b2, 16)})")

      # If the offset is divisible by 4, show as float32 values
      if rem(offset, 4) == 0 do
        try do
          <<_::binary-size(offset), f1::float-32-native, _::binary>> = bin1
          <<_::binary-size(offset), f2::float-32-native, _::binary>> = bin2
          IO.puts("  As float32: #{f1} vs #{f2}")
        rescue
          _ -> :ok  # Ignore errors if we can't interpret as float
        end
      end
    end)
  end
end
