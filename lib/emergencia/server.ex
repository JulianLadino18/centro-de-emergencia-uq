defmodule Emergencia.Servidor do
  @moduledoc """
  GenServer principal del sistema de emergencias.

  Mantiene el estado global y serializa todas las mutaciones. Esto resuelve
  la regla de concurrencia obligatoria: aunque varios procesos soliciten
  recursos o cupos al mismo tiempo, el GenServer atiende una solicitud a la
  vez y valida el estado antes de modificarlo.

  Después de cada mutación exitosa guarda el estado afectado en
  data/*.txt (personas, mensajes, necesidades, recursos, albergues, mascotas
  y zonas).
  -version 1.0
  -autor: equipo Programación III
  -fecha: 2026-11-15
  """

  use GenServer

  alias Emergencia.{Albergues, Ciudadanos, Mascotas, Necesidades, Persistencia, Recursos, Zonas}

  @directorio_por_defecto Path.expand("data", __DIR__)

  # ============ API pública ============

  @doc "Inicia el servidor. Acepta :directorio y :name."
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  # ---------- Personas y mensajería ----------

  def registrar_persona(documento, nombre, edad, zona, estado, servidor \\ __MODULE__),
    do: GenServer.call(servidor, {:registrar_persona, documento, nombre, edad, zona, estado})

  def cambiar_estado_persona(clave, estado, servidor \\ __MODULE__),
    do: GenServer.call(servidor, {:cambiar_estado_persona, clave, estado})

  def buscar_persona(clave, servidor \\ __MODULE__),
    do: GenServer.call(servidor, {:buscar_persona, clave})

  def buscar_personas(criterios, servidor \\ __MODULE__),
    do: GenServer.call(servidor, {:buscar_personas, criterios})

  def listar_personas(servidor \\ __MODULE__), do: GenServer.call(servidor, :listar_personas)

  def enviar_mensaje(remitente, documento, contenido, servidor \\ __MODULE__),
    do: GenServer.call(servidor, {:enviar_mensaje, remitente, documento, contenido})

  def listar_mensajes(documento, servidor \\ __MODULE__),
    do: GenServer.call(servidor, {:listar_mensajes, documento})

  def marcar_mensaje(id, estado, servidor \\ __MODULE__),
    do: GenServer.call(servidor, {:marcar_mensaje, id, estado})

  # ---------- Necesidades ----------

  def registrar_necesidad(tipo, cantidad, prioridad, zona, descripcion, responsable, servidor \\ __MODULE__) do
    GenServer.call(servidor, {:registrar_necesidad, tipo, cantidad, prioridad, zona, descripcion, responsable})
  end

  def cambiar_estado_necesidad(id, estado, servidor \\ __MODULE__),
    do: GenServer.call(servidor, {:cambiar_estado_necesidad, id, estado})

  def buscar_necesidad(id, servidor \\ __MODULE__),
    do: GenServer.call(servidor, {:buscar_necesidad, id})

  def listar_necesidades(criterios, servidor \\ __MODULE__),
    do: GenServer.call(servidor, {:listar_necesidades, criterios})

  def pendientes(servidor \\ __MODULE__), do: GenServer.call(servidor, :pendientes)

  def asignar_recurso(id, clave, cantidad, servidor \\ __MODULE__),
    do: GenServer.call(servidor, {:asignar_recurso, id, clave, cantidad})

  # ---------- Recursos ----------

  def registrar_recurso(codigo, nombre, categoria, cantidad, unidad, ubicacion, servidor \\ __MODULE__) do
    GenServer.call(servidor, {:registrar_recurso, codigo, nombre, categoria, cantidad, unidad, ubicacion})
  end

  def entrada_recurso(codigo, ubicacion, cantidad, servidor \\ __MODULE__),
    do: GenServer.call(servidor, {:entrada_recurso, codigo, ubicacion, cantidad})

  def salida_recurso(codigo, ubicacion, cantidad, servidor \\ __MODULE__),
    do: GenServer.call(servidor, {:salida_recurso, codigo, ubicacion, cantidad})

  def transferir_recurso(codigo, origen, destino, cantidad, servidor \\ __MODULE__),
    do: GenServer.call(servidor, {:transferir_recurso, codigo, origen, destino, cantidad})

  def listar_recursos(criterios, servidor \\ __MODULE__),
    do: GenServer.call(servidor, {:listar_recursos, criterios})

  def criticos(umbral, servidor \\ __MODULE__),
    do: GenServer.call(servidor, {:criticos, umbral})

  # ---------- Albergues ----------

  def registrar_albergue(codigo, nombre, zona, capacidad, servidor \\ __MODULE__),
    do: GenServer.call(servidor, {:registrar_albergue, codigo, nombre, zona, capacidad})

  def registrar_entrada_albergue(codigo, documento, servidor \\ __MODULE__),
    do: GenServer.call(servidor, {:entrada_albergue, codigo, documento})

  def registrar_salida_albergue(codigo, documento, servidor \\ __MODULE__),
    do: GenServer.call(servidor, {:salida_albergue, codigo, documento})

  def buscar_albergue(codigo, servidor \\ __MODULE__),
    do: GenServer.call(servidor, {:buscar_albergue, codigo})

  def listar_albergues(servidor \\ __MODULE__),
    do: GenServer.call(servidor, :listar_albergues)

  def reporte_albergues(servidor \\ __MODULE__),
    do: GenServer.call(servidor, :reporte_albergues)

  # ---------- Mascotas ----------

  def reportar_mascota(tipo, especie, nombre, caracteristicas, color, tamano, zona, contacto, servidor \\ __MODULE__) do
    GenServer.call(
      servidor,
      {:reportar_mascota, tipo, especie, nombre, caracteristicas, color, tamano, zona, contacto}
    )
  end

  def buscar_mascota(id, servidor \\ __MODULE__),
    do: GenServer.call(servidor, {:buscar_mascota, id})

  def listar_mascotas(criterios, servidor \\ __MODULE__),
    do: GenServer.call(servidor, {:listar_mascotas, criterios})

  def emparejar_mascotas(umbral, servidor \\ __MODULE__),
    do: GenServer.call(servidor, {:emparejar_mascotas, umbral})

  def confirmar_match(id_perdida, id_encontrada, servidor \\ __MODULE__),
    do: GenServer.call(servidor, {:confirmar_match, id_perdida, id_encontrada})

  # ---------- Zonas, sectores y puntos de atención ----------

  def registrar_zona(codigo, nombre, nivel, total_afectados \\ 0, servidor \\ __MODULE__),
    do: GenServer.call(servidor, {:registrar_zona, codigo, nombre, nivel, total_afectados})

  def registrar_sector(codigo_zona, codigo, nombre, servidor \\ __MODULE__),
    do: GenServer.call(servidor, {:registrar_sector, codigo_zona, codigo, nombre})

  def registrar_punto(codigo_zona, codigo_sector, codigo, nombre, descripcion \\ "", servidor \\ __MODULE__),
    do: GenServer.call(servidor, {:registrar_punto, codigo_zona, codigo_sector, codigo, nombre, descripcion})

  def actualizar_nivel_zona(codigo_zona, nivel, servidor \\ __MODULE__),
    do: GenServer.call(servidor, {:actualizar_nivel_zona, codigo_zona, nivel})

  def buscar_zona(codigo, servidor \\ __MODULE__),
    do: GenServer.call(servidor, {:buscar_zona, codigo})

  def listar_zonas(servidor \\ __MODULE__), do: GenServer.call(servidor, :listar_zonas)

  def resumen_zonas(servidor \\ __MODULE__), do: GenServer.call(servidor, :resumen_zonas)

  # ---------- Resumen ----------

  def resumen(servidor \\ __MODULE__), do: GenServer.call(servidor, :resumen)

  # ============ Callbacks ============

  @impl true
  def init(opts) do
    directorio = Keyword.get(opts, :directorio, @directorio_por_defecto)

    {:ok,
     %{
       directorio: directorio,
       personas: leer(directorio, "people.txt", &Ciudadanos.personas_desde_lineas/1),
       mensajes: leer(directorio, "messages.txt", &Ciudadanos.mensajes_desde_lineas/1),
       necesidades: leer(directorio, "needs.txt", &Necesidades.desde_lineas/1),
       recursos: leer(directorio, "resources.txt", &Recursos.desde_lineas/1),
       albergues: leer(directorio, "shelters.txt", &Albergues.desde_lineas/1),
       mascotas: leer(directorio, "pets.txt", &Mascotas.desde_lineas/1),
       zonas: leer_zonas(directorio)
     }}
  end

  # ---------- Personas y mensajería ----------

  @impl true
  def handle_call({:registrar_persona, documento, nombre, edad, zona, estado}, _from, state) do
    Ciudadanos.registrar_persona(state.personas, documento, nombre, edad, zona, estado)
    |> responder_mutacion(state, :personas)
  end

  def handle_call({:cambiar_estado_persona, clave, estado}, _from, state) do
    Ciudadanos.cambiar_estado(state.personas, clave, estado)
    |> responder_mutacion(state, :personas)
  end

  def handle_call({:buscar_persona, clave}, _from, state) do
    {:reply, Ciudadanos.encontrar(state.personas, clave), state}
  end

  def handle_call({:buscar_personas, criterios}, _from, state) do
    {:reply, Ciudadanos.buscar(state.personas, criterios), state}
  end

  def handle_call(:listar_personas, _from, state), do: {:reply, state.personas, state}

  def handle_call({:enviar_mensaje, remitente, documento, contenido}, _from, state) do
    Ciudadanos.enviar_mensaje(state.mensajes, state.personas, remitente, documento, contenido)
    |> responder_mutacion(state, :mensajes)
  end

  def handle_call({:listar_mensajes, documento}, _from, state) do
    {:reply, Ciudadanos.listar_mensajes(state.mensajes, documento), state}
  end

  def handle_call({:marcar_mensaje, id, estado}, _from, state) do
    Ciudadanos.marcar_mensaje(state.mensajes, id, estado)
    |> responder_mutacion(state, :mensajes)
  end

  # ---------- Necesidades ----------

  def handle_call({:registrar_necesidad, tipo, cantidad, prioridad, zona, descripcion, responsable}, _from, state) do
    Necesidades.registrar(state.necesidades, tipo, cantidad, prioridad, zona, descripcion, responsable)
    |> responder_mutacion(state, :necesidades)
  end

  def handle_call({:cambiar_estado_necesidad, id, estado}, _from, state) do
    Necesidades.cambiar_estado(state.necesidades, id, estado)
    |> responder_mutacion(state, :necesidades)
  end

  def handle_call({:buscar_necesidad, id}, _from, state) do
    {:reply, Necesidades.buscar_por_id(state.necesidades, id), state}
  end

  def handle_call({:listar_necesidades, criterios}, _from, state) do
    {:reply, Necesidades.filtrar(state.necesidades, criterios), state}
  end

  def handle_call(:pendientes, _from, state) do
    {:reply, Necesidades.pendientes(state.necesidades), state}
  end

  def handle_call({:asignar_recurso, id, clave, cantidad}, _from, state) do
    case Necesidades.asignar_recurso(state.necesidades, state.recursos, id, clave, cantidad) do
      {:ok, resultado} ->
        nuevo = %{state | necesidades: resultado.necesidades, recursos: resultado.recursos}

        with :ok <- persistir(nuevo, :necesidades),
             :ok <- persistir(nuevo, :recursos) do
          {:reply, {:ok, resultado}, nuevo}
        else
          {:error, _} = error -> {:reply, error, state}
        end

      {:error, _} = error ->
        {:reply, error, state}
    end
  end

  # ---------- Recursos ----------

  def handle_call({:registrar_recurso, codigo, nombre, categoria, cantidad, unidad, ubicacion}, _from, state) do
    Recursos.registrar(state.recursos, codigo, nombre, categoria, cantidad, unidad, ubicacion)
    |> responder_mutacion(state, :recursos)
  end

  def handle_call({:entrada_recurso, codigo, ubicacion, cantidad}, _from, state) do
    Recursos.entrada(state.recursos, codigo, ubicacion, cantidad)
    |> responder_mutacion(state, :recursos)
  end

  def handle_call({:salida_recurso, codigo, ubicacion, cantidad}, _from, state) do
    Recursos.salida(state.recursos, codigo, ubicacion, cantidad)
    |> responder_mutacion(state, :recursos)
  end

  def handle_call({:transferir_recurso, codigo, origen, destino, cantidad}, _from, state) do
    Recursos.transferir(state.recursos, codigo, origen, destino, cantidad)
    |> responder_mutacion(state, :recursos)
  end

  def handle_call({:listar_recursos, criterios}, _from, state) do
    {:reply, Recursos.consultar(state.recursos, criterios), state}
  end

  def handle_call({:criticos, umbral}, _from, state) do
    {:reply, Recursos.criticos(state.recursos, umbral), state}
  end

  # ---------- Albergues ----------

  def handle_call({:registrar_albergue, codigo, nombre, zona, capacidad}, _from, state) do
    Albergues.registrar(state.albergues, codigo, nombre, zona, capacidad)
    |> responder_mutacion(state, :albergues)
  end

  def handle_call({:entrada_albergue, codigo, documento}, _from, state) do
    Albergues.registrar_entrada(state.albergues, codigo, documento)
    |> responder_mutacion(state, :albergues)
  end

  def handle_call({:salida_albergue, codigo, documento}, _from, state) do
    Albergues.registrar_salida(state.albergues, codigo, documento)
    |> responder_mutacion(state, :albergues)
  end

  def handle_call({:buscar_albergue, codigo}, _from, state) do
    {:reply, Albergues.buscar(state.albergues, codigo), state}
  end

  def handle_call(:listar_albergues, _from, state), do: {:reply, state.albergues, state}

  def handle_call(:reporte_albergues, _from, state) do
    {:reply, Albergues.reporte(state.albergues), state}
  end

  # ---------- Mascotas ----------

  def handle_call({:reportar_mascota, tipo, especie, nombre, caracteristicas, color, tamano, zona, contacto}, _from, state) do
    Mascotas.reportar(state.mascotas, tipo, especie, nombre, caracteristicas, color, tamano, zona, contacto)
    |> responder_mutacion(state, :mascotas)
  end

  def handle_call({:buscar_mascota, id}, _from, state) do
    {:reply, Mascotas.buscar(state.mascotas, id), state}
  end

  def handle_call({:listar_mascotas, criterios}, _from, state) do
    {:reply, Mascotas.filtrar(state.mascotas, criterios), state}
  end

  def handle_call({:emparejar_mascotas, umbral}, _from, state) do
    {:reply, Mascotas.emparejar(state.mascotas, umbral), state}
  end

  def handle_call({:confirmar_match, id_perdida, id_encontrada}, _from, state) do
    Mascotas.confirmar_match(state.mascotas, id_perdida, id_encontrada)
    |> responder_mutacion(state, :mascotas)
  end

  # ---------- Zonas, sectores y puntos de atención ----------

  def handle_call({:registrar_zona, codigo, nombre, nivel, total_afectados}, _from, state) do
    codigo = limpiar(codigo)

    case Zonas.registrar_zona(state.zonas, codigo, nombre, nivel, total_afectados) do
      {:ok, zonas} -> responder_zonas(zonas, state, fn -> Zonas.buscar_zona(zonas, codigo) end)
      {:error, motivo} -> {:reply, {:error, motivo}, state}
    end
  end

  def handle_call({:registrar_sector, codigo_zona, codigo, nombre}, _from, state) do
    codigo_zona = limpiar(codigo_zona)

    with {:ok, zona} <- Zonas.buscar_zona(state.zonas, codigo_zona),
         {:ok, zona} <- Zonas.registrar_sector(zona, limpiar(codigo), nombre) do
      zonas = Map.put(state.zonas, zona.codigo, zona)
      responder_zonas(zonas, state, fn -> {:ok, zona} end)
    else
      {:error, motivo} -> {:reply, {:error, motivo}, state}
    end
  end

  def handle_call({:registrar_punto, codigo_zona, codigo_sector, codigo, nombre, descripcion}, _from, state) do
    codigo_zona = limpiar(codigo_zona)

    with {:ok, zona} <- Zonas.buscar_zona(state.zonas, codigo_zona),
         {:ok, zona} <-
           Zonas.registrar_punto(zona, limpiar(codigo_sector), limpiar(codigo), nombre, descripcion) do
      zonas = Map.put(state.zonas, zona.codigo, zona)
      responder_zonas(zonas, state, fn -> {:ok, zona} end)
    else
      {:error, motivo} -> {:reply, {:error, motivo}, state}
    end
  end

  def handle_call({:actualizar_nivel_zona, codigo_zona, nivel}, _from, state) do
    codigo_zona = limpiar(codigo_zona)

    case Zonas.actualizar_nivel(state.zonas, codigo_zona, nivel) do
      {:ok, zonas} -> responder_zonas(zonas, state, fn -> Zonas.buscar_zona(zonas, codigo_zona) end)
      {:error, motivo} -> {:reply, {:error, motivo}, state}
    end
  end

  def handle_call({:buscar_zona, codigo}, _from, state) do
    {:reply, Zonas.buscar_zona(state.zonas, limpiar(codigo)), state}
  end

  def handle_call(:listar_zonas, _from, state) do
    zonas = state.zonas |> Map.values() |> Enum.sort_by(& &1.codigo)
    {:reply, zonas, state}
  end

  def handle_call(:resumen_zonas, _from, state) do
    zonas = Map.values(state.zonas)

    resumen = %{
      total_zonas: length(zonas),
      total_sectores: Enum.reduce(zonas, 0, fn zona, acc -> acc + map_size(zona.sectores) end),
      total_puntos: Enum.reduce(zonas, 0, fn zona, acc -> acc + Zonas.contar_puntos(zona) end),
      total_afectados: Enum.reduce(zonas, 0, fn zona, acc -> acc + zona.total_afectados end),
      nivel_maximo: Zonas.nivel_maximo_regional(state.zonas)
    }

    {:reply, resumen, state}
  end

  # ---------- Resumen ----------

  def handle_call(:resumen, _from, state) do
    totales = Albergues.totales(state.albergues)

    resumen = %{
      personas: length(state.personas),
      mensajes: length(state.mensajes),
      necesidades: length(state.necesidades),
      necesidades_pendientes: length(Necesidades.pendientes(state.necesidades)),
      recursos: length(state.recursos),
      albergues: length(state.albergues),
      mascotas: length(state.mascotas),
      zonas: map_size(state.zonas),
      albergues_totales: totales,
      porcentaje_ocupacion: Albergues.porcentaje_ocupacion(state.albergues)
    }

    {:reply, resumen, state}
  end

  def handle_call(_mensaje, _from, state), do: {:reply, {:error, :operacion_desconocida}, state}

  @impl true
  def handle_cast(_mensaje, state), do: {:noreply, state}

  @impl true
  def handle_info(_mensaje, state), do: {:noreply, state}

  # ============ Helpers ============

  # Aplica una mutación {:ok, valor, lista} y persiste el campo afectado.
  defp responder_mutacion(resultado, state, campo) do
    case resultado do
      {:ok, valor, lista} ->
        nuevo = Map.put(state, campo, lista)

        case persistir(nuevo, campo) do
          :ok -> {:reply, {:ok, valor}, nuevo}
          {:error, _} = error -> {:reply, error, state}
        end

      {:error, _} = error ->
        {:reply, error, state}
    end
  end

  # ---------- Persistencia ----------

  defp leer(directorio, archivo, parser) do
    case File.read(Path.join(directorio, archivo)) do
      {:ok, contenido} ->
        contenido
        |> String.split(["\r\n", "\n"])
        |> parser.()

      {:error, _} ->
        []
    end
  end

  defp persistir(state, :personas) do
    escribir(state, "people.txt", Ciudadanos.personas_a_lineas(state.personas))
  end

  defp persistir(state, :mensajes) do
    escribir(state, "messages.txt", Ciudadanos.mensajes_a_lineas(state.mensajes))
  end

  defp persistir(state, :necesidades) do
    escribir(state, "needs.txt", Necesidades.a_lineas(state.necesidades))
  end

  defp persistir(state, :recursos) do
    escribir(state, "resources.txt", Recursos.a_lineas(state.recursos))
  end

  defp persistir(state, :albergues) do
    escribir(state, "shelters.txt", Albergues.a_lineas(state.albergues))
  end

  defp persistir(state, :mascotas) do
    escribir(state, "pets.txt", Mascotas.a_lineas(state.mascotas))
  end

  defp persistir(state, :zonas) do
    lineas =
      state.zonas
      |> Map.values()
      |> Enum.sort_by(& &1.codigo)
      |> Enum.map(&Persistencia.serializar_zona/1)

    escribir(state, "zonas.txt", lineas)
  end

  # ---------- Zonas ----------

  # Aplica un cambio en el mapa de zonas y lo guarda.
  defp responder_zonas(zonas, state, seleccion) do
    nuevo = %{state | zonas: zonas}

    case persistir(nuevo, :zonas) do
      :ok -> {:reply, seleccion.(), nuevo}
      {:error, _} = error -> {:reply, error, state}
    end
  end

  # Lee zonas.txt (una zona por línea) y descarta las líneas dañadas. Si aún
  # está vacío, usa la semilla zones.txt en formato de barras.
  defp leer_zonas(directorio) do
    zonas = leer_archivo_zonas(Path.join(directorio, "zonas.txt"))

    if map_size(zonas) == 0 do
      leer_archivo_zonas(Path.join(directorio, "zones.txt"))
    else
      zonas
    end
  end

  defp leer_archivo_zonas(ruta) do
    case File.read(ruta) do
      {:ok, contenido} ->
        contenido
        |> String.split(["\r\n", "\n"])
        |> Enum.reject(&(String.trim(&1) == ""))
        |> Enum.reduce(%{}, fn linea, acc ->
          case Persistencia.deserializar_zona(linea) do
            {:ok, zona} -> Map.put(acc, zona.codigo, zona)
            {:error, _} -> acc
          end
        end)

      {:error, _} ->
        %{}
    end
  end

  defp limpiar(valor), do: valor |> to_string() |> String.trim()

  defp escribir(state, archivo, lineas) do
    ruta = Path.join(state.directorio, archivo)
    contenido = Enum.map(lineas, fn linea -> [linea, "\n"] end)

    with :ok <- File.mkdir_p(Path.dirname(ruta)),
         :ok <- File.write(ruta, contenido) do
      :ok
    else
      {:error, razon} -> {:error, {:persistencia_fallida, ruta, razon}}
    end
  end
end
