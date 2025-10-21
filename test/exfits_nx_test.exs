defmodule ExFITSNxTest do
  use ExUnit.Case
  @moduletag :nx_integration

  # Skip these tests if Nx is not available
  setup do
    if Code.ensure_loaded?(Nx) do
      :ok
    else
      {:skip, "Nx not available"}
    end
  end

  test "convert between Nx tensor and FITS file" do
    # Create a simple test tensor
    tensor = Nx.tensor([
      [1.0, 2.0, 3.0],
      [4.0, 5.0, 6.0],
      [7.0, 8.0, 9.0]
    ])

    # Write tensor to a FITS file
    filename = "test_nx_tensor.fits"

    # Clean up any previous test file
    File.rm(filename)

    # Write the tensor to FITS format
    assert ExFITS.write_nx(tensor, filename) == :ok

    # Check that the file exists
    assert File.exists?(filename)

    # Now read it back as a tensor
    {:ok, read_tensor} = ExFITS.to_nx(filename)

    # Compare the tensors (should be approximately equal due to float conversions)
    # We'll check a few values
    assert_in_delta Nx.to_number(read_tensor[0][0]), 1.0, 0.001
    assert_in_delta Nx.to_number(read_tensor[1][1]), 5.0, 0.001
    assert_in_delta Nx.to_number(read_tensor[2][2]), 9.0, 0.001

    # Verify dimensions
    assert Nx.shape(read_tensor) == {3, 3}

    # Clean up
    File.rm(filename)
  end
end
