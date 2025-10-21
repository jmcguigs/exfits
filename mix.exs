defmodule Exfits.MixProject do
  use Mix.Project

  def project do
    [
      app: :exfits,
      version: "0.2.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      description: description(),
      package: package(),
      docs: docs()
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
      {:nx, "~> 0.6.2", optional: true},
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
    ]
  end

    defp aliases do
      [
        "compile.nif": [
          "cmd mkdir -p priv",
          "cmd sh c_src/build_cfitsio.sh"
        ]
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
        links: %{"GitHub" => "https://github.com/yourusername/exfits"}
      ]
    end

    defp docs do
      [
        main: "Exfits",
        extras: ["README.md"]
      ]
    end
end
