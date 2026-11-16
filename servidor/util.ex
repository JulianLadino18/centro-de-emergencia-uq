defmodule Emergencia.Util do
  @moduledoc """
  Utilidades compartidas del servidor: generación de IDs,
  formateo de fecha/hora, conversión de tipos y validaciones básicas.
  """

  @doc """
  Genera un ID único basado en timestamp y número aleatorio.
  """
  def id(prefix) do
    ts = :os.system_time(:micro_seconds)
    rand = :rand.uniform(999_999)
    "#{prefix}_#{ts}_#{rand}"
  end

  @doc """
  Devuelve la hora actual formateada como HH:MM:SS.
  """
  def ahora do
    {hh, mm, ss} = :erlang.time()
    "#{pad(hh)}:#{pad(mm)}:#{pad(ss)}"
  end

  @doc """
  Devuelve fecha y hora completa.
  """
  def fecha_hora do
    {{anio, mes, dia}, {hora, minuto, segundo}} = :calendar.local_time()
    "#{anio}-#{pad(mes)}-#{pad(dia)} #{pad(hora)}:#{pad(minuto)}:#{pad(segundo)}"
  end

  defp pad(n), do: n |> Integer.to_string() |> String.pad_leading(2, "0")

  @doc """
  Convierte a entero si es posible.
  """
  def a_entero(v) when is_integer(v), do: {:ok, v}

  def a_entero(v) when is_binary(v) do
    case Integer.parse(v) do
      {n, ""} -> {:ok, n}
      _ -> {:error, :invalido}
    end
  end

  def a_entero(_), do: {:error, :invalido}

  @doc """
  Valida que un número sea no negativo.
  """
  def no_negativo(v) when v >= 0, do: {:ok, v}
  def no_negativo(_), do: {:error, :negativo}

  @doc """
  Verifica si una cadena está vacía.
  """
  def vacio?(nil), do: true
  def vacio?(""), do: true
  def vacio?(_), do: false

  @doc """
  Quita las tildes de un texto que ya viene normalizado a NFD.
  Se hace con recursión y sin expresiones regulares para que el proyecto
  compile igual en cualquier versión de Erlang/OTP.
  """
  def sin_tildes(texto) when is_binary(texto) do
    texto
    |> String.to_charlist()
    |> quitar_marcas([])
    |> List.to_string()
  end

  def sin_tildes(_otro), do: ""

  # Las marcas diacríticas combinantes están entre U+0300 y U+036F
  defp quitar_marcas([], acumulado), do: Enum.reverse(acumulado)

  defp quitar_marcas([marca | resto], acumulado) when marca >= 0x0300 and marca <= 0x036F,
    do: quitar_marcas(resto, acumulado)

  defp quitar_marcas([caracter | resto], acumulado),
    do: quitar_marcas(resto, [caracter | acumulado])

  @doc """
  Divide un texto en palabras separando por cualquier carácter que no sea
  letra o dígito (recursivo, sin expresiones regulares).
  """
  def palabras(texto) when is_binary(texto) do
    texto
    |> String.to_charlist()
    |> separar_palabras([], [])
  end

  def palabras(_otro), do: []

  defp separar_palabras([], actual, palabras) do
    if actual == [] do
      Enum.reverse(palabras)
    else
      Enum.reverse([palabra(actual) | palabras])
    end
  end

  defp separar_palabras([caracter | resto], actual, palabras) do
    if alfanumerico?(caracter) do
      separar_palabras(resto, [caracter | actual], palabras)
    else
      if actual == [] do
        separar_palabras(resto, [], palabras)
      else
        separar_palabras(resto, [], [palabra(actual) | palabras])
      end
    end
  end

  # Las letras se van acumulando al revés para no recorrer la lista dos veces
  defp palabra(caracteres), do: caracteres |> Enum.reverse() |> List.to_string()

  defp alfanumerico?(caracter) when caracter >= ?0 and caracter <= ?9, do: true
  defp alfanumerico?(caracter) when caracter >= ?a and caracter <= ?z, do: true
  defp alfanumerico?(caracter) when caracter >= ?A and caracter <= ?Z, do: true
  defp alfanumerico?(caracter) when caracter >= 0x00C0, do: true
  defp alfanumerico?(_caracter), do: false

  @doc """
  Extrae el número final de un ID con prefijo ("P012" con prefijo "P" da 12).
  Retorna 0 cuando el ID no tiene el formato prefijo + número.
  """
  def numero_id(id, prefijo) when is_binary(id) and is_binary(prefijo) do
    if String.starts_with?(id, prefijo) do
      resto = String.replace_prefix(id, prefijo, "")

      case Integer.parse(resto) do
        {numero, ""} when numero > 0 -> numero
        _ -> 0
      end
    else
      0
    end
  end

  def numero_id(_id, _prefijo), do: 0

  @doc """
  Verifica que un texto sea un hash SHA-256 en hexadecimal (64 caracteres 0-9a-f).
  """
  def hex_valido?(texto) when is_binary(texto) do
    String.length(texto) == 64 and caracteres_hex?(String.to_charlist(texto))
  end

  def hex_valido?(_otro), do: false

  defp caracteres_hex?([]), do: true
  defp caracteres_hex?([caracter | resto]) when caracter >= ?0 and caracter <= ?9,
    do: caracteres_hex?(resto)

  defp caracteres_hex?([caracter | resto]) when caracter >= ?a and caracter <= ?f,
    do: caracteres_hex?(resto)

  defp caracteres_hex?(_otros), do: false
end
