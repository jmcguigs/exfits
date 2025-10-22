defmodule Mix.Tasks.Clean.Nif do
  @moduledoc """
  Cleans the compiled NIF files.
  """
  use Mix.Task

  @shortdoc "Clean the compiled NIF files"

  @impl Mix.Task
  def run(_) do
    # Define the files to be cleaned
    nif_files = [
      "priv/exfits_nif.so"
    ]

    # Remove all NIF files that exist
    for file <- nif_files do
      if File.exists?(file) do
        Mix.shell().info("Removing #{file}")
        File.rm!(file)
      end
    end
  end
end
