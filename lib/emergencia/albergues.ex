defmodule Emergencia.Albergues.Albergue do
  @moduledoc """
  Representa un albergue temporal y las personas que lo ocupan.
  Formato de la línea: A|codigo|nombre|zona|capacidad|ocupados|documentos
  Los documentos de los ocupantes van separados por coma.
  -version 1.0
  -autor: equipo Programación III
  -fecha: 2026-11-15
  """

  defstruct codigo: "",
            nombre: "",
            zona: "",
            capacidad: 0,
            ocupantes: []
end

defmodule Emergencia.Albergues do
  @moduledoc """
  Se encarga únicamente de los albergues: capacidad, ocupación,
  ingresos/salidas de ocupantes y reportes.
  No imprime ni crea procesos: recibe la lista actual y retorna la lista nueva.
  Regla de negocio: nunca se supera la capacidad máxima del albergue.
  -version 1.0
  -autor: equipo Programación III
  -fecha: 2026-11-15
  """

  alias Emergencia.Albergues.Albergue

  # ---------- Registro y consulta ----------

  @doc """
  Registra un albergue. El código no puede repetirse y la capacidad debe ser
  un entero mayor que cero. El albergue nace sin ocupantes.
  Retorna {:ok, albergue, albergues} o {:error, motivo}.
  """
  def registrar(albergues, codigo, nombre, zona, capacidad) do
    codigo = codigo |> limpiar() |> String.upcase()
    nombre = limpiar(nombre)
    zona = limpiar(zona)
    capacidad = convertir_entero(capacidad)

    cond do
      codigo == "" or nombre == "" or zona == "" -> {:error, :campo_vacio}
      capacidad == :error -> {:error, :capacidad_invalida}
      capacidad < 0 -> {:error, :capacidad_negativa}
      capacidad == 0 -> {:error, :capacidad_invalida}
      existe?(albergues, codigo) -> {:error, :albergue_duplicado}
      true -> crear_albergue(albergues, codigo, nombre, zona, capacidad)
    end
  end

  defp crear_albergue(albergues, codigo, nombre, zona, capacidad) do
    albergue = %Albergue{codigo: codigo, nombre: nombre, zona: zona, capacidad: capacidad}
    {:ok, albergue, albergues ++ [albergue]}
  end

  @doc """
  Busca un albergue por su código.
  Retorna {:ok, albergue} o {:error, :albergue_no_encontrado}.
  """
  def buscar(albergues, codigo) do
    buscado = normalizar(codigo)

    case Enum.find(albergues, fn albergue -> normalizar(albergue.codigo) == buscado end) do
      nil -> {:error, :albergue_no_encontrado}
      albergue -> {:ok, albergue}
    end
  end

  @doc """
  Indica si un documento ya está registrado como ocupante del albergue.
  """
  def ocupante?(%Albergue{ocupantes: ocupantes}, documento) do
    buscado = normalizar(documento)
    Enum.any?(ocupantes, fn ocupante -> normalizar(ocupante) == buscado end)
  end

  # ---------- Ingresos y salidas ----------

  @doc """
  Registra el ingreso de una persona (por documento) a un albergue.
  No se permite repetir el mismo documento dentro del albergue ni superar
  la capacidad máxima.
  Retorna {:ok, albergue, albergues} o {:error, motivo}.
  """
  def registrar_entrada(albergues, codigo, documento) do
    documento = limpiar(documento)

    cond do
      documento == "" ->
        {:error, :campo_vacio}

      true ->
        case buscar(albergues, codigo) do
          {:ok, albergue} -> ingresar(albergues, albergue, documento)
          {:error, motivo} -> {:error, motivo}
        end
    end
  end

  defp ingresar(albergues, albergue, documento) do
    cond do
      ocupante?(albergue, documento) -> {:error, :ocupante_duplicado}
      cupos_disponibles(albergue) <= 0 -> {:error, :capacidad_excedida}
      true ->
        actualizado = %{albergue | ocupantes: albergue.ocupantes ++ [documento]}
        {:ok, actualizado, reemplazar(albergues, actualizado)}
    end
  end

  @doc """
  Registra la salida de una persona de un albergue.
  Retorna {:ok, albergue, albergues} o {:error, motivo}.
  """
  def registrar_salida(albergues, codigo, documento) do
    documento = limpiar(documento)

    cond do
      documento == "" ->
        {:error, :campo_vacio}

      true ->
        case buscar(albergues, codigo) do
          {:ok, albergue} -> retirar(albergues, albergue, documento)
          {:error, motivo} -> {:error, motivo}
        end
    end
  end

  defp retirar(albergues, albergue, documento) do
    if ocupante?(albergue, documento) do
      buscado = normalizar(documento)
      ocupantes = Enum.reject(albergue.ocupantes, fn o -> normalizar(o) == buscado end)
      actualizado = %{albergue | ocupantes: ocupantes}
      {:ok, actualizado, reemplazar(albergues, actualizado)}
    else
      {:error, :ocupante_no_encontrado}
    end
  end

  # ---------- Lógica recursiva de cupos ----------

  @doc """
  Calcula recursivamente el porcentaje de ocupación de una lista de albergues
  (o de un solo albergue). Retorna un float entre 0.0 y 100.0.
  """
  def porcentaje_ocupacion(albergues) do
    %{capacidad: capacidad, ocupacion: ocupacion} = totales(albergues)

    if capacidad == 0 do
      0.0
    else
      Float.round(ocupacion / capacidad * 100, 2)
    end
  end

  @doc """
  Suma recursivamente capacidad y ocupación de la lista de albergues.
  Se llama con los acumuladores en cero: totales(albergues, 0, 0)
  Retorna {capacidad_total, ocupacion_total}.
  """
  # Caso base: no quedan albergues, se entregan los acumuladores
  def totales([], capacidad, ocupacion), do: {capacidad, ocupacion}

  # Caso recursivo: se suma la cabeza y se sigue con el resto
  def totales([%Albergue{} = albergue | resto], capacidad, ocupacion) do
    totales(resto, capacidad + albergue.capacidad, ocupacion + contar_ocupantes(albergue))
  end

  @doc """
  Versión de conveniencia de totales/3 que acepta una lista o un albergue y
  retorna un mapa con capacidad, ocupación y cupos disponibles.
  """
  def totales(%Albergue{} = albergue) do
    {capacidad, ocupacion} = totales([albergue], 0, 0)
    resumen_totales(capacidad, ocupacion)
  end

  def totales(albergues) when is_list(albergues) do
    {capacidad, ocupacion} = totales(albergues, 0, 0)
    resumen_totales(capacidad, ocupacion)
  end

  defp resumen_totales(capacidad, ocupacion) do
    %{capacidad: capacidad, ocupacion: ocupacion, disponibles: max(capacidad - ocupacion, 0)}
  end

  @doc """
  Calcula recursivamente los cupos disponibles de una lista de albergues
  (o de un solo albergue).
  """
  # Caso base: no quedan albergues
  def cupos_disponibles([]), do: 0

  # Caso recursivo: cupos de la cabeza más cupos del resto
  def cupos_disponibles([%Albergue{} = albergue | resto]) do
    cupos_disponibles(albergue) + cupos_disponibles(resto)
  end

  def cupos_disponibles(%Albergue{} = albergue) do
    max(albergue.capacidad - contar_ocupantes(albergue), 0)
  end

  @doc """
  Cuenta recursivamente el total de ocupantes registrados en una lista de
  albergues (o en un solo albergue).
  """
  # Caso base: no quedan albergues
  def contar_ocupantes([]), do: 0

  # Caso recursivo: ocupantes de la cabeza más ocupantes del resto
  def contar_ocupantes([%Albergue{} = albergue | resto]) do
    contar_ocupantes(albergue) + contar_ocupantes(resto)
  end

  def contar_ocupantes(%Albergue{ocupantes: ocupantes}), do: contar_lista(ocupantes)

  # Caso base: no quedan ocupantes
  defp contar_lista([]), do: 0

  # Caso recursivo: uno más los ocupantes del resto
  defp contar_lista([_ | resto]), do: 1 + contar_lista(resto)

  # ---------- Reportes ----------

  @doc """
  Genera un reporte general con totales, porcentaje y el detalle de cada albergue.
  """
  def reporte(albergues) when is_list(albergues) do
    total = totales(albergues)

    %{
      total_albergues: length(albergues),
      capacidad: total.capacidad,
      ocupacion: total.ocupacion,
      disponibles: total.disponibles,
      porcentaje: porcentaje_ocupacion(albergues),
      detalle: Enum.map(albergues, &texto_albergue/1)
    }
  end

  @doc """
  Arma el texto de un albergue para mostrarlo en consola.
  """
  def texto_albergue(%Albergue{} = albergue) do
    "#{albergue.codigo} | #{albergue.nombre} | Zona: #{albergue.zona} | " <>
      "Capacidad: #{albergue.capacidad} | Ocupantes: #{contar_ocupantes(albergue)} | " <>
      "Cupos: #{cupos_disponibles(albergue)}"
  end

  @doc """
  Traduce el motivo de un error a un mensaje para el usuario.
  """
  def mensaje_error(:campo_vacio), do: "Hay campos obligatorios vacíos"
  def mensaje_error(:capacidad_invalida), do: "La capacidad debe ser un número entero mayor que cero"
  def mensaje_error(:capacidad_negativa), do: "La capacidad no puede ser negativa"
  def mensaje_error(:albergue_duplicado), do: "Ya existe un albergue con ese código"
  def mensaje_error(:albergue_no_encontrado), do: "Albergue no encontrado"
  def mensaje_error(:ocupante_duplicado), do: "Esa persona ya está registrada en el albergue"
  def mensaje_error(:capacidad_excedida), do: "El albergue no tiene cupos disponibles"
  def mensaje_error(:ocupante_no_encontrado), do: "La persona no está registrada en el albergue"
  def mensaje_error(:linea_invalida), do: "Línea de archivo inválida"
  def mensaje_error(otro), do: "Error: #{inspect(otro)}"

  # ---------- Persistencia (texto plano, campos separados por |) ----------

  @doc """
  Convierte un albergue en una línea:
  A|codigo|nombre|zona|capacidad|ocupados|documentos
  """
  def a_linea(%Albergue{} = albergue) do
    [
      "A",
      albergue.codigo,
      albergue.nombre,
      albergue.zona,
      albergue.capacidad,
      contar_ocupantes(albergue),
      Enum.join(albergue.ocupantes, ",")
    ]
    |> Enum.join("|")
  end

  @doc """
  Convierte una línea en un albergue. Acepta el formato de 7 campos que usa
  data/shelters.txt y un formato corto de 6 campos.
  Retorna {:ok, albergue} o {:error, :linea_invalida}.
  """
  def desde_linea(linea) do
    case linea |> String.trim() |> String.split("|") do
      ["A", codigo, nombre, zona, capacidad, _ocupados, documentos] ->
        construir(codigo, nombre, zona, capacidad, documentos)

      ["A", codigo, nombre, zona, capacidad, documentos] ->
        construir(codigo, nombre, zona, capacidad, documentos)

      _ ->
        {:error, :linea_invalida}
    end
  end

  defp construir(codigo, nombre, zona, capacidad, documentos) do
    capacidad = convertir_entero(capacidad)

    if capacidad == :error or capacidad < 0 do
      {:error, :linea_invalida}
    else
      ocupantes =
        documentos
        |> String.split(",", trim: true)
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))

      {:ok,
       %Albergue{
         codigo: codigo,
         nombre: nombre,
         zona: zona,
         capacidad: capacidad,
         ocupantes: ocupantes
       }}
    end
  end

  @doc """
  Convierte las líneas de un archivo en albergues, ignorando las inválidas.
  """
  def desde_lineas(lineas) do
    lineas
    |> Enum.map(&desde_linea/1)
    |> Enum.filter(fn {estado, _} -> estado == :ok end)
    |> Enum.map(fn {_estado, albergue} -> albergue end)
  end

  @doc """
  Convierte los albergues en líneas de texto para guardarlos en el archivo.
  """
  def a_lineas(albergues), do: Enum.map(albergues, &a_linea/1)

  # ---------- Funciones privadas ----------

  defp existe?(albergues, codigo) do
    buscado = normalizar(codigo)
    Enum.any?(albergues, fn albergue -> normalizar(albergue.codigo) == buscado end)
  end

  # Reemplaza el albergue con el mismo código (recursivo)
  defp reemplazar([], _nuevo), do: []
  defp reemplazar([%{codigo: codigo} | resto], %{codigo: codigo} = nuevo), do: [nuevo | resto]
  defp reemplazar([otro | resto], nuevo), do: [otro | reemplazar(resto, nuevo)]

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
end
