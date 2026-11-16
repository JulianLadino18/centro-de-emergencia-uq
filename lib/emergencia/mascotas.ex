defmodule Emergencia.Mascotas.Mascota do
  @moduledoc """
  Representa un reporte de mascota perdida o encontrada.
  Formato de la línea: MA|id|tipo|especie|nombre|caracteristicas|color|tamano|zona|contacto|estado
  -version 1.0
  -autor: equipo Programación III
  -fecha: 2026-11-15
  """

  defstruct id: "",
            tipo: :perdida,
            especie: "",
            nombre: "",
            caracteristicas: "",
            color: "",
            tamano: "",
            zona: "",
            contacto: "",
            estado: :abierta
end

defmodule Emergencia.Mascotas do
  @moduledoc """
  Se encarga únicamente de los reportes de mascotas perdidas/encontradas y del
  emparejamiento por similitud.
  Puntaje de similitud (0 a 100): especie 30, color 25, tamaño 20, zona 15,
  características 10. Un par solo se considera coincidencia si alcanza el
  umbral mínimo de 30 puntos.
  confirmar_match/3 cierra ambos reportes como :resuelta y no permite resolver
  dos veces el mismo reporte.
  -version 1.0
  -autor: equipo Programación III
  -fecha: 2026-11-15
  """

  alias Emergencia.Mascotas.Mascota

  @tipos [:perdida, :encontrada]
  @estados [:abierta, :resuelta]

  @peso_especie 30
  @peso_color 25
  @peso_tamano 20
  @peso_zona 15
  @peso_caracteristicas 10
  @umbral 30

  # ---------- Reportes ----------

  @doc """
  Registra un reporte de mascota. tipo acepta perdida/encontrada (y lost/found).
  Especie, color, tamaño y zona son obligatorios. El ID se genera en orden
  (M001, M002...). El reporte nace abierto.
  Retorna {:ok, mascota, mascotas} o {:error, motivo}.
  """
  def reportar(mascotas, tipo, especie, nombre, caracteristicas, color, tamano, zona, contacto) do
    tipo = convertir_tipo(tipo)
    especie = limpiar(especie)
    nombre = limpiar(nombre)
    caracteristicas = limpiar(caracteristicas)
    color = limpiar(color)
    tamano = limpiar(tamano)
    zona = limpiar(zona)
    contacto = limpiar(contacto)

    cond do
      tipo == :error ->
        {:error, :tipo_invalido}

      especie == "" or color == "" or tamano == "" or zona == "" ->
        {:error, :campo_vacio}

      true ->
        mascota = %Mascota{
          id: siguiente_id(mascotas, "M"),
          tipo: tipo,
          especie: especie,
          nombre: if(nombre == "", do: "Desconocida", else: nombre),
          caracteristicas: caracteristicas,
          color: color,
          tamano: tamano,
          zona: zona,
          contacto: contacto,
          estado: :abierta
        }

        {:ok, mascota, mascotas ++ [mascota]}
    end
  end

  @doc """
  Busca una mascota por su ID.
  Retorna {:ok, mascota} o {:error, :mascota_no_encontrada}.
  """
  def buscar(mascotas, id) do
    buscado = normalizar(id)

    case Enum.find(mascotas, fn mascota -> normalizar(mascota.id) == buscado end) do
      nil -> {:error, :mascota_no_encontrada}
      mascota -> {:ok, mascota}
    end
  end

  @doc """
  Retorna la lista de reportes (sin filtrar).
  """
  def listar(mascotas), do: mascotas

  @doc """
  Filtra reportes por :tipo, :estado, :especie o :zona (todos los criterios
  dados deben cumplirse). Se conserva el orden original.
  """
  # Caso base: no quedan reportes por revisar
  def filtrar([], _criterios), do: []

  # Caso recursivo: si la cabeza cumple los criterios se conserva
  def filtrar([mascota | resto], criterios) do
    if cumple_criterios?(mascota, criterios) do
      [mascota | filtrar(resto, criterios)]
    else
      filtrar(resto, criterios)
    end
  end

  # ---------- Puntaje de similitud ----------

  @doc """
  Calcula el puntaje de similitud entre dos reportes (0 a 100).
  """
  def puntaje(%Mascota{} = a, %Mascota{} = b) do
    puntos_especie(a.especie, b.especie) +
      puntos_color(a.color, b.color) +
      puntos_tamano(a.tamano, b.tamano) +
      puntos_zona(a.zona, b.zona) +
      puntos_caracteristicas(a.caracteristicas, b.caracteristicas)
  end

  @doc """
  Indica si dos reportes son una coincidencia válida: deben ser de tipo opuesto
  (una perdida y una encontrada) y alcanzar el umbral mínimo de 30 puntos.
  """
  def coincidencia?(%Mascota{} = a, %Mascota{} = b) do
    tipos_opuestos?(a.tipo, b.tipo) and puntaje(a, b) >= @umbral
  end

  def coincidencia?(_a, _b), do: false

  @doc """
  Compara un reporte contra una lista de reportes y retorna las coincidencias
  (solo con reportes de tipo opuesto, abiertos y con puntaje >= umbral).
  """
  def comparar_con_todas(%Mascota{tipo: :perdida} = mascota, otras, umbral) when is_list(otras),
    do: comparar_lista(mascota, otras, umbral)

  def comparar_con_todas(%Mascota{tipo: :encontrada} = mascota, otras, umbral) when is_list(otras),
    do: comparar_lista(mascota, otras, umbral)

  def comparar_con_todas(_mascota, _otras, _umbral), do: []

  # Caso base: no quedan reportes con los que comparar
  defp comparar_lista(_mascota, [], _umbral), do: []

  # Caso recursivo: se evalúa la cabeza y se sigue con el resto
  defp comparar_lista(%Mascota{} = mascota, [otra | resto], umbral) do
    actual = if candidata?(mascota, otra, umbral), do: [crear_match(mascota, otra)], else: []
    actual ++ comparar_lista(mascota, resto, umbral)
  end

  @doc """
  Genera todas las coincidencias entre reportes perdidos y encontrados,
  ordenadas de mayor a menor puntaje.
  """
  def emparejar(mascotas, umbral \\ @umbral)

  def emparejar(mascotas, umbral) when is_list(mascotas) do
    emparejar_perdidas(mascotas, mascotas, umbral) |> ordenar_por_puntaje()
  end

  # Caso base: no quedan reportes por revisar
  defp emparejar_perdidas([], _todas, _umbral), do: []

  # Caso recursivo: cada reporte perdido y abierto se compara con todos
  defp emparejar_perdidas([%Mascota{tipo: :perdida, estado: :abierta} = perdida | resto], todas, umbral) do
    comparar_con_todas(perdida, todas, umbral) ++ emparejar_perdidas(resto, todas, umbral)
  end

  defp emparejar_perdidas([_ | resto], todas, umbral), do: emparejar_perdidas(resto, todas, umbral)

  @doc """
  Ordena recursivamente las coincidencias por puntaje descendente.
  Es estable: a igual puntaje se conserva el orden original.
  """
  # Caso base: una lista vacía ya está ordenada
  def ordenar_por_puntaje([]), do: []

  # Caso recursivo: se ordena la cola y se inserta la cabeza en su lugar
  def ordenar_por_puntaje([cabeza | cola]) do
    insertar_por_puntaje(cabeza, ordenar_por_puntaje(cola))
  end

  # Caso base: la lista ordenada está vacía
  defp insertar_por_puntaje(coincidencia, []), do: [coincidencia]

  # Caso recursivo: se inserta antes de la primera con menor puntaje
  defp insertar_por_puntaje(coincidencia, [primera | resto] = ordenadas) do
    if coincidencia.puntaje >= primera.puntaje do
      [coincidencia | ordenadas]
    else
      [primera | insertar_por_puntaje(coincidencia, resto)]
    end
  end

  # ---------- Confirmación de coincidencias ----------

  @doc """
  Confirma una coincidencia entre un reporte perdido y uno encontrado.
  Ambos reportes quedan en estado :resuelta. Falla si alguno ya estaba
  resuelto (no se resuelve dos veces), si son el mismo reporte o si los
  tipos no son compatibles.
  Retorna {:ok, %{perdida: ..., encontrada: ...}, mascotas} o {:error, motivo}.
  """
  def confirmar_match(mascotas, id_perdida, id_encontrada) do
    with {:ok, primera} <- buscar(mascotas, id_perdida),
         {:ok, segunda} <- buscar(mascotas, id_encontrada),
         :ok <- validar_par(primera, segunda) do
      perdida = %{primera | estado: :resuelta}
      encontrada = %{segunda | estado: :resuelta}

      nuevas =
        mascotas
        |> reemplazar(perdida)
        |> reemplazar(encontrada)

      {:ok, %{perdida: perdida, encontrada: encontrada}, nuevas}
    end
  end

  # ---------- Conversión de catálogos ----------

  @doc """
  Convierte un texto en :perdida o :encontrada (acepta lost/found).
  Retorna el átomo o :error.
  """
  def convertir_tipo(tipo) when tipo in @tipos, do: tipo

  def convertir_tipo(texto) when is_binary(texto) do
    case normalizar(texto) do
      "perdida" -> :perdida
      "perdido" -> :perdida
      "lost" -> :perdida
      "encontrada" -> :encontrada
      "encontrado" -> :encontrada
      "found" -> :encontrada
      _ -> :error
    end
  end

  def convertir_tipo(_otro), do: :error

  @doc """
  Convierte un texto en :abierta o :resuelta.
  Retorna el átomo o :error.
  """
  def convertir_estado(estado) when estado in @estados, do: estado

  def convertir_estado(texto) when is_binary(texto) do
    case normalizar(texto) do
      "abierta" -> :abierta
      "abierto" -> :abierta
      "pendiente" -> :abierta
      "resuelta" -> :resuelta
      "resuelto" -> :resuelta
      "cerrada" -> :resuelta
      "cerrado" -> :resuelta
      _ -> :error
    end
  end

  def convertir_estado(_otro), do: :error

  # ---------- Texto para mostrar ----------

  @doc """
  Arma el texto de una mascota para mostrarla en consola.
  """
  def texto_mascota(%Mascota{} = mascota) do
    "#{mascota.id} | #{texto_tipo(mascota.tipo)} | #{mascota.especie} | " <>
      "Nombre: #{mascota.nombre} | Color: #{mascota.color} | Tamaño: #{mascota.tamano} | " <>
      "Zona: #{mascota.zona} | Estado: #{texto_estado(mascota.estado)}"
  end

  @doc """
  Traduce el tipo de reporte a texto.
  """
  def texto_tipo(:perdida), do: "perdida"
  def texto_tipo(:encontrada), do: "encontrada"
  def texto_tipo(otro), do: to_string(otro)

  @doc """
  Traduce el estado del reporte a texto.
  """
  def texto_estado(:abierta), do: "abierta"
  def texto_estado(:resuelta), do: "resuelta"
  def texto_estado(otro), do: to_string(otro)

  @doc """
  Traduce el motivo de un error a un mensaje para el usuario.
  """
  def mensaje_error(:campo_vacio), do: "Hay campos obligatorios vacíos"
  def mensaje_error(:tipo_invalido), do: "Tipo inválido (perdida o encontrada)"
  def mensaje_error(:mascota_no_encontrada), do: "Reporte de mascota no encontrado"
  def mensaje_error(:mismo_reporte), do: "No se puede confirmar un reporte consigo mismo"
  def mensaje_error(:reporte_ya_resuelto), do: "El reporte ya está resuelto"
  def mensaje_error(:tipos_incompatibles), do: "Se necesita un reporte perdido y uno encontrado"
  def mensaje_error(:linea_invalida), do: "Línea de archivo inválida"
  def mensaje_error(otro), do: "Error: #{inspect(otro)}"

  # ---------- Persistencia (texto plano, campos separados por |) ----------

  @doc """
  Convierte una mascota en una línea:
  MA|id|tipo|especie|nombre|caracteristicas|color|tamano|zona|contacto|estado
  """
  def a_linea(%Mascota{} = mascota) do
    [
      "MA",
      mascota.id,
      texto_tipo(mascota.tipo),
      mascota.especie,
      mascota.nombre,
      mascota.caracteristicas,
      mascota.color,
      mascota.tamano,
      mascota.zona,
      mascota.contacto,
      texto_estado(mascota.estado)
    ]
    |> Enum.join("|")
  end

  @doc """
  Convierte una línea en una mascota (acepta los prefijos MA y M).
  Retorna {:ok, mascota} o {:error, :linea_invalida}.
  """
  def desde_linea(linea) do
    case linea |> String.trim() |> String.split("|") do
      [prefijo, id, tipo, especie, nombre, caracteristicas, color, tamano, zona, contacto, estado]
      when prefijo in ["MA", "M"] ->
        tipo = convertir_tipo(tipo)
        estado = convertir_estado(estado)

        if :error in [tipo, estado] do
          {:error, :linea_invalida}
        else
          {:ok,
           %Mascota{
             id: id,
             tipo: tipo,
             especie: especie,
             nombre: nombre,
             caracteristicas: caracteristicas,
             color: color,
             tamano: tamano,
             zona: zona,
             contacto: contacto,
             estado: estado
           }}
        end

      _ ->
        {:error, :linea_invalida}
    end
  end

  @doc """
  Convierte las líneas de un archivo en mascotas, ignorando las inválidas.
  """
  def desde_lineas(lineas) do
    lineas
    |> Enum.map(&desde_linea/1)
    |> Enum.filter(fn {estado, _} -> estado == :ok end)
    |> Enum.map(fn {_estado, mascota} -> mascota end)
  end

  @doc """
  Convierte las mascotas en líneas de texto para guardarlas en el archivo.
  """
  def a_lineas(mascotas), do: Enum.map(mascotas, &a_linea/1)

  # ---------- Funciones privadas ----------

  defp tipos_opuestos?(:perdida, :encontrada), do: true
  defp tipos_opuestos?(:encontrada, :perdida), do: true
  defp tipos_opuestos?(_a, _b), do: false

  defp candidata?(%Mascota{id: id}, %Mascota{id: id}, _umbral), do: false

  defp candidata?(%Mascota{} = mascota, %Mascota{} = otra, umbral) do
    mascota.estado == :abierta and
      otra.estado == :abierta and
      tipos_opuestos?(mascota.tipo, otra.tipo) and
      puntaje(mascota, otra) >= umbral
  end

  defp crear_match(%Mascota{tipo: :perdida} = perdida, %Mascota{tipo: :encontrada} = encontrada) do
    %{perdida: perdida, encontrada: encontrada, puntaje: puntaje(perdida, encontrada)}
  end

  defp crear_match(%Mascota{tipo: :encontrada} = encontrada, %Mascota{tipo: :perdida} = perdida) do
    %{perdida: perdida, encontrada: encontrada, puntaje: puntaje(perdida, encontrada)}
  end

  defp validar_par(%Mascota{id: id}, %Mascota{id: id}), do: {:error, :mismo_reporte}
  defp validar_par(%Mascota{estado: :resuelta}, _segunda), do: {:error, :reporte_ya_resuelto}
  defp validar_par(_primera, %Mascota{estado: :resuelta}), do: {:error, :reporte_ya_resuelto}
  defp validar_par(%Mascota{tipo: :perdida}, %Mascota{tipo: :encontrada}), do: :ok
  defp validar_par(%Mascota{tipo: :encontrada}, %Mascota{tipo: :perdida}), do: :ok
  defp validar_par(_primera, _segunda), do: {:error, :tipos_incompatibles}

  defp puntos_especie(especie_a, especie_b) do
    if coincide_texto?(especie_a, especie_b), do: @peso_especie, else: 0
  end

  defp puntos_color(color_a, color_b) do
    if coincide_texto?(color_a, color_b), do: @peso_color, else: 0
  end

  defp puntos_tamano(tamano_a, tamano_b) do
    if coincide_texto?(tamano_a, tamano_b), do: @peso_tamano, else: 0
  end

  defp puntos_zona(zona_a, zona_b) do
    if coincide_texto?(zona_a, zona_b), do: @peso_zona, else: 0
  end

  defp puntos_caracteristicas(caracteristicas_a, caracteristicas_b) do
    palabras_a = palabras(caracteristicas_a)
    palabras_b = palabras(caracteristicas_b)

    cond do
      palabras_a == [] or palabras_b == [] ->
        0

      true ->
        comunes = palabras_a |> interseccion(palabras_b) |> Enum.uniq() |> length()
        total = max(length(palabras_a), length(palabras_b))
        round(@peso_caracteristicas * comunes / total)
    end
  end

  defp coincide_texto?(a, b) do
    normalizado_a = normalizar(a)
    normalizado_b = normalizar(b)
    normalizado_a != "" and normalizado_b != "" and normalizado_a == normalizado_b
  end

  defp palabras(texto) do
    texto
    |> normalizar()
    |> Emergencia.Util.palabras()
    |> Enum.uniq()
  end

  # Intersección recursiva de dos listas de palabras
  defp interseccion([], _otras), do: []

  defp interseccion([palabra | resto], otras) do
    if palabra in otras do
      [palabra | interseccion(resto, otras)]
    else
      interseccion(resto, otras)
    end
  end

  defp cumple_criterios?(_mascota, []), do: true
  defp cumple_criterios?(mascota, [{campo, valor} | resto]) do
    cumple_criterio?(mascota, campo, valor) and cumple_criterios?(mascota, resto)
  end

  defp cumple_criterio?(mascota, :tipo, valor), do: mascota.tipo == convertir_tipo(valor)
  defp cumple_criterio?(mascota, :estado, valor), do: mascota.estado == convertir_estado(valor)
  defp cumple_criterio?(mascota, :especie, valor), do: normalizar(mascota.especie) == normalizar(valor)
  defp cumple_criterio?(mascota, :zona, valor), do: normalizar(mascota.zona) == normalizar(valor)
  defp cumple_criterio?(_mascota, _campo, _valor), do: false

  # ID en orden: M001, M002... (los ID con otro formato no se tienen en cuenta)
  defp siguiente_id(mascotas, prefijo) do
    mayor =
      Enum.reduce(mascotas, 0, fn mascota, acumulado ->
        case Emergencia.Util.numero_id(mascota.id, prefijo) do
          0 -> acumulado
          numero -> max(acumulado, numero)
        end
      end)

    prefijo <> String.pad_leading(Integer.to_string(mayor + 1), 3, "0")
  end

  # Reemplaza la mascota con el mismo id (recursivo)
  defp reemplazar([], _nueva), do: []
  defp reemplazar([%{id: id} | resto], %{id: id} = nueva), do: [nueva | resto]
  defp reemplazar([otra | resto], nueva), do: [otra | reemplazar(resto, nueva)]

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
end
