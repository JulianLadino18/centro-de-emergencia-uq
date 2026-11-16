defmodule Emergencia.NodoServidor do
  @moduledoc """
  Fachada remota del nodo servidor.

  El cliente no llama directamente a los GenServer: envía una tupla
  {comando, argumentos, cookie} por RPC a este módulo, que valida la sesión y
  ejecuta la operación sobre Emergencia.Servidor y Emergencia.Sesion.

  Todos los comandos pasan por este GenServer, así que se atienden de uno en
  uno: la concurrencia queda controlada aunque lleguen varios clientes a la vez.

  Formato de respuesta:
    {:ok, texto}                          -> comando exitoso
    {:ok, texto, %{cookie: cookie}}       -> connect (el cliente guarda la cookie)
    {:ok, texto, %{cerrar_sesion: true}}  -> disconnect (el cliente borra su sesión)
    {:error, texto}                       -> error explicado al usuario
  -version 1.0
  -autor: equipo Programación III
  -fecha: 2026-11-15
  """

  use GenServer

  require Logger

  alias Emergencia.{Albergues, Ciudadanos, Mascotas, Necesidades, Recursos, Sesion, Servidor, Util, Zonas}

  @timeout 30_000

  # Roles que pueden usar cada tipo de comando
  @todos [:ciudadano, :voluntario, :coordinador, :administrador]
  @gestion [:voluntario, :coordinador, :administrador]
  @coordinacion [:coordinador, :administrador]

  @comandos [
    "connect usuario contraseña [rol] [zona]",
    "disconnect",
    "register_zone codigo nombre nivel [personas]",
    "register_sector zona codigo nombre [nivel]",
    "register_point zona sector codigo [nombre] [descripcion]",
    "zone_status codigo",
    "zones_summary",
    "report_person documento nombre [edad] zona estado",
    "find_person documento | find_person nombre=texto",
    "list_people",
    "change_person_status id|documento estado",
    "send_family_message documento \"texto del mensaje\"",
    "list_family_messages documento",
    "register_need tipo cantidad prioridad zona descripcion [responsable]",
    "list_needs [zona=... tipo=... prioridad=... estado=...]",
    "assign_resource id_necesidad codigo|cantidad",
    "register_resource codigo nombre categoria cantidad unidad ubicacion",
    "list_resources [codigo=... nombre=... categoria=... ubicacion=...]",
    "resource_entry codigo ubicacion cantidad",
    "resource_exit codigo ubicacion cantidad",
    "transfer_resource codigo origen destino cantidad",
    "report_pet tipo especie nombre [caracteristicas] color tamano zona contacto",
    "list_pets [tipo=... especie=... zona=... estado=...]",
    "match_pets",
    "confirm_match id_perdida id_encontrada",
    "register_shelter codigo nombre zona capacidad",
    "check_shelter codigo",
    "register_entry codigo documento",
    "register_exit codigo documento",
    "shelter_report",
    "pending_needs",
    "critical_resources [umbral]",
    "summary",
    "help"
  ]

  # ============ API pública ============

  @doc "Inicia la fachada. Acepta :name."
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  @doc "Ejecuta un comando enviado por un cliente."
  def comando(comando, args, cookie \\ nil, servidor \\ __MODULE__) do
    GenServer.call(servidor, {:comando, comando, args, cookie}, @timeout)
  end

  @doc "Lista de comandos disponibles (texto de ayuda)."
  def comandos, do: @comandos

  # ============ Callbacks ============

  @impl true
  def init(_opts), do: {:ok, %{}}

  @impl true
  def handle_call({:comando, comando, args, cookie}, {pid, _tag}, state) do
    nombre = normalizar_comando(comando)

    # Evidencia en la terminal del servidor de cada solicitud recibida.
    registrar_solicitud(nombre, args, pid)

    respuesta = ejecutar(nombre, args, cookie)
    registrar_respuesta(nombre, respuesta)

    {:reply, respuesta, state}
  end

  # ============ Registro (logs) ============

  defp registrar_solicitud(comando, args, pid) do
    Logger.info(
      "[NodoServidor] #{node()} <- #{comando} " <>
        "args=#{formatear_args(comando, args)} cliente=#{inspect(pid)}"
    )
  end

  defp registrar_respuesta(comando, {:ok, texto}) do
    Logger.info("[NodoServidor] -> #{comando}: OK (#{resumen(texto)})")
  end

  defp registrar_respuesta(comando, {:ok, texto, _meta}) do
    Logger.info("[NodoServidor] -> #{comando}: OK (#{resumen(texto)})")
  end

  defp registrar_respuesta(comando, {:error, motivo}) do
    Logger.warning("[NodoServidor] -> #{comando}: ERROR (#{motivo})")
  end

  # Nunca se registra la contraseña de connect.
  defp formatear_args("connect", [usuario | resto]) do
    case resto do
      [_password | demas] -> inspect([usuario, "***" | demas], limit: 20, printable_limit: 200)
      [] -> inspect([usuario], limit: 20, printable_limit: 200)
    end
  end

  defp formatear_args(_comando, args) do
    inspect(args, limit: 20, printable_limit: 200)
  end

  # Primera línea de la respuesta, recortada para no llenar la terminal.
  defp resumen(texto) do
    texto
    |> to_string()
    |> String.split("\n")
    |> List.first()
    |> String.slice(0, 120)
  end

  # ============ Despacho ============

  defp ejecutar(comando, args, cookie) do
    case comando do
      "connect" -> cmd_connect(args)
      "disconnect" -> cmd_disconnect(cookie)
      "help" -> cmd_help()
      "register_zone" -> con_sesion(cookie, @coordinacion, fn _ -> cmd_register_zone(args) end)
      "register_sector" -> con_sesion(cookie, @coordinacion, fn _ -> cmd_register_sector(args) end)
      "register_point" -> con_sesion(cookie, @coordinacion, fn _ -> cmd_register_point(args) end)
      "zone_status" -> con_sesion(cookie, @todos, fn _ -> cmd_zone_status(args) end)
      "zones_summary" -> con_sesion(cookie, @todos, fn _ -> cmd_zones_summary() end)
      "report_person" -> con_sesion(cookie, @todos, fn _ -> cmd_report_person(args) end)
      "find_person" -> con_sesion(cookie, @todos, fn _ -> cmd_find_person(args) end)
      "list_people" -> con_sesion(cookie, @todos, fn _ -> cmd_list_people() end)
      "change_person_status" -> con_sesion(cookie, @todos, fn _ -> cmd_change_person_status(args) end)
      "send_family_message" -> con_sesion(cookie, @todos, fn u -> cmd_send_message(args, u) end)
      "list_family_messages" -> con_sesion(cookie, @todos, fn _ -> cmd_list_messages(args) end)
      "register_need" -> con_sesion(cookie, @todos, fn u -> cmd_register_need(args, u) end)
      "list_needs" -> con_sesion(cookie, @todos, fn _ -> cmd_list_needs(args) end)
      "pending_needs" -> con_sesion(cookie, @todos, fn _ -> cmd_pending_needs() end)
      "assign_resource" -> con_sesion(cookie, @coordinacion, fn _ -> cmd_assign_resource(args) end)
      "register_resource" -> con_sesion(cookie, @gestion, fn _ -> cmd_register_resource(args) end)
      "list_resources" -> con_sesion(cookie, @todos, fn _ -> cmd_list_resources(args) end)
      "resource_entry" -> con_sesion(cookie, @gestion, fn _ -> cmd_entry_resource(args) end)
      "resource_exit" -> con_sesion(cookie, @gestion, fn _ -> cmd_exit_resource(args) end)
      "transfer_resource" -> con_sesion(cookie, @gestion, fn _ -> cmd_transfer_resource(args) end)
      "critical_resources" -> con_sesion(cookie, @todos, fn _ -> cmd_critical_resources(args) end)
      "report_pet" -> con_sesion(cookie, @todos, fn _ -> cmd_report_pet(args) end)
      "list_pets" -> con_sesion(cookie, @todos, fn _ -> cmd_list_pets(args) end)
      "match_pets" -> con_sesion(cookie, @todos, fn _ -> cmd_match_pets() end)
      "confirm_match" -> con_sesion(cookie, @gestion, fn _ -> cmd_confirm_match(args) end)
      "register_shelter" -> con_sesion(cookie, @gestion, fn _ -> cmd_register_shelter(args) end)
      "check_shelter" -> con_sesion(cookie, @todos, fn _ -> cmd_check_shelter(args) end)
      "register_entry" -> con_sesion(cookie, @gestion, fn _ -> cmd_entry_shelter(args) end)
      "register_exit" -> con_sesion(cookie, @gestion, fn _ -> cmd_exit_shelter(args) end)
      "shelter_report" -> con_sesion(cookie, @todos, fn _ -> cmd_shelter_report() end)
      "summary" -> con_sesion(cookie, @todos, fn _ -> cmd_summary() end)
      otro -> {:error, "Comando desconocido: #{otro}. Use help para ver la lista"}
    end
  end

  # ============ Sesión ============

  defp cmd_connect([usuario, password | resto]) do
    rol = Enum.at(resto, 0, "ciudadano")
    zona = Enum.at(resto, 1, "sin_zona")

    case Sesion.connect(usuario, password, rol: rol, zona: zona, nombre_completo: usuario) do
      {:ok, %{cookie: cookie, usuario: datos, nuevo: nuevo?}} ->
        estado = if nuevo?, do: "usuario nuevo", else: "usuario existente"

        {:ok,
         "Sesión iniciada: #{datos.nombre_usuario} (#{datos.rol}, #{estado}, zona #{datos.zona_principal})",
         %{cookie: cookie}}

      {:error, razon} ->
        {:error, "No se pudo conectar: " <> texto_error_sesion(razon)}
    end
  end

  defp cmd_connect(_args), do: {:error, "Uso: connect usuario contraseña [rol] [zona]"}

  defp cmd_disconnect(nil), do: {:error, "No hay una sesión activa"}

  defp cmd_disconnect(cookie) do
    case Sesion.disconnect(cookie) do
      :ok -> {:ok, "Sesión cerrada", %{cerrar_sesion: true}}
      {:error, :sesion_invalida} -> {:error, "La sesión no existe o ya fue cerrada"}
      {:error, razon} -> {:error, "No se pudo cerrar la sesión: #{inspect(razon)}"}
    end
  end

  defp con_sesion(cookie, roles, fun) do
    case autorizar(cookie, roles) do
      {:ok, usuario} -> fun.(usuario)
      {:error, _} = error -> error
    end
  end

  defp autorizar(nil, _roles) do
    {:error, "Debe iniciar sesión primero: connect usuario contraseña rol zona"}
  end

  defp autorizar(cookie, roles) do
    case Sesion.autorizar(cookie, roles) do
      {:ok, usuario} -> {:ok, usuario}
      {:error, :no_autorizado} -> {:error, "El usuario no tiene permisos para este comando"}
      {:error, _} -> {:error, "Sesión inválida; vuelva a conectarse"}
    end
  end

  defp texto_error_sesion(:credenciales_invalidas), do: "contraseña incorrecta"
  defp texto_error_sesion(:rol_no_permitido), do: "no se permite registrar administradores por este medio"
  defp texto_error_sesion(:usuario_invalido), do: "usuario inválido"
  defp texto_error_sesion(razon), do: inspect(razon)

  # ============ Zonas ============

  defp cmd_register_zone([codigo, nombre, nivel | resto]) do
    total = Enum.at(resto, 0, "0")

    resultado =
      case Util.a_entero(total) do
        {:ok, numero} -> Servidor.registrar_zona(codigo, nombre, nivel, numero)
        {:error, _} -> {:error, "El total de afectados debe ser un número entero"}
      end

    case resultado do
      {:ok, zona} -> {:ok, "Zona registrada\n" <> texto_zona(zona)}
      {:error, motivo} -> {:error, texto_error_zonas(motivo)}
    end
  end

  defp cmd_register_zone(_args),
    do: {:error, "Uso: register_zone codigo nombre nivel [personas]"}

  defp cmd_register_sector([codigo_zona, codigo, nombre | resto]) do
    case Servidor.registrar_sector(codigo_zona, codigo, nombre) do
      {:ok, zona} ->
        case Enum.at(resto, 0) do
          nil ->
            {:ok, "Sector registrado\n" <> texto_zona_detalle(zona)}

          nivel ->
            case Servidor.actualizar_nivel_zona(zona.codigo, nivel) do
              {:ok, zona} -> {:ok, "Sector registrado\n" <> texto_zona_detalle(zona)}
              {:error, motivo} -> {:error, texto_error_zonas(motivo)}
            end
        end

      {:error, motivo} ->
        {:error, texto_error_zonas(motivo)}
    end
  end

  defp cmd_register_sector(_args), do: {:error, "Uso: register_sector zona codigo nombre [nivel]"}

  defp cmd_register_point([codigo_zona, codigo_sector, codigo | resto]) do
    nombre = Enum.at(resto, 0, codigo)
    descripcion = Enum.at(resto, 1, "")

    case Servidor.registrar_punto(codigo_zona, codigo_sector, codigo, nombre, descripcion) do
      {:ok, zona} -> {:ok, "Punto de atención registrado\n" <> texto_zona_detalle(zona)}
      {:error, motivo} -> {:error, texto_error_zonas(motivo)}
    end
  end

  defp cmd_register_point(_args),
    do: {:error, "Uso: register_point zona sector codigo [nombre] [descripcion]"}

  defp cmd_zone_status([codigo]) do
    case Servidor.buscar_zona(codigo) do
      {:ok, zona} -> {:ok, texto_zona_detalle(zona)}
      {:error, motivo} -> {:error, texto_error_zonas(motivo)}
    end
  end

  defp cmd_zone_status(_args), do: {:error, "Uso: zone_status codigo"}

  defp cmd_zones_summary do
    resumen = Servidor.resumen_zonas()
    zonas = Servidor.listar_zonas()

    nivel =
      case resumen.nivel_maximo do
        {:ok, nivel} -> nivel
        {:error, _} -> "sin zonas"
      end

    cabecera =
      "Zonas: #{resumen.total_zonas} | Sectores: #{resumen.total_sectores} | " <>
        "Puntos: #{resumen.total_puntos} | Afectados: #{resumen.total_afectados} | " <>
        "Nivel máximo: #{nivel}"

    {:ok, cabecera <> "\n" <> enumerar(zonas, &texto_zona/1)}
  end

  # ============ Personas y mensajería ============

  defp cmd_report_person([documento, nombre, edad, zona, estado]) do
    reportar_persona(documento, nombre, edad, zona, estado)
  end

  defp cmd_report_person([documento, nombre, zona, estado]) do
    reportar_persona(documento, nombre, nil, zona, estado)
  end

  defp cmd_report_person(_args),
    do: {:error, "Uso: report_person documento nombre [edad] zona estado"}

  defp reportar_persona(documento, nombre, edad, zona, estado) do
    case Servidor.registrar_persona(documento, nombre, edad, zona, estado) do
      {:ok, persona} -> {:ok, "Persona registrada\n" <> Ciudadanos.texto_persona(persona)}
      {:error, motivo} -> {:error, Ciudadanos.mensaje_error(motivo)}
    end
  end

  defp cmd_find_person([clave]) do
    case String.split(clave, "=", parts: 2) do
      [_campo, _valor] ->
        with {:ok, filtros} <- parsear_filtros([clave], [:nombre, :documento, :zona, :estado]) do
          personas = Servidor.buscar_personas(filtros)
          {:ok, "Coincidencias: #{length(personas)}\n" <> enumerar(personas, &Ciudadanos.texto_persona/1)}
        end

      [_unico] ->
        case Servidor.buscar_persona(clave) do
          {:ok, persona} -> {:ok, Ciudadanos.texto_persona(persona)}
          {:error, motivo} -> {:error, Ciudadanos.mensaje_error(motivo)}
        end
    end
  end

  defp cmd_find_person(_args), do: {:error, "Uso: find_person documento | find_person nombre=texto"}

  defp cmd_list_people do
    personas = Servidor.listar_personas()
    {:ok, "Personas registradas: #{length(personas)}\n" <> enumerar(personas, &Ciudadanos.texto_persona/1)}
  end

  defp cmd_change_person_status([clave, estado]) do
    case Servidor.cambiar_estado_persona(clave, estado) do
      {:ok, persona} -> {:ok, "Estado actualizado\n" <> Ciudadanos.texto_persona(persona)}
      {:error, motivo} -> {:error, Ciudadanos.mensaje_error(motivo)}
    end
  end

  defp cmd_change_person_status(_args),
    do: {:error, "Uso: change_person_status id|documento estado"}

  defp cmd_send_message([documento | palabras], usuario) when palabras != [] do
    contenido = Enum.join(palabras, " ")
    remitente = usuario.nombre_usuario

    case Servidor.enviar_mensaje(remitente, documento, contenido) do
      {:ok, mensaje} -> {:ok, "Mensaje enviado\n" <> Ciudadanos.texto_mensaje(mensaje)}
      {:error, motivo} -> {:error, Ciudadanos.mensaje_error(motivo)}
    end
  end

  defp cmd_send_message(_args, _usuario),
    do: {:error, ~s(Uso: send_family_message documento "texto del mensaje")}

  defp cmd_list_messages([documento]) do
    mensajes = Servidor.listar_mensajes(documento)
    {:ok, "Mensajes para #{documento}: #{length(mensajes)}\n" <> enumerar(mensajes, &Ciudadanos.texto_mensaje/1)}
  end

  defp cmd_list_messages(_args), do: {:error, "Uso: list_family_messages documento"}

  # ============ Necesidades ============

  defp cmd_register_need(args, usuario) do
    {datos, responsable} = separar_responsable(args, usuario.nombre_usuario)

    case datos do
      [tipo, cantidad, prioridad, zona, descripcion] ->
        case Servidor.registrar_necesidad(tipo, cantidad, prioridad, zona, descripcion, responsable) do
          {:ok, necesidad} -> {:ok, "Necesidad registrada\n" <> Necesidades.texto_necesidad(necesidad)}
          {:error, motivo} -> {:error, Necesidades.mensaje_error(motivo)}
        end

      _ ->
        {:error,
         "Uso: register_need tipo cantidad prioridad zona descripcion [responsable]"}
    end
  end

  # Los últimos argumentos pueden traer espacios: se toma el último como
  # responsable solo cuando hay más de los cinco obligatorios.
  defp separar_responsable(args, por_defecto) do
    if length(args) > 5 do
      responsable = List.last(args)
      {Enum.take(args, length(args) - 1), responsable}
    else
      {args, por_defecto}
    end
  end

  defp cmd_list_needs(args) do
    with {:ok, filtros} <- parsear_filtros(args, [:zona, :tipo, :prioridad, :estado]) do
      necesidades = Servidor.listar_necesidades(filtros)

      {:ok,
       "Necesidades: #{length(necesidades)}\n" <> enumerar(necesidades, &Necesidades.texto_necesidad/1)}
    end
  end

  defp cmd_pending_needs do
    pendientes = Servidor.pendientes()
    {:ok, "Pendientes: #{length(pendientes)}\n" <> enumerar(pendientes, &Necesidades.texto_necesidad/1)}
  end

  defp cmd_assign_resource([id, clave, cantidad]) do
    case Servidor.asignar_recurso(id, clave, cantidad) do
      {:ok, resultado} ->
        {:ok, "Recurso asignado\n" <> Necesidades.texto_necesidad(resultado.necesidad)}

      {:error, motivo} ->
        {:error, Necesidades.mensaje_error(motivo)}
    end
  end

  defp cmd_assign_resource(_args),
    do: {:error, "Uso: assign_resource id_necesidad codigo|cantidad"}

  # ============ Recursos ============

  defp cmd_register_resource([codigo, nombre, categoria, cantidad, unidad, ubicacion]) do
    case Servidor.registrar_recurso(codigo, nombre, categoria, cantidad, unidad, ubicacion) do
      {:ok, recurso} -> {:ok, "Recurso registrado\n" <> Recursos.texto_recurso(recurso)}
      {:error, motivo} -> {:error, Recursos.mensaje_error(motivo)}
    end
  end

  defp cmd_register_resource(_args),
    do: {:error, "Uso: register_resource codigo nombre categoria cantidad unidad ubicacion"}

  defp cmd_list_resources(args) do
    with {:ok, filtros} <- parsear_filtros(args, [:codigo, :nombre, :categoria, :ubicacion]) do
      recursos = Servidor.listar_recursos(filtros)
      {:ok, "Recursos: #{length(recursos)}\n" <> enumerar(recursos, &Recursos.texto_recurso/1)}
    end
  end

  defp cmd_entry_resource([codigo, ubicacion, cantidad]) do
    case Servidor.entrada_recurso(codigo, ubicacion, cantidad) do
      {:ok, recurso} -> {:ok, "Entrada registrada\n" <> Recursos.texto_recurso(recurso)}
      {:error, motivo} -> {:error, Recursos.mensaje_error(motivo)}
    end
  end

  defp cmd_entry_resource(_args),
    do: {:error, "Uso: resource_entry codigo ubicacion cantidad"}

  defp cmd_exit_resource([codigo, ubicacion, cantidad]) do
    case Servidor.salida_recurso(codigo, ubicacion, cantidad) do
      {:ok, recurso} -> {:ok, "Salida registrada\n" <> Recursos.texto_recurso(recurso)}
      {:error, motivo} -> {:error, Recursos.mensaje_error(motivo)}
    end
  end

  defp cmd_exit_resource(_args),
    do: {:error, "Uso: resource_exit codigo ubicacion cantidad"}

  defp cmd_transfer_resource([codigo, origen, destino, cantidad]) do
    case Servidor.transferir_recurso(codigo, origen, destino, cantidad) do
      {:ok, {en_origen, en_destino}} ->
        {:ok,
         "Transferencia registrada\n" <>
           "  " <> Recursos.texto_recurso(en_origen) <> "\n  " <> Recursos.texto_recurso(en_destino)}

      {:error, motivo} ->
        {:error, Recursos.mensaje_error(motivo)}
    end
  end

  defp cmd_transfer_resource(_args),
    do: {:error, "Uso: transfer_resource codigo origen destino cantidad"}

  defp cmd_critical_resources(args) do
    umbral = Enum.at(args, 0, "20")

    with {:ok, umbral} <- Util.a_entero(umbral) do
      recursos = Servidor.criticos(umbral)

      {:ok,
       "Recursos críticos (<= #{umbral}): #{length(recursos)}\n" <>
         enumerar(recursos, &Recursos.texto_recurso/1)}
    else
      {:error, _} -> {:error, "El umbral debe ser un número entero"}
    end
  end

  # ============ Mascotas ============

  defp cmd_report_pet([tipo, especie, nombre, caracteristicas, color, tamano, zona, contacto]) do
    reportar_mascota(tipo, especie, nombre, caracteristicas, color, tamano, zona, contacto)
  end

  defp cmd_report_pet([tipo, especie, nombre, color, tamano, zona, contacto]) do
    reportar_mascota(tipo, especie, nombre, "", color, tamano, zona, contacto)
  end

  defp cmd_report_pet(_args),
    do: {:error, "Uso: report_pet tipo especie nombre [caracteristicas] color tamano zona contacto"}

  defp reportar_mascota(tipo, especie, nombre, caracteristicas, color, tamano, zona, contacto) do
    case Servidor.reportar_mascota(tipo, especie, nombre, caracteristicas, color, tamano, zona, contacto) do
      {:ok, mascota} -> {:ok, "Reporte registrado\n" <> Mascotas.texto_mascota(mascota)}
      {:error, motivo} -> {:error, Mascotas.mensaje_error(motivo)}
    end
  end

  defp cmd_list_pets(args) do
    with {:ok, filtros} <- parsear_filtros(args, [:tipo, :especie, :zona, :estado]) do
      mascotas = Servidor.listar_mascotas(filtros)
      {:ok, "Reportes de mascotas: #{length(mascotas)}\n" <> enumerar(mascotas, &Mascotas.texto_mascota/1)}
    end
  end

  defp cmd_match_pets do
    coincidencias = Servidor.emparejar_mascotas(30)
    {:ok, "Coincidencias: #{length(coincidencias)}\n" <> enumerar(coincidencias, &texto_match/1)}
  end

  defp cmd_confirm_match([id_perdida, id_encontrada]) do
    case Servidor.confirmar_match(id_perdida, id_encontrada) do
      {:ok, %{perdida: perdida, encontrada: encontrada}} ->
        {:ok,
         "Coincidencia confirmada: #{perdida.id} y #{encontrada.id} quedaron resueltas"}

      {:error, motivo} ->
        {:error, Mascotas.mensaje_error(motivo)}
    end
  end

  defp cmd_confirm_match(_args),
    do: {:error, "Uso: confirm_match id_perdida id_encontrada"}

  # ============ Albergues ============

  defp cmd_register_shelter([codigo, nombre, zona, capacidad]) do
    case Servidor.registrar_albergue(codigo, nombre, zona, capacidad) do
      {:ok, albergue} -> {:ok, "Albergue registrado\n" <> Albergues.texto_albergue(albergue)}
      {:error, motivo} -> {:error, Albergues.mensaje_error(motivo)}
    end
  end

  defp cmd_register_shelter(_args),
    do: {:error, "Uso: register_shelter codigo nombre zona capacidad"}

  defp cmd_check_shelter([codigo]) do
    case Servidor.buscar_albergue(codigo) do
      {:ok, albergue} -> {:ok, Albergues.texto_albergue(albergue)}
      {:error, motivo} -> {:error, Albergues.mensaje_error(motivo)}
    end
  end

  defp cmd_check_shelter(_args), do: {:error, "Uso: check_shelter codigo"}

  defp cmd_entry_shelter([codigo, documento]) do
    case Servidor.registrar_entrada_albergue(codigo, documento) do
      {:ok, albergue} -> {:ok, "Ingreso registrado\n" <> Albergues.texto_albergue(albergue)}
      {:error, motivo} -> {:error, Albergues.mensaje_error(motivo)}
    end
  end

  defp cmd_entry_shelter(_args), do: {:error, "Uso: register_entry codigo documento"}

  defp cmd_exit_shelter([codigo, documento]) do
    case Servidor.registrar_salida_albergue(codigo, documento) do
      {:ok, albergue} -> {:ok, "Salida registrada\n" <> Albergues.texto_albergue(albergue)}
      {:error, motivo} -> {:error, Albergues.mensaje_error(motivo)}
    end
  end

  defp cmd_exit_shelter(_args), do: {:error, "Uso: register_exit codigo documento"}

  defp cmd_shelter_report do
    reporte = Servidor.reporte_albergues()

    cabecera =
      "Albergues: #{reporte.total_albergues} | Capacidad: #{reporte.capacidad} | " <>
        "Ocupación: #{reporte.ocupacion} (#{reporte.porcentaje}%) | Cupos: #{reporte.disponibles}"

    {:ok, cabecera <> "\n" <> enumerar(reporte.detalle, & &1)}
  end

  # ============ Resumen y ayuda ============

  defp cmd_summary do
    resumen = Servidor.resumen()
    totales = resumen.albergues_totales

    lineas = [
      "Personas: #{resumen.personas} | Mensajes: #{resumen.mensajes} | Zonas: #{resumen.zonas}",
      "Necesidades: #{resumen.necesidades} (pendientes: #{resumen.necesidades_pendientes}) | Recursos: #{resumen.recursos}",
      "Albergues: #{resumen.albergues} | Capacidad: #{totales.capacidad} | Ocupación: #{totales.ocupacion} (#{resumen.porcentaje_ocupacion}%) | Cupos: #{totales.disponibles}",
      "Mascotas: #{resumen.mascotas}"
    ]

    {:ok, Enum.join(lineas, "\n")}
  end

  defp cmd_help do
    cuerpo = enumerar(@comandos, & &1)
    {:ok, "Comandos disponibles:\n" <> cuerpo}
  end

  # ============ Formato ============

  defp normalizar_comando(comando) do
    comando
    |> to_string()
    |> String.trim()
    |> String.downcase()
    |> String.replace("-", "_")
  end

  defp enumerar([], _fun), do: "  (sin resultados)"

  defp enumerar(elementos, fun) do
    Enum.map_join(elementos, "\n", fn elemento -> "  " <> fun.(elemento) end)
  end

  defp texto_zona(zona) do
    "#{zona.codigo} | #{zona.nombre} | Nivel: #{zona.nivel_afectacion} | " <>
      "Afectados: #{zona.total_afectados} | Sectores: #{map_size(zona.sectores)} | " <>
      "Puntos: #{Zonas.contar_puntos(zona)}"
  end

  defp texto_zona_detalle(zona) do
    sectores =
      Enum.map_join(zona.sectores |> Map.values() |> Enum.sort_by(& &1.codigo), "\n", fn sector ->
        puntos =
          case sector.puntos_atencion do
            [] -> "(ninguno)"
            lista -> Enum.map_join(lista, ", ", & &1.codigo)
          end

        "  #{sector.codigo} | #{sector.nombre} | Puntos: #{puntos}"
      end)

    texto_zona(zona) <> "\n" <> sectores
  end

  defp texto_match(%{perdida: perdida, encontrada: encontrada, puntaje: puntaje}) do
    "#{perdida.id} (#{perdida.especie}) <-> #{encontrada.id} (#{encontrada.especie}) | puntaje #{puntaje}"
  end

  defp texto_error_zonas(motivo) when is_binary(motivo), do: motivo
  defp texto_error_zonas(motivo), do: "Error: #{inspect(motivo)}"

  # ============ Filtros clave=valor ============

  defp parsear_filtros(args, permitidos) do
    Enum.reduce_while(args, {:ok, []}, fn arg, {:ok, acumulado} ->
      case String.split(arg, "=", parts: 2) do
        [clave, valor] ->
          case atomo_permitido(clave, permitidos) do
            nil ->
              {:halt,
               {:error,
                "Filtro desconocido: #{clave}. Válidos: #{Enum.join(permitidos, ", ")}"}}

            atomo ->
              {:cont, {:ok, acumulado ++ [{atomo, String.trim(valor)}]}}
          end

        [_unico] ->
          {:halt, {:error, "Filtro inválido: #{arg}. Use clave=valor"}}
      end
    end)
  end

  defp atomo_permitido(clave, permitidos) do
    buscada = clave |> String.trim() |> String.downcase()
    Enum.find(permitidos, fn atomo -> Atom.to_string(atomo) == buscada end)
  end
end
