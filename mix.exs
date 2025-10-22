defmodule Exfits.MixProject do
  use Mix.Project

  def project do
    [
      app: :exfits,
      version: "0.2.1",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      description: description(),
      package: package(),
      docs: docs(),
      compilers: [:nif] ++ Mix.compilers(),
      build_embedded: Mix.env() == :prod
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:nx, "~> 0.6", optional: true},
      {:ex_doc, "~> 0.30", only: :dev, runtime: false}
    ]
  end

  defp aliases do
    [
      # Keep the alias for backward compatibility
      "compile.nif": [
        "compile.nif.force"
      ],
      "compile.nif.force": [
        # Force recompilation
        "cmd rm -f priv/exfits_nif.so",
        "cmd mkdir -p priv",
        "cmd sh c_src/build_cfitsio.sh"
      ],
      # Ensure NIF is cleaned when running mix clean
      clean: ["clean", "clean.nif"]
    ]
  end

  defp description do
    """
    Exfits provides Elixir bindings to the CFITSIO library for working with FITS
    (Flexible Image Transport System) files, commonly used in astronomy.
    """
  end

  defp package do
    [
      files: ~w(lib c_src mix.exs README.md LICENSE),
      maintainers: ["ExFITS Contributors"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/jmcguigs/exfits"}
    ]
  end

  defp docs do
    [
      main: "readme",
      source_url: "https://github.com/jmcguigs/exfits",
      extras: ["README.md"],
      source_ref: "main",
      formatters: ["html"],
      groups_for_modules: [
        "Core": [
          ExFITS
        ],
        "NIF Interface": [
          ExFITS.NIF
        ]
      ]
    ]
  end
end
