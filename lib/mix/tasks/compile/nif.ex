defmodule Mix.Tasks.Compile.Nif do
  @moduledoc """
  Compiles the Exfits NIF library.
  """
  use Mix.Task.Compiler

  @impl Mix.Task.Compiler
  def run(_args) do
    if File.exists?("priv/exfits_nif.so") do
      # NIF already exists, nothing to do
      {:noop, []}
    else
      # Create priv directory
      File.mkdir_p!("priv")

      # Run the build script
      case System.cmd("sh", ["c_src/build_cfitsio.sh"], stderr_to_stdout: true) do
        {output, 0} ->
          Mix.shell().info(output)
          {:ok, []}

        {output, exit_code} ->
          Mix.shell().error("NIF compilation failed (exit code #{exit_code}):")
          Mix.shell().error(output)
          {:error, []}
      end
    end
  end
end
