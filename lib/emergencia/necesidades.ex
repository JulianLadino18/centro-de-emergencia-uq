defmodule Emergencia.Necesidades.Necesidad do
  @moduledoc """
  Representa una solicitud de ayuda.
  asignado es la cantidad acumulada ya cubierta con recursos y recursos son los
  códigos de los recursos usados.
  Formato de la línea: N|id|tipo|cantidad|prioridad|zona|descripcion|recursos|estado|asignado|responsable
  -version 1.0
  -autor: Daniel Gil
  -fecha: 2026-11-14
  """

  defstruct id: "",
            tipo: :otra,
            cantidad: 0,
            prioridad: :media,
            zona: "",
            descripcion: "",
            responsable: "",
            estado: :pendiente,
            recursos: [],
            asignado: 0
end

defmodule Emergencia.Necesidades do
  @moduledoc """
  Se encarga únicamente de las necesidades: registro, estados, priorización,
  filtros y asignación de recursos.
  No imprime ni crea procesos: recibe la lista actual y retorna la lista nueva.
  La prioridad se usa de verdad: ordenar_por_prioridad/1 ordena las solicitudes
  (las críticas primero) y siguiente/1 elige la que se debe atender.
  -version 1.0
  -autor: Daniel Gil
  -fecha: 2026-11-14
  """

  alias Emergencia.Necesidades.Necesidad
  alias Emergencia.Recursos

  @tipos [:agua, :alimentos, :medicamentos, :primeros_auxilios, :refugio, :transporte, :rescate, :otra]
  @prioridades [:critica, :alta, :media, :baja]
  @estados [:pendiente, :asignada, :en_atencion, :atendida, :cancelada]

  # Estados a los que se puede pasar desde cada estado. atendida y cancelada son finales.
  @transiciones %{
    pendiente: [:asignada, :cancelada],
    asignada: [:en_atencion, :atendida, :cancelada],
    en_atencion: [:atendida, :cancelada],
    atendida: [],
    cancelada: []
  }

  # ---------- Registro y estados ----------

  @doc """
  Registra una necesidad. El ID se genera en orden (N001, N002...), la cantidad
  debe ser mayor que cero y la necesidad nace en estado pendiente.
  Retorna {:ok, necesidad, necesidades} o {:error, motivo}.
  """
  def registrar(necesidades, tipo, cantidad, prioridad, zona, descripcion, responsable \\ "sistema") do
    tipo = convertir(tipo, @tipos)
    cantidad = convertir_entero(cantidad)
    prioridad = convertir(prioridad, @prioridades)
    zona = limpiar(zona)
    descripcion = limpiar(descripcion)
    responsable = limpiar(responsable)

    cond do
      zona == "" or responsable == "" -> {:error, :campo_vacio}
      tipo == :error -> {:error, :tipo_invalido}
      cantidad == :error -> {:error, :cantidad_invalida}
      cantidad < 0 -> {:error, :cantidad_negativa}
      cantidad == 0 -> {:error, :cantidad_invalida}
      prioridad == :error -> {:error, :prioridad_invalida}
      true -> crear_necesidad(necesidades, tipo, cantidad, prioridad, zona, descripcion, responsable)
    end
  end

  defp crear_necesidad(necesidades, tipo, cantidad, prioridad, zona, descripcion, responsable) do
    necesidad = %Necesidad{
      id: siguiente_id(necesidades),
      tipo: tipo,
      cantidad: cantidad,
      prioridad: prioridad,
      zona: zona,
      descripcion: descripcion,
      responsable: responsable
    }

    {:ok, necesidad, necesidades ++ [necesidad]}
  end

  @doc """
  Cambia el estado de una necesidad respetando las transiciones válidas.
  Una necesidad atendida o cancelada no se puede cerrar de nuevo ni reabrir.
  El estado asignada solo se alcanza con asignar_recurso/5.
  Retorna {:ok, necesidad, necesidades} o {:error, motivo}.
  """
  def cambiar_estado(necesidades, id, nuevo_estado) do
    case buscar_por_id(necesidades, id) do
      {:ok, necesidad} -> aplicar_estado(necesidades, necesidad, convertir(nuevo_estado, @estados))
      {:error, motivo} -> {:error, motivo}
    end
  end

  defp aplicar_estado(_necesidades, _necesidad, :error), do: {:error, :estado_invalido}

  defp aplicar_estado(_necesidades, %Necesidad{estado: actual}, _nuevo) when actual in [:atendida, :cancelada],
    do: {:error, :necesidad_cerrada}

  defp aplicar_estado(_necesidades, %Necesidad{estado: estado}, estado), do: {:error, :mismo_estado}
  defp aplicar_estado(_necesidades, _necesidad, :asignada), do: {:error, :usar_asignar_recurso}

  defp aplicar_estado(necesidades, necesidad, nuevo) do
    if nuevo in Map.fetch!(@transiciones, necesidad.estado) do
      actualizada = %{necesidad | estado: nuevo}
      {:ok, actualizada, reemplazar(necesidades, actualizada)}
    else
      {:error, :transicion_invalida}
    end
  end

  @doc """
  Busca una necesidad por su ID.
  Retorna {:ok, necesidad} o {:error, :necesidad_no_encontrada}.
  """
  def buscar_por_id(necesidades, id) do
    buscado = normalizar(id)

    case Enum.find(necesidades, fn necesidad -> normalizar(necesidad.id) == buscado end) do
      nil -> {:error, :necesidad_no_encontrada}
      necesidad -> {:ok, necesidad}
    end
  end

  @doc """
  Convierte un texto (por ejemplo "primeros auxilios") en un tipo de necesidad.
  Retorna el átomo o :error.
  """
  def convertir_tipo(valor), do: convertir(valor, @tipos)

  @doc """
  Convierte un texto (por ejemplo "crítica" o "critica") en una prioridad.
  Retorna el átomo o :error.
  """
  def convertir_prioridad(valor), do: convertir(valor, @prioridades)

  @doc """
  Convierte un texto (por ejemplo "en atención") en un estado de necesidad.
  Retorna el átomo o :error.
  """
  def convertir_estado(valor), do: convertir(valor, @estados)

  # ---------- Asignación de recursos ----------

  @doc """
  Asigna recursos del inventario a una necesidad.
  La clave puede ser el código, el nombre o la categoría del recurso.
  Valida que la necesidad esté abierta, que no se cubra más de lo requerido y que
  el inventario alcance; solo entonces descuenta del inventario y actualiza la
  necesidad. Si algo falla no se modifica ni el inventario ni la necesidad.
  Retorna {:ok, %{necesidad: ..., necesidades: ..., recursos: ..., usados: ...}}
  o {:error, motivo}.
  """
  def asignar_recurso(necesidades, recursos, id, clave, cantidad) do
    case buscar_por_id(necesidades, id) do
      {:ok, necesidad} -> asignar_a_necesidad(necesidades, recursos, necesidad, clave, cantidad)
      {:error, motivo} -> {:error, motivo}
    end
  end

  defp asignar_a_necesidad(necesidades, recursos, necesidad, clave, cantidad) do
    cantidad = convertir_entero(cantidad)

    cond do
      necesidad.estado in [:atendida, :cancelada] -> {:error, :necesidad_cerrada}
      necesidad.estado not in [:pendiente, :asignada] -> {:error, :necesidad_no_asignable}
      cantidad == :error -> {:error, :cantidad_invalida}
      cantidad < 0 -> {:error, :cantidad_negativa}
      cantidad == 0 -> {:error, :cantidad_invalida}
      cantidad > pendiente_de_cubrir(necesidad) -> {:error, :excede_requerido}
      true -> descontar_y_actualizar(necesidades, recursos, necesidad, clave, cantidad)
    end
  end

  defp descontar_y_actualizar(necesidades, recursos, necesidad, clave, cantidad) do
    case Recursos.asignar(recursos, clave, cantidad, "asignado a #{necesidad.id}") do
      {:ok, usados, recursos} ->
        codigos = Enum.map(usados, fn {codigo, _ubicacion, _cantidad} -> codigo end)

        actualizada = %{
          necesidad
          | asignado: necesidad.asignado + cantidad,
            recursos: Enum.uniq(necesidad.recursos ++ codigos),
            estado: :asignada
        }

        {:ok,
         %{
           necesidad: actualizada,
           necesidades: reemplazar(necesidades, actualizada),
           recursos: recursos,
           usados: usados
         }}

      {:error, motivo} ->
        {:error, motivo}
    end
  end

  @doc """
  Cantidad que todavía falta cubrir de una necesidad.
  """
  def pendiente_de_cubrir(necesidad), do: necesidad.cantidad - necesidad.asignado

  # ---------- Priorización y filtros recursivos ----------

  @doc """
  Peso numérico de una prioridad (crítica = 4, alta = 3, media = 2, baja = 1).
  """
  def peso_prioridad(:critica), do: 4
  def peso_prioridad(:alta), do: 3
  def peso_prioridad(:media), do: 2
  def peso_prioridad(:baja), do: 1

  @doc """
  Ordena las necesidades de mayor a menor prioridad con inserción recursiva.
  Es estable: a igual prioridad se conserva el orden de registro.
  """
  # Caso base: una lista vacía ya está ordenada
  def ordenar_por_prioridad([]), do: []

  # Caso recursivo: se ordena la cola y se inserta la cabeza en su lugar
  def ordenar_por_prioridad([cabeza | cola]) do
    insertar_por_prioridad(cabeza, ordenar_por_prioridad(cola))
  end

  # Caso base: la lista ordenada está vacía, la necesidad queda sola
  defp insertar_por_prioridad(necesidad, []), do: [necesidad]

  # Caso recursivo: se inserta antes de la primera con menor o igual prioridad
  defp insertar_por_prioridad(necesidad, [primera | resto] = ordenadas) do
    if peso_prioridad(necesidad.prioridad) >= peso_prioridad(primera.prioridad) do
      [necesidad | ordenadas]
    else
      [primera | insertar_por_prioridad(necesidad, resto)]
    end
  end

  @doc """
  Filtra necesidades por :zona, :tipo, :prioridad y :estado (todos los criterios
  dados deben cumplirse). Se conserva el orden original.
  Ejemplo: filtrar(necesidades, zona: "centro", prioridad: "critica")
  """
  # Caso base: no quedan necesidades por revisar
  def filtrar([], _criterios), do: []

  # Caso recursivo: si la cabeza cumple los criterios se conserva, y se sigue con el resto
  def filtrar([necesidad | resto], criterios) do
    if cumple_criterios?(necesidad, criterios) do
      [necesidad | filtrar(resto, criterios)]
    else
      filtrar(resto, criterios)
    end
  end

  @doc """
  Retorna las necesidades pendientes, ordenadas por prioridad.
  """
  def pendientes(necesidades) do
    necesidades
    |> filtrar(estado: :pendiente)
    |> ordenar_por_prioridad()
  end

  @doc """
  Selecciona la siguiente necesidad a atender: la pendiente de mayor prioridad.
  Retorna {:ok, necesidad} o {:error, :sin_pendientes}.
  """
  def siguiente(necesidades) do
    case pendientes(necesidades) do
      [] -> {:error, :sin_pendientes}
      [primera | _resto] -> {:ok, primera}
    end
  end

  @doc """
  Cuenta las necesidades por estado. Retorna un mapa %{estado => cantidad}.
  """
  def contar_por_estado(necesidades), do: contar_por_estado(necesidades, %{})

  # Caso base: se entrega el acumulador
  defp contar_por_estado([], acumulador), do: acumulador

  # Caso recursivo: se suma la cabeza al acumulador y se sigue con el resto
  defp contar_por_estado([necesidad | resto], acumulador) do
    contar_por_estado(resto, Map.update(acumulador, necesidad.estado, 1, fn cantidad -> cantidad + 1 end))
  end

  # Caso base: no quedan criterios por evaluar
  defp cumple_criterios?(_necesidad, []), do: true

  # Caso recursivo: se evalúa el primer criterio y luego los demás
  defp cumple_criterios?(necesidad, [{campo, valor} | resto]) do
    cumple_criterio?(necesidad, campo, valor) and cumple_criterios?(necesidad, resto)
  end

  defp cumple_criterio?(necesidad, :zona, valor), do: normalizar(necesidad.zona) == normalizar(valor)
  defp cumple_criterio?(necesidad, :tipo, valor), do: necesidad.tipo == convertir(valor, @tipos)
  defp cumple_criterio?(necesidad, :prioridad, valor), do: necesidad.prioridad == convertir(valor, @prioridades)
  defp cumple_criterio?(necesidad, :estado, valor), do: necesidad.estado == convertir(valor, @estados)

  # Un criterio desconocido no se cumple
  defp cumple_criterio?(_necesidad, _campo, _valor), do: false

  # ---------- Texto para mostrar (se imprime con Util.mostrar_mensaje) ----------

  @doc """
  Arma el texto de una necesidad para mostrarla en consola.
  """
  def texto_necesidad(necesidad) do
    "#{necesidad.id} | #{texto(necesidad.tipo)} | Cantidad: #{necesidad.cantidad} | " <>
      "Prioridad: #{texto(necesidad.prioridad)} | Zona: #{necesidad.zona} | " <>
      "Estado: #{texto(necesidad.estado)} | Asignado: #{necesidad.asignado} | #{necesidad.descripcion}"
  end

  @doc """
  Traduce el motivo de un error a un mensaje para el usuario.
  """
  def mensaje_error(:campo_vacio), do: "Hay campos obligatorios vacíos"
  def mensaje_error(:tipo_invalido), do: "Tipo inválido (agua, alimentos, medicamentos, primeros auxilios, refugio, transporte, rescate, otra)"
  def mensaje_error(:prioridad_invalida), do: "Prioridad inválida (crítica, alta, media, baja)"
  def mensaje_error(:estado_invalido), do: "Estado inválido (pendiente, asignada, en atención, atendida, cancelada)"
  def mensaje_error(:cantidad_invalida), do: "La cantidad debe ser un número entero mayor que cero"
  def mensaje_error(:cantidad_negativa), do: "La cantidad no puede ser negativa"
  def mensaje_error(:necesidad_no_encontrada), do: "Necesidad no encontrada"
  def mensaje_error(:necesidad_cerrada), do: "La necesidad ya está atendida o cancelada"
  def mensaje_error(:necesidad_no_asignable), do: "Solo se asignan recursos a necesidades pendientes o asignadas"
  def mensaje_error(:excede_requerido), do: "La cantidad supera lo que falta por cubrir en la necesidad"
  def mensaje_error(:usar_asignar_recurso), do: "El estado asignada solo se alcanza asignando un recurso"
  def mensaje_error(:transicion_invalida), do: "No se puede pasar a ese estado desde el estado actual"
  def mensaje_error(:mismo_estado), do: "La necesidad ya se encuentra en ese estado"
  def mensaje_error(:sin_pendientes), do: "No hay necesidades pendientes"
  def mensaje_error(:linea_invalida), do: "Línea de archivo inválida"
  def mensaje_error(otro), do: Recursos.mensaje_error(otro)

  # ---------- Persistencia (texto plano, campos separados por |) ----------

  @doc """
  Convierte una necesidad en una línea:
  N|id|tipo|cantidad|prioridad|zona|descripcion|recursos|estado|asignado|responsable
  Los códigos de recursos van separados por coma.
  """
  def a_linea(necesidad) do
    [
      "N",
      necesidad.id,
      texto(necesidad.tipo),
      necesidad.cantidad,
      texto(necesidad.prioridad),
      necesidad.zona,
      necesidad.descripcion,
      Enum.join(necesidad.recursos, ","),
      texto(necesidad.estado),
      necesidad.asignado,
      necesidad.responsable
    ]
    |> Enum.join("|")
  end

  @doc """
  Convierte una línea en una necesidad (acepta líneas antiguas sin responsable).
  Retorna {:ok, necesidad} o {:error, :linea_invalida}.
  """
  def desde_linea(linea) do
    case linea |> String.trim() |> String.split("|") do
      ["N", id, tipo, cantidad, prioridad, zona, descripcion, recursos, estado, asignado | resto]
      when length(resto) <= 1 ->
        tipo = convertir(tipo, @tipos)
        cantidad = convertir_entero(cantidad)
        prioridad = convertir(prioridad, @prioridades)
        estado = convertir(estado, @estados)
        asignado = convertir_entero(asignado)

        if :error in [tipo, cantidad, prioridad, estado, asignado] do
          {:error, :linea_invalida}
        else
          {:ok,
           %Necesidad{
             id: id,
             tipo: tipo,
             cantidad: cantidad,
             prioridad: prioridad,
             zona: zona,
             descripcion: descripcion,
             responsable: List.first(resto, ""),
             estado: estado,
             recursos: String.split(recursos, ",", trim: true),
             asignado: asignado
           }}
        end

      _ ->
        {:error, :linea_invalida}
    end
  end

  @doc """
  Convierte las líneas de un archivo en necesidades, ignorando las líneas inválidas.
  """
  def desde_lineas(lineas) do
    lineas
    |> Enum.map(&desde_linea/1)
    |> Enum.filter(fn {estado, _} -> estado == :ok end)
    |> Enum.map(fn {_estado, necesidad} -> necesidad end)
  end

  @doc """
  Convierte las necesidades en líneas de texto para guardarlas en el archivo.
  """
  def a_lineas(necesidades), do: Enum.map(necesidades, &a_linea/1)

  # ---------- Funciones privadas ----------

  # Convierte un texto en un átomo del catálogo (acepta tildes, mayúsculas y espacios)
  defp convertir(valor, catalogo) when is_binary(valor) do
    clave = valor |> normalizar() |> String.replace([" ", "-"], "_")

    case Enum.find(catalogo, fn atomo -> Atom.to_string(atomo) == clave end) do
      nil -> :error
      atomo -> atomo
    end
  end

  defp convertir(valor, catalogo) do
    if valor in catalogo, do: valor, else: :error
  end

  # Texto legible de un átomo (primeros_auxilios -> "primeros auxilios")
  defp texto(:critica), do: "crítica"
  defp texto(:en_atencion), do: "en atención"
  defp texto(atomo), do: atomo |> Atom.to_string() |> String.replace("_", " ")

  # Retorna un entero o :error si el texto no es un entero completo
  defp convertir_entero(valor) when is_integer(valor), do: valor

  defp convertir_entero(texto) when is_binary(texto) do
    case Integer.parse(String.trim(texto)) do
      {numero, ""} -> numero
      _ -> :error
    end
  end

  defp convertir_entero(_otro), do: :error

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

  # ID en orden: N001, N002... (los ID con otro formato no se tienen en cuenta)
  defp siguiente_id(necesidades) do
    mayor =
      Enum.reduce(necesidades, 0, fn necesidad, acumulado ->
        case Emergencia.Util.numero_id(necesidad.id, "N") do
          0 -> acumulado
          numero -> max(acumulado, numero)
        end
      end)

    "N" <> String.pad_leading(Integer.to_string(mayor + 1), 3, "0")
  end

  # Reemplaza la necesidad con el mismo id (recursivo)
  defp reemplazar([], _nueva), do: []
  defp reemplazar([%{id: id} | resto], %{id: id} = nueva), do: [nueva | resto]
  defp reemplazar([otra | resto], nueva), do: [otra | reemplazar(resto, nueva)]
end
