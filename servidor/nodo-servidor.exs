defmodule Nodo.Servidor do
  @moduledoc """
  Nodo servidor del sistema de emergencias.

  Carga los módulos del proyecto, configura la cookie de distribución, arranca
  el árbol de supervisión OTP (GenServer de estado global + GenServer de
  sesiones) y deja el nodo escuchando comandos de los clientes por RPC.

  Uso:
    elixir --sname servidor servidor/nodo-servidor.exs

  La cookie se lee de servidor/cookie.txt; si no existe se genera y se copia a
  cliente/cookie.txt para que los clientes usen la misma.
  -version 1.0
  -autor: equipo Programación III
  -fecha: 2026-11-15
  """

  @raiz Path.expand("..", __DIR__)
  @directorio Path.join([@raiz, "lib", "emergencia", "data"])
  @cookie_servidor Path.join(__DIR__, "cookie.txt")
  @cookie_cliente Path.join([@raiz, "cliente", "cookie.txt"])

  @modulos [
    "servidor/util.ex",
    "servidor/cookie.exs",
    "lib/emergencia/modelos.ex",
    "lib/emergencia/persistencia.ex",
    "lib/emergencia/zonas.ex",
    "lib/emergencia/ciudadanos.ex",
    "lib/emergencia/necesidades.ex",
    "lib/emergencia/recursos.ex",
    "lib/emergencia/albergues.ex",
    "lib/emergencia/mascotas.ex",
    "lib/emergencia/sesion.ex",
    "lib/emergencia/server.ex",
    "lib/emergencia/supervisor.ex",
    "lib/emergencia/nodo_servidor.ex"
  ]

  def iniciar do
    verificar_nodo()
    cargar_modulos()
    configurar_cookie()

    Application.put_env(:emergencia, :persistencia, directorio: @directorio)

    {:ok, _supervisor} = Emergencia.Supervisor.start_link(directorio: @directorio)
    {:ok, _fachada} = Emergencia.NodoServidor.start_link()

    IO.puts("Nodo servidor iniciado: #{node()}")
    IO.puts("Datos: #{@directorio}")
    IO.puts("Esperando comandos de los clientes... (Ctrl+C para salir)")

    Process.sleep(:infinity)
  end

  defp verificar_nodo do
    if node() == :nonode@nohost do
      IO.puts(:stderr, """
      [error] El servidor debe arrancar con un nombre de nodo:
          elixir --sname servidor servidor/nodo-servidor.exs
      """)

      System.halt(1)
    end
  end

  defp cargar_modulos do
    Enum.each(@modulos, fn archivo -> Code.require_file(archivo, @raiz) end)
  end

  defp configurar_cookie do
    cookie =
      case Emergencia.Cookie.leer(@cookie_servidor) do
        {:ok, ""} -> generar_cookie()
        {:ok, valor} -> valor
        {:error, _} -> generar_cookie()
      end

    :ok = Emergencia.Cookie.guardar(@cookie_servidor, cookie)
    :ok = Emergencia.Cookie.guardar(@cookie_cliente, cookie)
    Node.set_cookie(String.to_atom(cookie))
    IO.puts("Cookie de distribución: #{cookie}")
  end

  defp generar_cookie do
    if function_exported?(Emergencia.Cookie, :generar, 0) do
      Emergencia.Cookie.generar()
    else
      :crypto.strong_rand_bytes(12) |> Base.encode16(case: :lower)
    end
  end
end

Nodo.Servidor.iniciar()
