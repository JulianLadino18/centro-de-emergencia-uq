defmodule Emergencia.Supervisor do
  @moduledoc """
  Supervisor OTP del sistema de emergencias.

  Usa la estrategia one_for_one: si un hijo falla, solo ese hijo se reinicia.
  Supervisa el GenServer principal (estado global y persistencia) y el
  GenServer de sesiones (usuarios, autenticación y cookies).
  -version 1.0
  -autor: equipo Programación III
  -fecha: 2026-11-15
  """

  use Supervisor

  @directorio_por_defecto Path.expand("data", __DIR__)

  @doc "Inicia el supervisor. Acepta :directorio y :name."
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    gen_opts = if name, do: [name: name], else: []
    Supervisor.start_link(__MODULE__, opts, gen_opts)
  end

  @impl true
  def init(opts) do
    directorio = Keyword.get(opts, :directorio, @directorio_por_defecto)

    hijos = [
      {Emergencia.Servidor, [directorio: directorio]},
      {Emergencia.Sesion, []}
    ]

    Supervisor.init(hijos, strategy: :one_for_one)
  end
end
