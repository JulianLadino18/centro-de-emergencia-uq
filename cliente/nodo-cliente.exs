defmodule Nodo.Cliente do
  @moduledoc """
  Nodo cliente del sistema de emergencias.

  Envía comandos al GenServer :servicio_emergencia del nodo servidor usando
  llamadas remotas (RPC). La cookie de distribución se lee del archivo
  cliente/cookie.txt (o servidor/cookie.txt) y la sesión del usuario se guarda
  en cliente/sesion.txt entre ejecuciones.

  Uso:
    elixir --sname cliente cliente/nodo-cliente.exs [comando] [args...]

  Ejemplos:
    elixir --sname cliente cliente/nodo-cliente.exs summary
    elixir --sname cliente cliente/nodo-cliente.exs connect laura 1234 coordinador centro
    elixir --sname cliente cliente/nodo-cliente.exs register_shelter A02 Sur Z2 30
  -version 1.0
  -autor: equipo Programación III
  -fecha: 2026-11-15
  """

  @raiz Path.expand("..", __DIR__)
  @archivo_sesion Path.join(__DIR__, "sesion.txt")
  @timeout 30_000

  def iniciar(argv \\ System.argv()) do
    Code.require_file("util.ex", __DIR__)

    {comando, args} =
      case argv do
        [] -> {"help", []}
        [comando | resto] -> {comando, resto}
      end

    configurar_cookie()
    ejecutar(comando, args)
  end

  # ---------- Cookie de distribución ----------

  defp configurar_cookie do
    if node() == :nonode@nohost do
      abortar(
        "El cliente debe arrancar con un nombre de nodo, por ejemplo:\n" <>
          "  elixir --sname cliente cliente/nodo-cliente.exs summary"
      )
    end

    case leer_cookie() do
      {:ok, cookie} ->
        Node.set_cookie(String.to_atom(cookie))

      {:error, _} ->
        abortar(
          "No se encontró la cookie de distribución.\n" <>
            "Arranque primero el servidor: elixir --sname servidor servidor/nodo-servidor.exs"
        )
    end
  end

  defp leer_cookie do
    rutas = [
      Path.join(__DIR__, "cookie.txt"),
      Path.join([@raiz, "servidor", "cookie.txt"])
    ]

    Enum.find_value(rutas, {:error, :sin_cookie}, fn ruta ->
      case File.read(ruta) do
        {:ok, contenido} ->
          case String.trim(contenido) do
            "" -> nil
            cookie -> {:ok, cookie}
          end

        {:error, _} ->
          nil
      end
    end)
  end

  # ---------- Conexión y ejecución ----------

  defp ejecutar(comando, args) do
    servidor = nodo_servidor()

    with :ok <- conectar(servidor) do
      cookie = cookie_sesion()

      case :rpc.call(servidor, Emergencia.NodoServidor, :comando, [comando, args, cookie], @timeout) do
        {:ok, texto} ->
          Emergencia.Cliente.Util.imprimir_resultado({:ok, texto})

        {:ok, texto, meta} ->
          actualizar_sesion(meta)
          Emergencia.Cliente.Util.imprimir_resultado({:ok, texto})

        {:error, texto} ->
          Emergencia.Cliente.Util.imprimir_resultado({:error, texto})

        {:badrpc, motivo} ->
          abortar("Error de comunicación con #{servidor}: #{inspect(motivo)}")
      end
    end
  end

  defp conectar(servidor) do
    if Node.connect(servidor) do
      :ok
    else
      {:error,
       "No se pudo conectar al nodo #{servidor}.\n" <>
         "Verifique que el servidor esté corriendo y que ambos usen la misma cookie."}
    end
  end

  defp nodo_servidor do
    case System.get_env("NODO_SERVIDOR") do
      nil -> :"servidor@#{host()}"
      nombre -> String.to_atom(nombre)
    end
  end

  defp host do
    node()
    |> Atom.to_string()
    |> String.split("@")
    |> List.last()
  end

  # ---------- Sesión del usuario ----------

  defp cookie_sesion do
    case File.read(@archivo_sesion) do
      {:ok, contenido} ->
        case String.trim(contenido) do
          "" -> nil
          cookie -> cookie
        end

      {:error, _} ->
        nil
    end
  end

  defp actualizar_sesion(%{cookie: cookie}) do
    File.write(@archivo_sesion, cookie <> "\n")
    :ok
  end

  defp actualizar_sesion(%{cerrar_sesion: true}) do
    File.rm(@archivo_sesion)
    :ok
  end

  defp actualizar_sesion(_meta), do: :ok

  defp abortar(mensaje) do
    IO.puts(:stderr, "[error] " <> mensaje)
    System.halt(1)
  end
end

Nodo.Cliente.iniciar()
