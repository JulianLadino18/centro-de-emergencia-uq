defmodule Emergencia.Cliente.Util do
  @moduledoc """
  Utilidades del cliente: parseo de argumentos y formateo de salida.
  -version 1.0
  -autor: equipo Programación III
  -fecha: 2026-11-15
  """

  @doc """
  Separa los argumentos de línea de comandos en posicionales y filtros
  clave=valor.
  Retorna {posicionales, filtros}.
  """
  def separar_filtros(args) when is_list(args) do
    Enum.split_with(args, fn arg -> not String.contains?(arg, "=") end)
  end

  @doc """
  Normaliza prioridad escrita sin acento: "crítica" -> "critica".
  """
  def normalizar_prioridad(valor), do: normalizar(valor)

  @doc """
  Normaliza nivel de afectación escrito sin acento: "crítico" -> "critico".
  """
  def normalizar_nivel(valor), do: normalizar(valor)

  @doc """
  Normaliza tipo de mascota (lost/found -> perdida/encontrada).
  """
  def normalizar_tipo_mascota(valor) do
    case normalizar(valor) do
      "lost" -> "perdida"
      "perdido" -> "perdida"
      "found" -> "encontrada"
      "encontrado" -> "encontrada"
      otro -> otro
    end
  end

  @doc """
  Imprime un resultado {:ok, valor} o {:error, razon}.
  Los errores salen por stderr y terminan el proceso con código 1.
  """
  def imprimir_resultado({:ok, texto}) do
    IO.puts(texto)
    :ok
  end

  def imprimir_resultado({:ok, texto, _meta}) do
    IO.puts(texto)
    :ok
  end

  def imprimir_resultado({:error, texto}) do
    IO.puts(:stderr, "[error] " <> to_string(texto))
    System.halt(1)
  end

  # Minúsculas y sin tildes, sin expresiones regulares
  defp normalizar(valor) do
    valor
    |> to_string()
    |> String.trim()
    |> String.downcase()
    |> String.normalize(:nfd)
    |> String.to_charlist()
    |> Enum.reject(fn caracter -> caracter >= 0x0300 and caracter <= 0x036F end)
    |> List.to_string()
  end
end
