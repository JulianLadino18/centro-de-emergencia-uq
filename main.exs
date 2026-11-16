defmodule Main do
  @moduledoc """
  Punto de entrada único del sistema de emergencias.

  Ejecución:
      elixir main.exs

  Este script:
    1. Carga todos los módulos del proyecto.
    2. Genera una cookie y la guarda en servidor/cookie.txt y cliente/cookie.txt.
    3. Inicia el árbol de supervisión OTP (Servidor + Sesión).
    4. Ejecuta una demostración de albergues y mascotas.
  -version 1.0
  -autor: equipo Programación III
  -fecha: 2026-11-15
  """

  @raiz Path.expand(__DIR__)

  def iniciar do
    cargar_modulos()
    preparar_cookie()

    directorio = Path.join([@raiz, "lib", "emergencia", "data"])
    {:ok, _supervisor} = Emergencia.Supervisor.start_link(directorio: directorio)

    demostracion()
  end

  # ---------- Carga de módulos ----------

  defp cargar_modulos do
    archivos = [
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
      "lib/emergencia/supervisor.ex"
    ]

    Enum.each(archivos, fn archivo -> Code.require_file(archivo, @raiz) end)
  end

  # ---------- Cookie ----------

  defp preparar_cookie do
    cookie = Emergencia.Cookie.generar()

    _ = Emergencia.Cookie.guardar(Path.join([@raiz, "servidor", "cookie.txt"]), cookie)
    _ = Emergencia.Cookie.guardar(Path.join([@raiz, "cliente", "cookie.txt"]), cookie)

    IO.puts("Cookie generada y guardada: #{cookie}")
  end

  # ---------- Demostración ----------

  defp demostracion do
    sufijo = Integer.to_string(System.unique_integer([:positive]))
    codigo = "D" <> sufijo
    documento_1 = "DOC" <> sufijo <> "A"
    documento_2 = "DOC" <> sufijo <> "B"
    documento_3 = "DOC" <> sufijo <> "C"

    IO.puts("\n=== ALBERGUES ===")
    {:ok, _} = Emergencia.Servidor.registrar_albergue(codigo, "Albergue Demo " <> sufijo, "Z1", 2)
    {:ok, _} = Emergencia.Servidor.registrar_entrada_albergue(codigo, documento_1)
    {:ok, _} = Emergencia.Servidor.registrar_entrada_albergue(codigo, documento_2)

    case Emergencia.Servidor.registrar_entrada_albergue(codigo, documento_3) do
      {:error, motivo} ->
        IO.puts("Tercer ingreso rechazado: " <> Emergencia.Albergues.mensaje_error(motivo))

      {:ok, _} ->
        IO.puts("ERROR: se superó la capacidad del albergue")
    end

    reporte = Emergencia.Servidor.reporte_albergues()

    IO.puts(
      "Albergues: #{reporte.total_albergues} | Capacidad: #{reporte.capacidad} | " <>
        "Ocupación: #{reporte.ocupacion} | #{reporte.porcentaje}%"
    )

    Enum.each(reporte.detalle, fn linea -> IO.puts("  " <> linea) end)

    IO.puts("\n=== MASCOTAS ===")

    {:ok, perdida} =
      Emergencia.Servidor.reportar_mascota(
        "perdida",
        "perro",
        "Luna",
        "collar rojo",
        "negra",
        "mediana",
        "Z1",
        "300123"
      )

    {:ok, encontrada} =
      Emergencia.Servidor.reportar_mascota(
        "encontrada",
        "perro",
        "Desconocida",
        "collar rojo",
        "negra",
        "mediana",
        "Z1",
        "300456"
      )

    coincidencias = Emergencia.Servidor.emparejar_mascotas(30)
    IO.puts("Coincidencias con puntaje >= 30: #{length(coincidencias)}")

    Enum.each(coincidencias, fn coincidencia ->
      IO.puts(
        "  #{coincidencia.perdida.id} <-> #{coincidencia.encontrada.id} | " <>
          "puntaje #{coincidencia.puntaje}"
      )
    end)

    par_esperado =
      Enum.find(coincidencias, fn coincidencia ->
        coincidencia.perdida.id == perdida.id and coincidencia.encontrada.id == encontrada.id
      end)

    if par_esperado do
      {:ok, _} = Emergencia.Servidor.confirmar_match(perdida.id, encontrada.id)
      IO.puts("Match confirmado: ambos reportes quedaron como resuelta")

      case Emergencia.Servidor.confirmar_match(perdida.id, encontrada.id) do
        {:error, motivo} ->
          IO.puts("Segundo intento rechazado: " <> Emergencia.Mascotas.mensaje_error(motivo))

        {:ok, _} ->
          IO.puts("ERROR: se resolvió dos veces el mismo reporte")
      end
    else
      IO.puts("No se encontró el par de mascotas esperado")
    end

    IO.puts("\n=== RESUMEN GLOBAL ===")
    IO.inspect(Emergencia.Servidor.resumen(), label: "Resumen")
  end
end

Main.iniciar()
