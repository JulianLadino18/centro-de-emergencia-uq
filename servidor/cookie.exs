defmodule Emergencia.Cookie do
  @moduledoc """
  Genera y gestiona la cookie de autenticación para nodos distribuidos.
  -version 1.0
  -autor: equipo Programación III
  -fecha: 2026-11-15
  """

  @doc """
  Genera una cookie aleatoria de 24 caracteres hexadecimales.
  """
  def generar do
    :crypto.strong_rand_bytes(12) |> Base.encode16(case: :lower)
  end

  @doc """
  Lee la cookie desde un archivo de texto.
  Retorna {:ok, cookie} o {:error, motivo}.
  """
  def leer(ruta) do
    case File.read(ruta) do
      {:ok, contenido} -> {:ok, String.trim(contenido)}
      {:error, razon} -> {:error, razon}
    end
  end

  @doc """
  Escribe la cookie en un archivo de texto (crea el directorio si hace falta).
  Retorna :ok o {:error, motivo}.
  """
  def guardar(ruta, cookie) do
    with :ok <- File.mkdir_p(Path.dirname(ruta)),
         :ok <- File.write(ruta, cookie <> "\n") do
      :ok
    end
  end
end
