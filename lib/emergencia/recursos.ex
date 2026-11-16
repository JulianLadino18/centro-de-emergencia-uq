defmodule Emergencia.Recursos.Recurso do
  @moduledoc """
  Representa la existencia de un recurso en un centro de apoyo.
  Un mismo código puede estar en varios centros (por ejemplo después de una
  transferencia); lo que lo identifica es la pareja {codigo, ubicacion}.
  El historial guarda tuplas {fecha, tipo, cantidad, detalle}.
  Formato de la línea: R|codigo|nombre|categoria|cantidad|unidad|ubicacion|historial
  -version 1.0
  -autor: Daniel Gil
  -fecha: 2026-11-14
  """

  defstruct codigo: "",
            nombre: "",
            categoria: "",
            cantidad: 0,
            unidad: "",
            ubicacion: "",
            historial: []
end

defmodule Emergencia.Recursos do
  @moduledoc """
  Se encarga únicamente del inventario: registro, entradas, salidas,
  transferencias, asignación y consultas.
  No imprime ni crea procesos: recibe la lista de recursos y retorna la lista nueva.
  Cada operación valida y descuenta en un solo paso, y el GenServer atiende un
  mensaje a la vez, así que lo asignado nunca supera el inventario disponible.
  Si una operación falla no modifica nada.
  -version 1.0
  -autor: Daniel Gil
  -fecha: 2026-11-14
  """

  alias Emergencia.Recursos.Recurso

  @tipos [:registro, :entrada, :salida, :asignacion, :transferencia_salida, :transferencia_entrada]

  # ---------- Registro y consulta de un recurso ----------

  @doc """
  Registra un recurso en un centro. La pareja {codigo, ubicacion} no puede repetirse
  y un código que ya existe debe conservar su nombre, categoría y unidad.
  La cantidad inicial no puede ser negativa.
  Retorna {:ok, recurso, recursos} o {:error, motivo}.
  """
  def registrar(recursos, codigo, nombre, categoria, cantidad, unidad, ubicacion) do
    codigo = codigo |> limpiar() |> String.upcase()
    nombre = limpiar(nombre)
    categoria = limpiar(categoria)
    unidad = limpiar(unidad)
    ubicacion = limpiar(ubicacion)
    cantidad = convertir_entero(cantidad)

    cond do
      codigo == "" or nombre == "" or categoria == "" or unidad == "" or ubicacion == "" ->
        {:error, :campo_vacio}

      cantidad == :error -> {:error, :cantidad_invalida}
      cantidad < 0 -> {:error, :cantidad_negativa}
      existe?(recursos, codigo, ubicacion) -> {:error, :recurso_duplicado}
      datos_distintos?(recursos, codigo, nombre, categoria, unidad) -> {:error, :datos_distintos}
      true -> crear_recurso(recursos, codigo, nombre, categoria, cantidad, unidad, ubicacion)
    end
  end

  defp crear_recurso(recursos, codigo, nombre, categoria, cantidad, unidad, ubicacion) do
    recurso = %Recurso{
      codigo: codigo,
      nombre: nombre,
      categoria: categoria,
      cantidad: cantidad,
      unidad: unidad,
      ubicacion: ubicacion,
      historial: [{fecha(), :registro, cantidad, "registro inicial"}]
    }

    {:ok, recurso, recursos ++ [recurso]}
  end

  @doc """
  Busca el recurso de un código en un centro.
  Retorna {:ok, recurso} o {:error, :recurso_no_encontrado}.
  """
  def buscar(recursos, codigo, ubicacion) do
    case Enum.find(recursos, fn recurso -> misma_clave?(recurso, codigo, ubicacion) end) do
      nil -> {:error, :recurso_no_encontrado}
      recurso -> {:ok, recurso}
    end
  end

  # ---------- Entradas, salidas y transferencias ----------

  @doc """
  Registra una entrada de inventario. La cantidad debe ser mayor que cero.
  Retorna {:ok, recurso, recursos} o {:error, motivo}.
  """
  def entrada(recursos, codigo, ubicacion, cantidad, detalle \\ "entrada") do
    case validar_cantidad(cantidad) do
      {:ok, cantidad} ->
        actualizar(recursos, codigo, ubicacion, fn recurso ->
          {:ok, mover(recurso, :entrada, cantidad, detalle)}
        end)

      {:error, motivo} ->
        {:error, motivo}
    end
  end

  @doc """
  Registra una salida de inventario. Si la cantidad supera lo disponible retorna
  {:error, {:stock_insuficiente, disponible}} y no cambia nada.
  """
  def salida(recursos, codigo, ubicacion, cantidad, detalle \\ "salida") do
    case validar_cantidad(cantidad) do
      {:ok, cantidad} ->
        actualizar(recursos, codigo, ubicacion, fn recurso ->
          descontar(recurso, :salida, cantidad, detalle)
        end)

      {:error, motivo} ->
        {:error, motivo}
    end
  end

  @doc """
  Transfiere recursos entre dos centros de apoyo. Si el destino todavía no tiene
  ese código, se crea con el mismo nombre, categoría y unidad.
  Retorna {:ok, {recurso_origen, recurso_destino}, recursos} o {:error, motivo}.
  """
  def transferir(recursos, codigo, origen, destino, cantidad) do
    case validar_cantidad(cantidad) do
      {:ok, cantidad} -> transferir_validada(recursos, codigo, origen, destino, cantidad)
      {:error, motivo} -> {:error, motivo}
    end
  end

  defp transferir_validada(recursos, codigo, origen, destino, cantidad) do
    if normalizar(origen) == normalizar(destino) do
      {:error, :mismo_centro}
    else
      resultado =
        actualizar(recursos, codigo, origen, fn recurso ->
          descontar(recurso, :transferencia_salida, cantidad, "hacia #{destino}")
        end)

      case resultado do
        {:ok, de_origen, recursos} -> recibir(recursos, de_origen, destino, cantidad)
        {:error, motivo} -> {:error, motivo}
      end
    end
  end

  # Suma lo transferido al destino; si el destino no tenía ese código, lo crea
  defp recibir(recursos, de_origen, destino, cantidad) do
    detalle = "desde #{de_origen.ubicacion}"

    case buscar(recursos, de_origen.codigo, destino) do
      {:ok, _existente} ->
        {:ok, en_destino, recursos} =
          actualizar(recursos, de_origen.codigo, destino, fn recurso ->
            {:ok, mover(recurso, :transferencia_entrada, cantidad, detalle)}
          end)

        {:ok, {de_origen, en_destino}, recursos}

      {:error, _motivo} ->
        en_destino = %{
          de_origen
          | cantidad: cantidad,
            ubicacion: String.trim(destino),
            historial: [{fecha(), :transferencia_entrada, cantidad, detalle}]
        }

        {:ok, {de_origen, en_destino}, recursos ++ [en_destino]}
    end
  end

  # ---------- Asignación a necesidades ----------

  @doc """
  Descuenta cantidad unidades del recurso identificado por clave (código, nombre o
  categoría), tomándolas recursivamente de uno o varios centros hasta cubrir lo pedido.
  Retorna {:ok, usados, recursos}, donde usados es una lista de {codigo, ubicacion, cantidad},
  o {:error, {:stock_insuficiente, disponible}} si no alcanza (sin cambiar nada).
  """
  def asignar(recursos, clave, cantidad, detalle \\ "asignación") do
    case validar_cantidad(cantidad) do
      {:ok, cantidad} -> asignar_validada(recursos, clave, cantidad, detalle)
      {:error, motivo} -> {:error, motivo}
    end
  end

  defp asignar_validada(recursos, clave, cantidad, detalle) do
    if Enum.any?(recursos, fn recurso -> coincide?(recurso, clave) end) do
      case tomar(recursos, clave, cantidad, detalle) do
        {nuevos, usados, 0} -> {:ok, usados, nuevos}
        {_nuevos, _usados, _faltante} -> {:error, {:stock_insuficiente, total_disponible(recursos, clave)}}
      end
    else
      {:error, :recurso_no_encontrado}
    end
  end

  # Retorna {lista_nueva, usados, faltante}. Se detiene cuando lo pedido llega a 0.
  # Caso base: ya se cubrió todo, el resto de la lista queda igual
  defp tomar(recursos, _clave, 0, _detalle), do: {recursos, [], 0}

  # Caso base: se acabó la lista y todavía falta cantidad
  defp tomar([], _clave, restante, _detalle), do: {[], [], restante}

  # Caso recursivo: se toma de la cabeza lo que se pueda y se sigue con el resto
  defp tomar([recurso | resto], clave, restante, detalle) do
    if coincide?(recurso, clave) and recurso.cantidad > 0 do
      tomado = min(recurso.cantidad, restante)
      actualizado = mover(recurso, :asignacion, -tomado, detalle)
      {resto_nuevo, usados, faltante} = tomar(resto, clave, restante - tomado, detalle)
      {[actualizado | resto_nuevo], [{recurso.codigo, recurso.ubicacion, tomado} | usados], faltante}
    else
      {resto_nuevo, usados, faltante} = tomar(resto, clave, restante, detalle)
      {[recurso | resto_nuevo], usados, faltante}
    end
  end

  # ---------- Consultas recursivas ----------

  @doc """
  Suma recursivamente la cantidad de una lista de recursos.
  Se llama con el acumulador en 0: suma_recursiva(recursos, 0)
  """
  # Caso base: no quedan recursos, se entrega el acumulador
  def suma_recursiva([], acumulador), do: acumulador

  # Caso recursivo: se suma la cantidad de la cabeza y se sigue con el resto
  def suma_recursiva([recurso | resto], acumulador) do
    suma_recursiva(resto, acumulador + recurso.cantidad)
  end

  @doc """
  Calcula recursivamente el total disponible de un recurso en todos los centros.
  La clave puede ser el código, el nombre o la categoría.
  """
  # Caso base: no quedan recursos
  def total_disponible([], _clave), do: 0

  # Caso recursivo: lo de la cabeza (si coincide) más el total del resto
  def total_disponible([recurso | resto], clave) do
    propio = if coincide?(recurso, clave), do: recurso.cantidad, else: 0
    propio + total_disponible(resto, clave)
  end

  @doc """
  Filtra el inventario por :categoria, :ubicacion, :codigo o :nombre
  (todos los criterios dados deben cumplirse).
  Ejemplo: consultar(recursos, categoria: "agua", ubicacion: "centro_acopio_1")
  """
  # Caso base: no quedan recursos
  def consultar([], _criterios), do: []

  # Caso recursivo: se conserva la cabeza si cumple los criterios
  def consultar([recurso | resto], criterios) do
    if cumple_criterios?(recurso, criterios) do
      [recurso | consultar(resto, criterios)]
    else
      consultar(resto, criterios)
    end
  end

  @doc """
  Retorna los recursos con existencias menores o iguales al umbral (por defecto 20).
  """
  def criticos(recursos, umbral \\ 20)

  # Caso base: no quedan recursos
  def criticos([], _umbral), do: []

  # Caso recursivo: se conserva la cabeza si está por debajo del umbral
  def criticos([recurso | resto], umbral) do
    if recurso.cantidad <= umbral do
      [recurso | criticos(resto, umbral)]
    else
      criticos(resto, umbral)
    end
  end

  @doc """
  Retorna el historial de movimientos de un recurso en un centro.
  """
  def historial(recursos, codigo, ubicacion) do
    case buscar(recursos, codigo, ubicacion) do
      {:ok, recurso} -> {:ok, recurso.historial}
      {:error, motivo} -> {:error, motivo}
    end
  end

  defp cumple_criterios?(_recurso, []), do: true

  defp cumple_criterios?(recurso, [{campo, valor} | resto]) do
    cumple_criterio?(recurso, campo, valor) and cumple_criterios?(recurso, resto)
  end

  defp cumple_criterio?(recurso, :categoria, valor), do: normalizar(recurso.categoria) == normalizar(valor)
  defp cumple_criterio?(recurso, :ubicacion, valor), do: normalizar(recurso.ubicacion) == normalizar(valor)
  defp cumple_criterio?(recurso, :codigo, valor), do: normalizar(recurso.codigo) == normalizar(valor)
  defp cumple_criterio?(recurso, :nombre, valor), do: normalizar(recurso.nombre) == normalizar(valor)

  # Un criterio desconocido no se cumple
  defp cumple_criterio?(_recurso, _campo, _valor), do: false

  # ---------- Texto para mostrar (se imprime con Util.mostrar_mensaje) ----------

  @doc """
  Arma el texto de un recurso para mostrarlo en consola.
  """
  def texto_recurso(recurso) do
    "#{recurso.codigo} | #{recurso.nombre} | Categoría: #{recurso.categoria} | " <>
      "Cantidad: #{recurso.cantidad} #{recurso.unidad} | Ubicación: #{recurso.ubicacion}"
  end

  @doc """
  Traduce el motivo de un error a un mensaje para el usuario.
  """
  def mensaje_error(:campo_vacio), do: "Hay campos obligatorios vacíos"
  def mensaje_error(:cantidad_invalida), do: "La cantidad debe ser un número entero mayor que cero"
  def mensaje_error(:cantidad_negativa), do: "La cantidad no puede ser negativa"
  def mensaje_error(:recurso_duplicado), do: "Ya existe ese recurso en ese centro"
  def mensaje_error(:datos_distintos), do: "Ese código ya existe con otro nombre, categoría o unidad"
  def mensaje_error(:recurso_no_encontrado), do: "Recurso no encontrado"
  def mensaje_error(:mismo_centro), do: "El origen y el destino deben ser centros distintos"
  def mensaje_error({:stock_insuficiente, disponible}), do: "Inventario insuficiente: solo hay #{disponible} disponibles"
  def mensaje_error(:linea_invalida), do: "Línea de archivo inválida"
  def mensaje_error(otro), do: "Error: #{inspect(otro)}"

  # ---------- Persistencia (texto plano, campos separados por |) ----------

  @doc """
  Convierte un recurso en una línea: R|codigo|nombre|categoria|cantidad|unidad|ubicacion|historial
  El historial se guarda como fecha~tipo~cantidad~detalle separado por ;
  """
  def a_linea(recurso) do
    historial =
      recurso.historial
      |> Enum.map(fn {fecha, tipo, cantidad, detalle} -> "#{fecha}~#{tipo}~#{cantidad}~#{detalle}" end)
      |> Enum.join(";")

    ["R", recurso.codigo, recurso.nombre, recurso.categoria, recurso.cantidad, recurso.unidad, recurso.ubicacion, historial]
    |> Enum.join("|")
  end

  @doc """
  Convierte una línea en un recurso (acepta un historial escrito como texto libre).
  Retorna {:ok, recurso} o {:error, :linea_invalida}.
  """
  def desde_linea(linea) do
    case linea |> String.trim() |> String.split("|") do
      ["R", codigo, nombre, categoria, cantidad, unidad, ubicacion | resto] when length(resto) <= 1 ->
        cantidad = convertir_entero(cantidad)

        if cantidad == :error or cantidad < 0 do
          {:error, :linea_invalida}
        else
          {:ok,
           %Recurso{
             codigo: codigo,
             nombre: nombre,
             categoria: categoria,
             cantidad: cantidad,
             unidad: unidad,
             ubicacion: ubicacion,
             historial: resto |> List.first("") |> convertir_historial()
           }}
        end

      _ ->
        {:error, :linea_invalida}
    end
  end

  @doc """
  Convierte las líneas de un archivo en recursos, ignorando las líneas inválidas.
  """
  def desde_lineas(lineas) do
    lineas
    |> Enum.map(&desde_linea/1)
    |> Enum.filter(fn {estado, _} -> estado == :ok end)
    |> Enum.map(fn {_estado, recurso} -> recurso end)
  end

  @doc """
  Convierte los recursos en líneas de texto para guardarlos en el archivo.
  """
  def a_lineas(recursos), do: Enum.map(recursos, &a_linea/1)

  # ---------- Funciones privadas ----------

  # Aplica fun al recurso {codigo, ubicacion} y reconstruye la lista (recursivo).
  # fun retorna {:ok, recurso_nuevo} o {:error, motivo}.
  defp actualizar([], _codigo, _ubicacion, _fun), do: {:error, :recurso_no_encontrado}

  defp actualizar([recurso | resto], codigo, ubicacion, fun) do
    if misma_clave?(recurso, codigo, ubicacion) do
      case fun.(recurso) do
        {:ok, nuevo} -> {:ok, nuevo, [nuevo | resto]}
        {:error, motivo} -> {:error, motivo}
      end
    else
      case actualizar(resto, codigo, ubicacion, fun) do
        {:ok, nuevo, resto_nuevo} -> {:ok, nuevo, [recurso | resto_nuevo]}
        {:error, motivo} -> {:error, motivo}
      end
    end
  end

  # No se puede sacar más de lo que hay
  defp descontar(recurso, tipo, cantidad, detalle) do
    if cantidad > recurso.cantidad do
      {:error, {:stock_insuficiente, recurso.cantidad}}
    else
      {:ok, mover(recurso, tipo, -cantidad, detalle)}
    end
  end

  # Aplica un movimiento (positivo entra, negativo sale) y lo anota en el historial
  defp mover(recurso, tipo, delta, detalle) do
    %{
      recurso
      | cantidad: recurso.cantidad + delta,
        historial: recurso.historial ++ [{fecha(), tipo, abs(delta), limpiar(detalle)}]
    }
  end

  defp existe?(recursos, codigo, ubicacion) do
    Enum.any?(recursos, fn recurso -> misma_clave?(recurso, codigo, ubicacion) end)
  end

  # Un código ya registrado en otro centro debe tener los mismos datos
  defp datos_distintos?(recursos, codigo, nombre, categoria, unidad) do
    Enum.any?(recursos, fn recurso ->
      normalizar(recurso.codigo) == normalizar(codigo) and
        {normalizar(recurso.nombre), normalizar(recurso.categoria), normalizar(recurso.unidad)} !=
          {normalizar(nombre), normalizar(categoria), normalizar(unidad)}
    end)
  end

  defp misma_clave?(recurso, codigo, ubicacion) do
    normalizar(recurso.codigo) == normalizar(codigo) and
      normalizar(recurso.ubicacion) == normalizar(ubicacion)
  end

  # La clave puede ser el código, el nombre o la categoría del recurso
  defp coincide?(recurso, clave) do
    buscado = normalizar(clave)
    buscado in [normalizar(recurso.codigo), normalizar(recurso.nombre), normalizar(recurso.categoria)]
  end

  # La cantidad de una entrada, salida, transferencia o asignación debe ser un entero mayor que cero
  defp validar_cantidad(valor) do
    cantidad = convertir_entero(valor)

    cond do
      cantidad == :error -> {:error, :cantidad_invalida}
      cantidad < 0 -> {:error, :cantidad_negativa}
      cantidad == 0 -> {:error, :cantidad_invalida}
      true -> {:ok, cantidad}
    end
  end

  # Retorna un entero o :error si el texto no es un entero completo
  defp convertir_entero(valor) when is_integer(valor), do: valor

  defp convertir_entero(texto) when is_binary(texto) do
    case Integer.parse(String.trim(texto)) do
      {numero, ""} -> numero
      _ -> :error
    end
  end

  defp convertir_entero(_otro), do: :error

  defp convertir_historial(""), do: []

  defp convertir_historial(texto) do
    texto
    |> String.split(";", trim: true)
    |> Enum.map(&convertir_movimiento/1)
  end

  # Si la entrada no tiene el formato nuevo (historial antiguo en texto libre), se conserva tal cual
  defp convertir_movimiento(entrada) do
    case String.split(entrada, "~", parts: 4) do
      [fecha, tipo, cantidad, detalle] ->
        tipo = Enum.find(@tipos, fn t -> Atom.to_string(t) == tipo end)
        cantidad = convertir_entero(cantidad)

        if tipo == nil or cantidad == :error do
          {"", :registro, 0, String.trim(entrada)}
        else
          {fecha, tipo, cantidad, detalle}
        end

      _ ->
        {"", :registro, 0, String.trim(entrada)}
    end
  end

  defp fecha, do: Emergencia.Util.fecha_hora()

  # Quita los separadores del archivo (| ; ~) y los saltos de línea
  defp limpiar(texto) when is_binary(texto) do
    texto
    |> String.replace(["|", ";", "~", "\r", "\n"], " ")
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
