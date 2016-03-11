defmodule ReactiveSession.Mixfile do
  use Mix.Project

  def project do
    [app: :reactive_session,
     version: "0.0.1",
     elixir: "~> 1.0.0",
     deps: deps]
  end

  # Configuration for the OTP application
  #
  # Type `mix help compile.app` for more information
  def application do
    [applications: [:logger, :httpoison],
     mod: {ReactiveSession, []}]
  end

  # Dependencies can be Hex packages:
  #
  #   {:mydep, "~> 0.3.0"}
  #
  # Or git/path repositories:
  #
  #   {:mydep, git: "https://github.com/elixir-lang/mydep.git", tag: "0.1.0"}
  #
  # To depend on another app inside the umbrella:
  #
  #   {:myapp, in_umbrella: true}
  #
  # Type `mix help deps` for more examples and options
  defp deps do
    [
      {:reactive_entity, git: "git@bitbucket.org:ScalableEngineering/reactive-entity.git"},
      {:mailgun, "~> 0.1.1"},
      {:httpoison, "~> 0.7.2"}
    ]
  end
end
