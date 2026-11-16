defmodule Emergencia.Ciudadanos.Persona do
  @moduledoc """
  Representa una persona afectada por la emergencia.
  Formato de la línea: P|id|nombre|documento|edad|zona|estado|historial
  -version 1.0
  -autor: Daniel Gil
  -fecha: 2026-11-14
  """

  defstruct id: "",
            documento: "",
            nombre: "",
            edad: nil,
            zona: "",
            estado: :sin_informacion,
            historial: []
end

defmodule Emergencia.Ciudadanos.Mensaje do
  @moduledoc """
  Representa un mensaje dirigido a una persona (por su documento).
  Formato de la línea: M|id|fecha|remitente|destinatario|contenido|estado
  -version 1.0
  -autor: Daniel Gil
  -fecha: 2026-11-14
  """

  defstruct id: "", fecha: "", remitente: "", destinatario: "", contenido: "", estado: :pendiente
end

defmodule Emergencia.Ciudadanos do
  @moduledoc """
  Se encarga únicamente del registro de personas afectadas, la búsqueda
  recursiva y la mensajería familiar.
  No imprime ni crea procesos: recibe la lista actual y retorna la lista nueva.
  Retorna {:ok, elemento, lista_nueva} o {:error, motivo}.
  -version 1.0
  -autor: Daniel Gil
  -fecha: 2026-11-14
  """

  alias Emergencia.Ciudadanos.{Mensaje, Persona}

  @estados [:sin_informacion, :reportada, :localizada, :trasladada, :en_albergue, :reunificada]

  # Estados a los que se puede pasar desde cada estado. reunificada es un estado final.
  @transiciones %{
    sin_informacion: [:reportada, :localizada, :trasladada, :en_albergue],
    reportada: [:localizada, :trasladada, :en_albergue],
    localizada: [:trasladada, :en_albergue, :reunificada],
    trasladada: [:localizada, :en_albergue, :reunificada],
    en_albergue: [:localizada, :trasladada, :reunificada],
    reunificada: []
  }

  # ---------- Personas ----------

  @doc """
  Registra una persona afectada.
  El documento no puede repetirse y el ID se genera en orden (P001, P002...).
  Retorna {:ok, persona, personas} o {:error, motivo}.
  """
  def registrar_persona(personas, documento, nombre, edad, zona, estado \\ :reportada) do
    documento = limpiar(documento)
    nombre = limpiar(nombre)
    zona = limpiar(zona)
    edad = convertir_edad(edad)
    estado = convertir_estado(estado)

    cond do
      documento == "" or nombre == "" or zona == "" -> {:error, :campo_vacio}
      edad == :error -> {:error, :edad_invalida}
      is_integer(edad) and edad < 0 -> {:error, :edad_negativa}
      is_integer(edad) and edad > 120 -> {:error, :edad_invalida}
      estado == :error -> {:error, :estado_invalido}
      buscar_documento(personas, documento) != nil -> {:error, :documento_duplicado}
      true -> crear_persona(personas, documento, nombre, edad, zona, estado)
    end
  end

  defp crear_persona(personas, documento, nombre, edad, zona, estado) do
    persona = %Persona{
      id: siguiente_id(personas, "P"),
      documento: documento,
      nombre: nombre,
      edad: edad,
      zona: zona,
      estado: estado,
      historial: [{Emergencia.Util.fecha_hora(), estado}]
    }

    {:ok, persona, personas ++ [persona]}
  end

  @doc """
  Cambia el estado de una persona (se identifica por ID o por documento).
  Solo se permiten las transiciones válidas y cada cambio queda en el historial.
  Retorna {:ok, persona, personas} o {:error, motivo}.
  """
  def cambiar_estado(personas, clave, nuevo_estado) do
    case encontrar(personas, clave) do
      {:ok, persona} -> aplicar_estado(personas, persona, convertir_estado(nuevo_estado))
      {:error, motivo} -> {:error, motivo}
    end
  end

  defp aplicar_estado(_personas, _persona, :error), do: {:error, :estado_invalido}
  defp aplicar_estado(_personas, %Persona{estado: estado}, estado), do: {:error, :mismo_estado}

  defp aplicar_estado(personas, persona, nuevo) do
    if nuevo in Map.fetch!(@transiciones, persona.estado) do
      actualizada = %{
        persona
        | estado: nuevo,
          historial: persona.historial ++ [{Emergencia.Util.fecha_hora(), nuevo}]
      }

      {:ok, actualizada, reemplazar(personas, actualizada)}
    else
      {:error, :transicion_invalida}
    end
  end

  @doc """
  Busca una persona por ID o por documento.
  Retorna {:ok, persona} o {:error, :persona_no_encontrada}.
  """
  def encontrar(personas, clave) do
    buscado = normalizar(clave)

    case Enum.find(personas, fn persona ->
           normalizar(persona.id) == buscado or normalizar(persona.documento) == buscado
         end) do
      nil -> {:error, :persona_no_encontrada}
      persona -> {:ok, persona}
    end
  end

  @doc """
  Retorna el historial de cambios de estado de una persona.
  """
  def historial(personas, clave) do
    case encontrar(personas, clave) do
      {:ok, persona} -> {:ok, persona.historial}
      {:error, motivo} -> {:error, motivo}
    end
  end

  @doc """
  Convierte un texto (por ejemplo "en albergue" o "sin información") en un estado.
  Retorna el átomo del estado o :error si no es válido.
  """
  def convertir_estado(estado) when estado in @estados, do: estado

  def convertir_estado(texto) when is_binary(texto) do
    clave = texto |> normalizar() |> String.replace([" ", "-"], "_")

    case Enum.find(@estados, fn estado -> Atom.to_string(estado) == clave end) do
      nil -> :error
      estado -> estado
    end
  end

  def convertir_estado(_otro), do: :error

  # ---------- Búsqueda recursiva ----------

  @doc """
  Busca personas por varios criterios a la vez: :nombre (contiene el texto, sin
  distinguir mayúsculas ni tildes), :documento, :zona y :estado.
  Todos los criterios dados deben cumplirse. Se conserva el orden original.
  Ejemplo: buscar(personas, zona: "Z1", estado: "en albergue")
  """
  # Caso base: no quedan personas por revisar
  def buscar([], _criterios), do: []

  # Caso recursivo: si la cabeza cumple los criterios se conserva, y se sigue con el resto
  def buscar([persona | resto], criterios) do
    if cumple_criterios?(persona, criterios) do
      [persona | buscar(resto, criterios)]
    else
      buscar(resto, criterios)
    end
  end

  # Caso base: no quedan criterios por evaluar
  defp cumple_criterios?(_persona, []), do: true

  # Caso recursivo: se evalúa el primer criterio y luego los demás
  defp cumple_criterios?(persona, [{campo, valor} | resto]) do
    cumple_criterio?(persona, campo, valor) and cumple_criterios?(persona, resto)
  end

  defp cumple_criterio?(persona, :nombre, valor) do
    String.contains?(normalizar(persona.nombre), normalizar(valor))
  end

  defp cumple_criterio?(persona, :documento, valor) do
    normalizar(persona.documento) == normalizar(valor)
  end

  defp cumple_criterio?(persona, :zona, valor) do
    normalizar(persona.zona) == normalizar(valor)
  end

  defp cumple_criterio?(persona, :estado, valor) do
    persona.estado == convertir_estado(valor)
  end

  # Un criterio desconocido no se cumple
  defp cumple_criterio?(_persona, _campo, _valor), do: false

  @doc """
  Cuenta las personas por estado. Retorna un mapa %{estado => cantidad}.
  """
  def contar_por_estado(personas), do: contar_por_estado(personas, %{})

  # Caso base: se entrega el acumulador
  defp contar_por_estado([], acumulador), do: acumulador

  # Caso recursivo: se suma la cabeza al acumulador y se sigue con el resto
  defp contar_por_estado([persona | resto], acumulador) do
    contar_por_estado(resto, Map.update(acumulador, persona.estado, 1, fn cantidad -> cantidad + 1 end))
  end

  # ---------- Mensajería familiar ----------

  @doc """
  Registra un mensaje para una persona (por su documento). La persona debe estar
  registrada. El mensaje queda pendiente hasta que se marque como entregado.
  Retorna {:ok, mensaje, mensajes} o {:error, motivo}.
  """
  def enviar_mensaje(mensajes, personas, remitente, documento, contenido) do
    remitente = limpiar(remitente)
    documento = limpiar(documento)
    contenido = limpiar(contenido)
    destinatario = buscar_documento(personas, documento)

    cond do
      remitente == "" or documento == "" or contenido == "" -> {:error, :campo_vacio}
      destinatario == nil -> {:error, :destinatario_no_encontrado}
      true -> crear_mensaje(mensajes, remitente, destinatario.documento, contenido)
    end
  end

  defp crear_mensaje(mensajes, remitente, documento, contenido) do
    mensaje = %Mensaje{
      id: siguiente_id(mensajes, "MSG"),
      fecha: Emergencia.Util.fecha_hora(),
      remitente: remitente,
      destinatario: documento,
      contenido: contenido,
      estado: :pendiente
    }

    {:ok, mensaje, mensajes ++ [mensaje]}
  end

  @doc """
  Lista los mensajes dirigidos a un documento.
  """
  def listar_mensajes(mensajes, documento) do
    buscado = normalizar(documento)
    Enum.filter(mensajes, fn mensaje -> normalizar(mensaje.destinatario) == buscado end)
  end

  @doc """
  Marca un mensaje como entregado o pendiente.
  Retorna {:ok, mensaje, mensajes} o {:error, motivo}.
  """
  def marcar_mensaje(mensajes, id, estado) do
    estado = convertir_estado_mensaje(estado)
    mensaje = Enum.find(mensajes, fn mensaje -> mensaje.id == id end)

    cond do
      estado == :error -> {:error, :estado_mensaje_invalido}
      mensaje == nil -> {:error, :mensaje_no_encontrado}
      true ->
        actualizado = %{mensaje | estado: estado}
        {:ok, actualizado, reemplazar(mensajes, actualizado)}
    end
  end

  defp convertir_estado_mensaje(estado) when estado in [:pendiente, :entregado], do: estado

  defp convertir_estado_mensaje(texto) when is_binary(texto) do
    case normalizar(texto) do
      "entregado" -> :entregado
      "pendiente" -> :pendiente
      _ -> :error
    end
  end

  defp convertir_estado_mensaje(_otro), do: :error

  # ---------- Texto para mostrar (se imprime con Util.mostrar_mensaje) ----------

  @doc """
  Arma el texto de una persona para mostrarla en consola.
  """
  def texto_persona(persona) do
    edad = if persona.edad == nil, do: "sin dato", else: persona.edad

    "#{persona.id} | #{persona.nombre} | Documento: #{persona.documento} | Edad: #{edad} | " <>
      "Zona: #{persona.zona} | Estado: #{texto_estado(persona.estado)}"
  end

  @doc """
  Arma el texto de un mensaje para mostrarlo en consola.
  """
  def texto_mensaje(mensaje) do
    "#{mensaje.id} | #{mensaje.fecha} | De: #{mensaje.remitente} | Para: #{mensaje.destinatario} | " <>
      "#{mensaje.contenido} | #{mensaje.estado}"
  end

  @doc """
  Texto legible de un estado (en_albergue -> "en albergue").
  """
  def texto_estado(:sin_informacion), do: "sin información"
  def texto_estado(estado), do: estado |> Atom.to_string() |> String.replace("_", " ")

  @doc """
  Traduce el motivo de un error a un mensaje para el usuario.
  """
  def mensaje_error(:campo_vacio), do: "Hay campos obligatorios vacíos"
  def mensaje_error(:edad_invalida), do: "La edad debe ser un número entre 0 y 120"
  def mensaje_error(:edad_negativa), do: "La edad no puede ser negativa"
  def mensaje_error(:estado_invalido), do: "Estado inválido (sin información, reportada, localizada, trasladada, en albergue, reunificada)"
  def mensaje_error(:documento_duplicado), do: "Ya existe una persona con ese documento"
  def mensaje_error(:persona_no_encontrada), do: "Persona no encontrada"
  def mensaje_error(:mismo_estado), do: "La persona ya se encuentra en ese estado"
  def mensaje_error(:transicion_invalida), do: "No se puede pasar a ese estado desde el estado actual"
  def mensaje_error(:destinatario_no_encontrado), do: "El destinatario no está registrado"
  def mensaje_error(:mensaje_no_encontrado), do: "Mensaje no encontrado"
  def mensaje_error(:estado_mensaje_invalido), do: "Estado de mensaje inválido (entregado o pendiente)"
  def mensaje_error(:linea_invalida), do: "Línea de archivo inválida"
  def mensaje_error(otro), do: "Error: #{inspect(otro)}"

  # ---------- Persistencia (texto plano, campos separados por |) ----------

  @doc """
  Convierte una persona en una línea: P|id|nombre|documento|edad|zona|estado|historial
  El historial se guarda como fecha=estado separado por ;
  """
  def persona_a_linea(persona) do
    historial =
      persona.historial
      |> Enum.map(fn {fecha, estado} -> "#{fecha}=#{estado}" end)
      |> Enum.join(";")

    ["P", persona.id, persona.nombre, persona.documento, persona.edad, persona.zona, texto_estado(persona.estado), historial]
    |> Enum.join("|")
  end

  @doc """
  Convierte una línea en una persona (acepta líneas antiguas sin historial).
  Retorna {:ok, persona} o {:error, :linea_invalida}.
  """
  def linea_a_persona(linea) do
    case linea |> String.trim() |> String.split("|") do
      ["P", id, nombre, documento, edad, zona, estado | resto] when length(resto) <= 1 ->
        edad = convertir_edad(edad)
        estado = convertir_estado(estado)

        if edad == :error or estado == :error do
          {:error, :linea_invalida}
        else
          {:ok,
           %Persona{
             id: id,
             nombre: nombre,
             documento: documento,
             edad: edad,
             zona: zona,
             estado: estado,
             historial: resto |> List.first("") |> convertir_historial()
           }}
        end

      _ ->
        {:error, :linea_invalida}
    end
  end

  @doc """
  Convierte las líneas de un archivo en personas, ignorando las líneas inválidas.
  """
  def personas_desde_lineas(lineas) do
    lineas
    |> Enum.map(&linea_a_persona/1)
    |> Enum.filter(fn {estado, _} -> estado == :ok end)
    |> Enum.map(fn {_estado, persona} -> persona end)
  end

  @doc """
  Convierte las personas en líneas de texto para guardarlas en el archivo.
  """
  def personas_a_lineas(personas), do: Enum.map(personas, &persona_a_linea/1)

  @doc """
  Convierte un mensaje en una línea: M|id|fecha|remitente|destinatario|contenido|estado
  """
  def mensaje_a_linea(mensaje) do
    ["M", mensaje.id, mensaje.fecha, mensaje.remitente, mensaje.destinatario, mensaje.contenido, mensaje.estado]
    |> Enum.join("|")
  end

  @doc """
  Convierte una línea en un mensaje.
  Retorna {:ok, mensaje} o {:error, :linea_invalida}.
  """
  def linea_a_mensaje(linea) do
    case linea |> String.trim() |> String.split("|") do
      ["M", id, fecha, remitente, destinatario, contenido, estado] ->
        estado = convertir_estado_mensaje(estado)

        if estado == :error do
          {:error, :linea_invalida}
        else
          {:ok,
           %Mensaje{
             id: id,
             fecha: fecha,
             remitente: remitente,
             destinatario: destinatario,
             contenido: contenido,
             estado: estado
           }}
        end

      _ ->
        {:error, :linea_invalida}
    end
  end

  @doc """
  Convierte las líneas de un archivo en mensajes, ignorando las líneas inválidas.
  """
  def mensajes_desde_lineas(lineas) do
    lineas
    |> Enum.map(&linea_a_mensaje/1)
    |> Enum.filter(fn {estado, _} -> estado == :ok end)
    |> Enum.map(fn {_estado, mensaje} -> mensaje end)
  end

  @doc """
  Convierte los mensajes en líneas de texto para guardarlos en el archivo.
  """
  def mensajes_a_lineas(mensajes), do: Enum.map(mensajes, &mensaje_a_linea/1)

  # ---------- Funciones privadas ----------

  defp buscar_documento(personas, documento) do
    buscado = normalizar(documento)
    Enum.find(personas, fn persona -> normalizar(persona.documento) == buscado end)
  end

  # Retorna un entero, nil si no se dio edad, o :error si no es válida
  defp convertir_edad(nil), do: nil
  defp convertir_edad(""), do: nil
  defp convertir_edad(edad) when is_integer(edad), do: edad

  defp convertir_edad(texto) when is_binary(texto) do
    case Integer.parse(String.trim(texto)) do
      {numero, ""} -> numero
      _ -> :error
    end
  end

  defp convertir_edad(_otro), do: :error

  defp convertir_historial(""), do: []

  defp convertir_historial(texto) do
    texto
    |> String.split(";", trim: true)
    |> Enum.map(fn entrada -> String.split(entrada, "=", parts: 2) end)
    |> Enum.filter(fn partes -> length(partes) == 2 end)
    |> Enum.map(fn [fecha, estado] -> {fecha, convertir_estado(estado)} end)
    |> Enum.filter(fn {_fecha, estado} -> estado != :error end)
  end

  # Quita el separador | y los saltos de línea para no dañar el archivo de texto
  defp limpiar(texto) when is_binary(texto) do
    texto
    |> String.replace(["|", "\r", "\n"], " ")
    |> String.trim()
  end

  defp limpiar(_otro), do: ""

  # Minúsculas y sin tildes, para comparar textos
  defp normalizar(texto) when is_binary(texto) do
    texto
    |> String.trim()
    |> String.downcase()
    |> :unicode.characters_to_nfd_binary()
    |> Emergencia.Util.sin_tildes()
  end

  defp normalizar(nil), do: ""
  defp normalizar(otro), do: otro |> to_string() |> normalizar()

  # ID en orden: P001, P002... (los ID con otro formato no se tienen en cuenta)
  defp siguiente_id(elementos, prefijo) do
    mayor =
      Enum.reduce(elementos, 0, fn elemento, acumulado ->
        case Emergencia.Util.numero_id(elemento.id, prefijo) do
          0 -> acumulado
          numero -> max(acumulado, numero)
        end
      end)

    prefijo <> String.pad_leading(Integer.to_string(mayor + 1), 3, "0")
  end

  # Reemplaza el elemento con el mismo id (recursivo)
  defp reemplazar([], _nuevo), do: []
  defp reemplazar([%{id: id} | resto], %{id: id} = nuevo), do: [nuevo | resto]
  defp reemplazar([otro | resto], nuevo), do: [otro | reemplazar(resto, nuevo)]
end
