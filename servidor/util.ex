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
end
