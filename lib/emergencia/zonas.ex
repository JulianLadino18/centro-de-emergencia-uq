defmodule Emergencia.Zonas do
  @moduledoc "Módulo funcional para manejar la jerarquía de Zona -> Sector -> Punto de atención.
  -version 1.0
  -autor: Samuel Franco Salazar
  -fecha: 2026-11-14
  "

  alias Emergencia.Modelos.{Catalogos, PuntoAtencion, Sector, Zona}

  require Catalogos

  @umbral_critico 5_000
  @msg_duplicado "Código duplicado"
  @msg_nivel "Nivel de afectación inválido (válidos: crítico, alto, medio, bajo)"

  @type zonas :: %{optional(String.t()) => Zona.t()}
  @type error :: {:error, String.t()}

  @doc "Registra una zona validando que el código no exista."
  @spec registrar_zona(zonas(), term(), term(), term(), term()) :: {:ok, zonas()} | error()
  def registrar_zona(zonas, codigo, nombre, nivel, total_afectados \\ 0) when is_map(zonas) do
    with {:ok, zona} <- con_mensaje(Zona.new(codigo, nombre, nivel, total_afectados)),
         :ok <- validar_zona_nueva(zonas, zona.codigo) do
      {:ok, Map.put(zonas, zona.codigo, zona)}
    end
  end

  @doc "Registra un sector dentro de una zona. El código no puede repetirse."
  @spec registrar_sector(Zona.t(), term(), term()) :: {:ok, Zona.t()} | error()
  def registrar_sector(%Zona{} = zona, codigo, nombre) do
    with {:ok, sector} <- con_mensaje(Sector.new(codigo, nombre)) do
      con_mensaje(Zona.agregar_sector(zona, sector))
    end
  end

  @doc "Registra un punto de atención. Su código debe ser único en toda la zona."
  @spec registrar_punto(Zona.t(), String.t(), term(), term(), term()) ::
          {:ok, Zona.t()} | error()
  def registrar_punto(%Zona{} = zona, codigo_sector, codigo, nombre, descripcion \\ "") do
    with {:ok, sector} <- buscar_sector(zona, codigo_sector),
         {:ok, punto} <- con_mensaje(PuntoAtencion.new(codigo, nombre, descripcion)),
         :ok <- validar_punto_nuevo(zona, punto.codigo),
         {:ok, sector} <- con_mensaje(Sector.agregar_punto(sector, punto)) do
      con_mensaje(Zona.actualizar_sector(zona, sector))
    end
  end

  @doc "Cambia el nivel de afectación de una zona registrada."
  @spec actualizar_nivel(zonas(), String.t(), term()) :: {:ok, zonas()} | error()
  def actualizar_nivel(zonas, codigo_zona, nivel) when is_map(zonas) do
    with {:ok, zona} <- buscar_zona(zonas, codigo_zona),
         {:ok, zona} <- con_mensaje(Zona.actualizar_nivel(zona, nivel)) do
      {:ok, Map.put(zonas, zona.codigo, zona)}
    end
  end

  @doc "Busca una zona por código."
  @spec buscar_zona(zonas(), String.t()) :: {:ok, Zona.t()} | error()
  def buscar_zona(zonas, codigo) when is_map(zonas) do
    case Map.fetch(zonas, codigo) do
      {:ok, zona} -> {:ok, zona}
      :error -> {:error, "Zona no encontrada"}
    end
  end

  @doc "Busca un sector por código dentro de una zona."
  @spec buscar_sector(Zona.t(), String.t()) :: {:ok, Sector.t()} | error()
  def buscar_sector(%Zona{sectores: sectores}, codigo) do
    case Map.fetch(sectores, codigo) do
      {:ok, sector} -> {:ok, sector}
      :error -> {:error, "Sector no encontrado"}
    end
  end

  @doc "Retorna el estado general de una zona."
  @spec estado_zona(Zona.t()) :: map()
  def estado_zona(%Zona{} = zona) do
    %{
      codigo: zona.codigo,
      nombre: zona.nombre,
      nivel_afectacion: zona.nivel_afectacion,
      nivel_efectivo: nivel_efectivo(zona),
      total_afectados: zona.total_afectados,
      sectores: map_size(zona.sectores),
      puntos_atencion: contar_puntos(zona)
    }
  end

  @doc "Retorna estadísticas de cantidad de puntos por sector usando recursividad."
  @spec estadisticas_por_sector(Zona.t()) :: %{optional(String.t()) => non_neg_integer()}
  def estadisticas_por_sector(%Zona{} = zona) do
    recorrer_sectores(zona, %{}, fn %Sector{codigo: cod} = sector, acc ->
      Map.put(acc, cod, contar_puntos(sector))
    end)
  end

  @doc "El nivel efectivo sube a critico si hay más de 5000 afectados."
  @spec nivel_efectivo(Zona.t()) :: Catalogos.nivel_afectacion()
  def nivel_efectivo(%Zona{total_afectados: total}) when total >= @umbral_critico, do: :critico
  def nivel_efectivo(%Zona{nivel_afectacion: nivel}), do: nivel

  @doc "Función recursiva para iterar los sectores."
  @spec recorrer_sectores(Zona.t() | [Sector.t()], acc, (Sector.t(), acc -> acc)) :: acc
        when acc: term()
  def recorrer_sectores(%Zona{sectores: sectores}, acumulador, fun) when is_function(fun, 2) do
    sectores
    |> Map.values()
    |> Enum.sort_by(& &1.codigo)
    |> recorrer_sectores(acumulador, fun)
  end

  def recorrer_sectores([], acumulador, fun) when is_function(fun, 2), do: acumulador

  def recorrer_sectores([%Sector{} = sector | resto], acumulador, fun)
      when is_function(fun, 2) do
    recorrer_sectores(resto, fun.(sector, acumulador), fun)
  end

  @doc "Función recursiva para contar los puntos de atención."
  @spec contar_puntos(Zona.t() | Sector.t() | [Sector.t()] | [PuntoAtencion.t()]) ::
          non_neg_integer()
  def contar_puntos(%Zona{sectores: sectores}), do: sectores |> Map.values() |> contar_puntos()
  def contar_puntos(%Sector{puntos_atencion: puntos}), do: contar_puntos(puntos)
  def contar_puntos([]), do: 0
  def contar_puntos([%Sector{} = sector | resto]), do: contar_puntos(sector) + contar_puntos(resto)
  def contar_puntos([%PuntoAtencion{} | resto]), do: 1 + contar_puntos(resto)

  @doc "Calcula recursivamente el nivel de afectación más grave."
  @spec nivel_maximo([Zona.t() | Catalogos.nivel_afectacion()], Catalogos.nivel_afectacion() | nil) ::
          Catalogos.nivel_afectacion() | nil
  def nivel_maximo([], acumulador), do: acumulador

  def nivel_maximo([%Zona{} = zona | resto], acumulador),
    do: nivel_maximo(resto, mas_grave(acumulador, nivel_efectivo(zona)))

  def nivel_maximo([nivel | resto], acumulador) when Catalogos.es_nivel?(nivel),
    do: nivel_maximo(resto, mas_grave(acumulador, nivel))

  @doc "Nivel máximo de todo el sistema."
  @spec nivel_maximo_regional(zonas()) :: {:ok, Catalogos.nivel_afectacion()} | error()
  def nivel_maximo_regional(zonas) when is_map(zonas) do
    case nivel_maximo(Map.values(zonas), nil) do
      nil -> {:error, "No hay zonas registradas"}
      nivel -> {:ok, nivel}
    end
  end

  # Funciones privadas

  defp mas_grave(nil, nivel), do: nivel

  defp mas_grave(actual, nivel) do
    if Catalogos.peso_nivel(nivel) > Catalogos.peso_nivel(actual), do: nivel, else: actual
  end

  defp validar_zona_nueva(zonas, codigo) do
    if Map.has_key?(zonas, codigo), do: {:error, @msg_duplicado}, else: :ok
  end

  defp validar_punto_nuevo(%Zona{} = zona, codigo) do
    existe? =
      recorrer_sectores(zona, false, fn %Sector{puntos_atencion: puntos}, acc ->
        acc or Enum.any?(puntos, &(&1.codigo == codigo))
      end)

    if existe?, do: {:error, @msg_duplicado}, else: :ok
  end

  defp con_mensaje({:ok, _} = ok), do: ok
  defp con_mensaje({:error, razon}), do: {:error, traducir(razon)}

  defp traducir(:sector_duplicado), do: @msg_duplicado
  defp traducir(:punto_atencion_duplicado), do: @msg_duplicado
  defp traducir(:nivel_invalido), do: @msg_nivel
  defp traducir(:sector_inexistente), do: "Sector no encontrado"
  defp traducir(:sector_invalido), do: "Sector inválido"
  defp traducir(:punto_atencion_invalido), do: "Punto de atención inválido"
  defp traducir({:campo_vacio, campo}), do: "El campo #{campo} no puede estar vacío"
  defp traducir({:campo_invalido, campo}), do: "El campo #{campo} es inválido"
  defp traducir({:cantidad_negativa, campo}), do: "El campo #{campo} no puede ser negativo"
  defp traducir(otro), do: "Error: #{inspect(otro)}"
end
