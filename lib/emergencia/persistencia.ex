defmodule Emergencia.Persistencia do
  @moduledoc """
  Módulo para guardar y cargar datos de usuarios y zonas en archivos de texto (.txt).
  Los datos se guardan usando la representación de mapas y listas de Elixir.
  -version 1.0
  -autor: Samuel Franco Salazar
  -fecha: 2026-11-14
  """

  alias Emergencia.Modelos.{Catalogos, PuntoAtencion, Sector, Usuario, Zona}

  @defaults [
    directorio: "data",
    archivo_usuarios: "usuarios.txt",
    archivo_zonas: "zonas.txt"
  ]

  @inspect_opts [limit: :infinity, printable_limit: :infinity]

  @type clave :: :usuarios | :zonas
  @type usuarios :: %{optional(String.t()) => Usuario.t()}
  @type zonas :: %{optional(String.t()) => Zona.t()}
  @type error_linea :: {pos_integer(), term()}
  @type error_carga ::
          {:archivo_corrupto, Path.t(), [error_linea()]}
          | {:archivo_ilegible, Path.t(), File.posix() | atom()}

  # Rutas e inicialización

  @doc "Retorna el directorio de datos configurado."
  @spec directorio() :: Path.t()
  def directorio, do: config(:directorio)

  @doc "Retorna la ruta del archivo de usuarios."
  @spec ruta_usuarios() :: Path.t()
  def ruta_usuarios, do: Path.join(directorio(), config(:archivo_usuarios))

  @doc "Retorna la ruta del archivo de zonas."
  @spec ruta_zonas() :: Path.t()
  def ruta_zonas, do: Path.join(directorio(), config(:archivo_zonas))

  @doc "Crea la carpeta de datos y los archivos si no existen."
  @spec inicializar() :: :ok | {:error, {:inicializacion_fallida, Path.t(), term()}}
  def inicializar do
    with :ok <- crear_directorio(directorio()),
         :ok <- crear_archivo(ruta_usuarios()),
         :ok <- crear_archivo(ruta_zonas()) do
      :ok
    end
  end

  # Usuarios

  @doc "Guarda los usuarios en el archivo, reemplazando el contenido anterior."
  @spec guardar_usuarios(usuarios() | [Usuario.t()]) ::
          :ok | {:error, :entidades_invalidas | {:escritura_fallida, Path.t(), term()}}
  def guardar_usuarios(usuarios) do
    with {:ok, lista} <- a_lista(usuarios, Usuario) do
      lineas =
        lista
        |> Enum.sort_by(& &1.nombre_usuario)
        |> Enum.map(&serializar_usuario/1)

      escribir_atomico(ruta_usuarios(), lineas)
    end
  end

  @doc """
  Carga los usuarios desde el archivo de texto.

  Si el archivo canónico (`usuarios.txt`) todavía está vacío, usa la semilla
  `users.txt` en formato de barras (`U|usuario|contraseña|rol|zona|nombre`).
  """
  @spec cargar_usuarios() :: {:ok, usuarios()} | {:error, error_carga()}
  def cargar_usuarios do
    with {:ok, usuarios} <- cargar(ruta_usuarios(), &deserializar_usuario/1, & &1.nombre_usuario) do
      if map_size(usuarios) == 0 do
        cargar_usuarios_semilla()
      else
        {:ok, usuarios}
      end
    end
  end

  # Semilla de usuarios en formato de barras. Solo se usa mientras el archivo
  # canónico no tenga registros.
  defp cargar_usuarios_semilla do
    ruta = Path.join(directorio(), "users.txt")

    if File.exists?(ruta) do
      cargar(ruta, &deserializar_usuario/1, & &1.nombre_usuario)
    else
      {:ok, %{}}
    end
  end

  def serializar_usuario(%Usuario{} = u) do
    %{
      "nombre_usuario" => u.nombre_usuario,
      "password" => u.password,
      "nombre_completo" => u.nombre_completo,
      "rol" => Atom.to_string(u.rol),
      "zona_principal" => u.zona_principal
    }
    |> inspect(@inspect_opts)
  end

  def deserializar_usuario(linea) when is_binary(linea) do
    if String.contains?(linea, "|") do
      usuario_desde_pipe(linea)
    else
      with {:ok, literal} <- parsear_literal(linea) do
        usuario_desde_literal(literal)
      end
    end
  end

  # Zonas

  @doc "Guarda las zonas en el archivo, reemplazando el contenido anterior."
  @spec guardar_zonas(zonas() | [Zona.t()]) ::
          :ok | {:error, :entidades_invalidas | {:escritura_fallida, Path.t(), term()}}
  def guardar_zonas(zonas) do
    with {:ok, lista} <- a_lista(zonas, Zona) do
      lineas =
        lista
        |> Enum.sort_by(& &1.codigo)
        |> Enum.map(&serializar_zona/1)

      escribir_atomico(ruta_zonas(), lineas)
    end
  end

  @doc "Carga las zonas desde el archivo de texto."
  @spec cargar_zonas() :: {:ok, zonas()} | {:error, error_carga()}
  def cargar_zonas do
    cargar(ruta_zonas(), &deserializar_zona/1, & &1.codigo)
  end

  def serializar_zona(%Zona{} = z) do
    %{
      "codigo" => z.codigo,
      "nombre" => z.nombre,
      "nivel_afectacion" => Atom.to_string(z.nivel_afectacion),
      "total_afectados" => z.total_afectados,
      "sectores" =>
        z.sectores
        |> Map.values()
        |> Enum.sort_by(& &1.codigo)
        |> Enum.map(&sector_a_literal/1)
    }
    |> inspect(@inspect_opts)
  end

  def deserializar_zona(linea) when is_binary(linea) do
    if String.contains?(linea, "|") do
      zona_desde_pipe(linea)
    else
      with {:ok, literal} <- parsear_literal(linea) do
        zona_desde_literal(literal)
      end
    end
  end

  @doc "Renombra un archivo dañado y crea uno nuevo para evitar crashear el sistema."
  @spec poner_en_cuarentena(clave()) ::
          {:ok, Path.t()} | {:error, {:cuarentena_fallida, Path.t(), term()}}
  def poner_en_cuarentena(clave) when clave in [:usuarios, :zonas] do
    ruta = ruta_de(clave)
    destino = "#{ruta}.corrupto-#{System.os_time(:second)}"

    with :ok <- rename(ruta, destino),
         :ok <- inicializar() do
      {:ok, destino}
    else
      {:error, razon} -> {:error, {:cuarentena_fallida, ruta, razon}}
    end
  end

  # Funciones privadas

  defp config(clave) do
    :emergencia
    |> Application.get_env(:persistencia, [])
    |> Keyword.get(clave, Keyword.fetch!(@defaults, clave))
  end

  defp ruta_de(:usuarios), do: ruta_usuarios()
  defp ruta_de(:zonas), do: ruta_zonas()

  defp crear_directorio(dir) do
    case File.mkdir_p(dir) do
      :ok -> :ok
      {:error, razon} -> {:error, {:inicializacion_fallida, dir, razon}}
    end
  end

  defp crear_archivo(ruta) do
    case File.write(ruta, "", [:append]) do
      :ok -> :ok
      {:error, razon} -> {:error, {:inicializacion_fallida, ruta, razon}}
    end
  end

  defp rename(origen, destino) do
    case File.rename(origen, destino) do
      :ok -> :ok
      {:error, _} = error -> error
    end
  end

  defp cargar(ruta, deserializar, clave_fun) do
    case File.read(ruta) do
      {:ok, contenido} -> parsear_contenido(contenido, ruta, deserializar, clave_fun)
      {:error, :enoent} -> {:ok, %{}}
      {:error, razon} -> {:error, {:archivo_ilegible, ruta, razon}}
    end
  end

  defp parsear_contenido(contenido, ruta, deserializar, clave_fun) do
    if String.valid?(contenido) do
      {entidades, errores} =
        contenido
        |> String.split(["\r\n", "\n"])
        |> Enum.with_index(1)
        |> Enum.reject(fn {linea, _n} -> String.trim(linea) == "" end)
        |> Enum.reduce({%{}, []}, fn {linea, n}, {acc, errores} ->
          acumular(deserializar.(linea), n, clave_fun, acc, errores)
        end)

      case errores do
        [] -> {:ok, entidades}
        _ -> {:error, {:archivo_corrupto, ruta, Enum.reverse(errores)}}
      end
    else
      {:error, {:archivo_corrupto, ruta, [{1, :utf8_invalido}]}}
    end
  end

  defp acumular({:ok, entidad}, n, clave_fun, acc, errores) do
    clave = clave_fun.(entidad)

    if Map.has_key?(acc, clave),
      do: {acc, [{n, :codigo_duplicado} | errores]},
      else: {Map.put(acc, clave, entidad), errores}
  end

  defp acumular({:error, razon}, n, _clave_fun, acc, errores),
    do: {acc, [{n, razon} | errores]}

  # ---------- Parsers del formato de barras ----------
  #
  # Los archivos semilla usan una línea por registro:
  #   usuarios: U|usuario|contraseña|rol|zona|nombre_completo
  #   zonas:    Z|codigo|nombre|nivel|total_afectados[|sectores]
  #
  # Los sectores se separan con ";" y el encabezado del sector con "~".
  # Los puntos van después de "^" y se separan entre sí con "^":
  #   S1~Sector Norte^P1~Punto 1~Frente al parque
  # Cada sector es "codigo~nombre" y cada punto "codigo~nombre~descripcion".

  defp usuario_desde_pipe(linea) do
    case separar_pipe(linea, "U") do
      [usuario, password, rol, zona, nombre_completo] ->
        crear_usuario_pipe(usuario, password, nombre_completo, rol, zona)

      [usuario, password, rol, zona] ->
        crear_usuario_pipe(usuario, password, usuario, rol, zona)

      _ ->
        {:error, :estructura_invalida}
    end
  end

  defp crear_usuario_pipe(usuario, password, nombre_completo, rol, zona) do
    with {:ok, usuario} <- Catalogos.validar_texto(usuario, :nombre_usuario),
         {:ok, nombre_completo} <- Catalogos.validar_texto(nombre_completo, :nombre_completo),
         {:ok, rol} <- Catalogos.parse_rol(rol),
         {:ok, zona} <- Catalogos.validar_texto(zona, :zona_principal),
         {:ok, password} <- preparar_password(password) do
      {:ok,
       %Usuario{
         nombre_usuario: usuario,
         password: password,
         nombre_completo: nombre_completo,
         rol: rol,
         zona_principal: zona
       }}
    end
  end

  # La semilla puede traer la contraseña en claro (se hashea) o ya hasheada.
  defp preparar_password(password) do
    cond do
      Emergencia.Util.hex_valido?(password) ->
        {:ok, password}

      password == "" ->
        {:error, {:campo_invalido, :password}}

      true ->
        {:ok, :crypto.hash(:sha256, password) |> Base.encode16(case: :lower)}
    end
  end

  defp zona_desde_pipe(linea) do
    case separar_pipe(linea, "Z") do
      [codigo, nombre, nivel, total] ->
        with {:ok, total} <- entero_no_negativo(total) do
          Zona.new(codigo, nombre, nivel, total)
        end

      [codigo, nombre, nivel, total, sectores] ->
        with {:ok, total} <- entero_no_negativo(total),
             {:ok, sectores} <- sectores_desde_pipe(sectores) do
          Zona.new(codigo, nombre, nivel, total, sectores)
        end

      _ ->
        {:error, :estructura_invalida}
    end
  end

  defp separar_pipe(linea, prefijo) do
    campos =
      linea
      |> String.split("|")
      |> Enum.map(&String.trim/1)

    case campos do
      [^prefijo | resto] -> resto
      otros -> otros
    end
  end

  defp entero_no_negativo(texto) do
    case Integer.parse(String.trim(texto)) do
      {numero, ""} when numero >= 0 -> {:ok, numero}
      _ -> {:error, {:campo_invalido, :total_afectados}}
    end
  end

  defp sectores_desde_pipe(""), do: {:ok, []}

  defp sectores_desde_pipe(texto) do
    texto
    |> String.split(";", trim: true)
    |> mapear(&sector_desde_pipe/1)
  end

  defp sector_desde_pipe(texto) do
    {cabecera, puntos} =
      case String.split(texto, "^", parts: 2) do
        [cabecera] -> {cabecera, ""}
        [cabecera, puntos] -> {cabecera, puntos}
      end

    with [codigo, nombre] <- String.split(cabecera, "~", parts: 2),
         {:ok, puntos} <- puntos_desde_pipe(puntos) do
      Sector.new(codigo, nombre, puntos)
    else
      {:error, _} = error -> error
      _ -> {:error, :estructura_invalida}
    end
  end

  defp puntos_desde_pipe(""), do: {:ok, []}

  defp puntos_desde_pipe(texto) do
    texto
    |> String.split("^", trim: true)
    |> mapear(&punto_desde_pipe/1)
  end

  defp punto_desde_pipe(texto) do
    case String.split(texto, "~", parts: 3) do
      [codigo, nombre] -> PuntoAtencion.new(codigo, nombre, "")
      [codigo, nombre, descripcion] -> PuntoAtencion.new(codigo, nombre, descripcion)
      _ -> {:error, :estructura_invalida}
    end
  end

  defp parsear_literal(linea) do
    case Code.string_to_quoted(linea, existing_atoms_only: true) do
      {:ok, ast} -> literal(ast)
      {:error, _} -> {:error, :sintaxis_invalida}
    end
  end

  defp literal(valor) when is_binary(valor), do: {:ok, valor}
  defp literal(valor) when is_integer(valor), do: {:ok, valor}
  defp literal(lista) when is_list(lista), do: mapear(lista, &literal/1)

  defp literal({:%{}, _meta, pares}) when is_list(pares) do
    with {:ok, pares} <- mapear(pares, &par_literal/1) do
      {:ok, Map.new(pares)}
    end
  end

  defp literal(_otro), do: {:error, :literal_no_permitido}

  defp par_literal({clave, valor}) when is_binary(clave) do
    with {:ok, valor} <- literal(valor), do: {:ok, {clave, valor}}
  end

  defp par_literal(_otro), do: {:error, :literal_no_permitido}

  defp usuario_desde_literal(%{
         "nombre_usuario" => nombre_usuario,
         "password" => password,
         "nombre_completo" => nombre_completo,
         "rol" => rol,
         "zona_principal" => zona_principal
       }) do
    with {:ok, nombre_usuario} <- Catalogos.validar_texto(nombre_usuario, :nombre_usuario),
         {:ok, password} <- validar_hash(password),
         {:ok, nombre_completo} <- Catalogos.validar_texto(nombre_completo, :nombre_completo),
         {:ok, rol} <- Catalogos.parse_rol(rol),
         {:ok, zona_principal} <- Catalogos.validar_texto(zona_principal, :zona_principal) do
      {:ok,
       %Usuario{
         nombre_usuario: nombre_usuario,
         password: password,
         nombre_completo: nombre_completo,
         rol: rol,
         zona_principal: zona_principal
       }}
    end
  end

  defp usuario_desde_literal(_otro), do: {:error, :estructura_invalida}

  defp validar_hash(valor) when is_binary(valor) do
    if Emergencia.Util.hex_valido?(valor),
      do: {:ok, valor},
      else: {:error, {:campo_invalido, :password}}
  end

  defp validar_hash(_otro), do: {:error, {:campo_invalido, :password}}

  defp zona_desde_literal(%{
         "codigo" => codigo,
         "nombre" => nombre,
         "nivel_afectacion" => nivel,
         "total_afectados" => total,
         "sectores" => sectores
       })
       when is_list(sectores) do
    with {:ok, sectores} <- mapear(sectores, &sector_desde_literal/1) do
      Zona.new(codigo, nombre, nivel, total, sectores)
    end
  end

  defp zona_desde_literal(_otro), do: {:error, :estructura_invalida}

  defp sector_desde_literal(%{
         "codigo" => codigo,
         "nombre" => nombre,
         "puntos_atencion" => puntos
       })
       when is_list(puntos) do
    with {:ok, puntos} <- mapear(puntos, &punto_desde_literal/1) do
      Sector.new(codigo, nombre, puntos)
    end
  end

  defp sector_desde_literal(_otro), do: {:error, :estructura_invalida}

  defp punto_desde_literal(%{
         "codigo" => codigo,
         "nombre" => nombre,
         "descripcion" => descripcion
       }) do
    PuntoAtencion.new(codigo, nombre, descripcion)
  end

  defp punto_desde_literal(_otro), do: {:error, :estructura_invalida}

  defp sector_a_literal(%Sector{} = s) do
    %{
      "codigo" => s.codigo,
      "nombre" => s.nombre,
      "puntos_atencion" => Enum.map(s.puntos_atencion, &punto_a_literal/1)
    }
  end

  defp punto_a_literal(%PuntoAtencion{} = p) do
    %{"codigo" => p.codigo, "nombre" => p.nombre, "descripcion" => p.descripcion}
  end

  defp mapear(lista, fun) do
    lista
    |> Enum.reduce_while({:ok, []}, fn elemento, {:ok, acc} ->
      case fun.(elemento) do
        {:ok, valor} -> {:cont, {:ok, [valor | acc]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      {:error, _} = error -> error
    end
  end

  defp a_lista(entrada, modulo) do
    lista =
      case entrada do
        mapa when is_map(mapa) and not is_struct(mapa) -> Map.values(mapa)
        lista when is_list(lista) -> lista
        _otro -> :invalido
      end

    if is_list(lista) and Enum.all?(lista, &is_struct(&1, modulo)),
      do: {:ok, lista},
      else: {:error, :entidades_invalidas}
  end

  defp escribir_atomico(ruta, lineas) do
    contenido = Enum.map(lineas, &[&1, ?\n])
    temporal = ruta <> ".tmp"

    with :ok <- File.mkdir_p(Path.dirname(ruta)),
         :ok <- escribir_y_cerrar(temporal, contenido),
         :ok <- File.rename(temporal, ruta) do
      :ok
    else
      {:error, razon} ->
        _ = File.rm(temporal)
        {:error, {:escritura_fallida, ruta, razon}}
    end
  end

  defp escribir_y_cerrar(ruta, contenido) do
    resultado =
      File.open(ruta, [:write, :binary], fn io ->
        with :ok <- IO.binwrite(io, contenido) do
          :file.sync(io)
        end
      end)

    case resultado do
      {:ok, :ok} -> :ok
      {:ok, {:error, razon}} -> {:error, razon}
      {:error, razon} -> {:error, razon}
    end
  end
end
