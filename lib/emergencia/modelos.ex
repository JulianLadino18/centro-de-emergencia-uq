defmodule Emergencia.Modelos.Catalogos do
  @moduledoc "Catálogos y guardas para roles y niveles de afectación.
  -version 1.0
  -autor: Samuel Franco Salazar
  -fecha: 2026-11-14
  "

  @roles [:ciudadano, :voluntario, :coordinador, :administrador]
  @niveles [:critico, :alto, :medio, :bajo]

  @type rol :: :ciudadano | :voluntario | :coordinador | :administrador
  @type nivel_afectacion :: :critico | :alto | :medio | :bajo

  defguard es_rol?(valor) when valor in @roles
  defguard es_nivel?(valor) when valor in @niveles

  @doc "Lista de roles permitidos."
  @spec roles() :: [rol()]
  def roles, do: @roles

  @doc "Lista de niveles de afectación permitidos."
  @spec niveles() :: [nivel_afectacion()]
  def niveles, do: @niveles

  @doc "Peso numérico de un nivel para ordenar zonas por gravedad."
  @spec peso_nivel(nivel_afectacion()) :: 1..4
  def peso_nivel(:critico), do: 4
  def peso_nivel(:alto), do: 3
  def peso_nivel(:medio), do: 2
  def peso_nivel(:bajo), do: 1

  @doc "Convierte un valor en un rol válido."
  @spec parse_rol(term()) :: {:ok, rol()} | {:error, :rol_invalido}
  def parse_rol(valor) when es_rol?(valor), do: {:ok, valor}

  def parse_rol(valor) when is_binary(valor) do
    case buscar_en_catalogo(valor, @roles) do
      {:ok, rol} -> {:ok, rol}
      :error -> {:error, :rol_invalido}
    end
  end

  def parse_rol(_), do: {:error, :rol_invalido}

  @doc "Convierte un valor en un nivel de afectación válido."
  @spec parse_nivel(term()) :: {:ok, nivel_afectacion()} | {:error, :nivel_invalido}
  def parse_nivel(valor) when es_nivel?(valor), do: {:ok, valor}

  def parse_nivel(valor) when is_binary(valor) do
    case buscar_en_catalogo(valor, @niveles) do
      {:ok, nivel} -> {:ok, nivel}
      :error -> {:error, :nivel_invalido}
    end
  end

  def parse_nivel(_), do: {:error, :nivel_invalido}

  @doc "Valida que el valor sea un string no vacío."
  @spec validar_texto(term(), atom()) ::
          {:ok, String.t()} | {:error, {:campo_vacio | :campo_invalido, atom()}}
  def validar_texto(valor, campo) when is_binary(valor) do
    case String.trim(valor) do
      "" -> {:error, {:campo_vacio, campo}}
      texto -> {:ok, texto}
    end
  end

  def validar_texto(_valor, campo), do: {:error, {:campo_invalido, campo}}

  @doc "Valida que el valor sea un entero mayor o igual a cero."
  @spec validar_entero_no_negativo(term(), atom()) ::
          {:ok, non_neg_integer()} | {:error, {:cantidad_negativa | :campo_invalido, atom()}}
  def validar_entero_no_negativo(valor, _campo) when is_integer(valor) and valor >= 0,
    do: {:ok, valor}

  def validar_entero_no_negativo(valor, campo) when is_integer(valor),
    do: {:error, {:cantidad_negativa, campo}}

  def validar_entero_no_negativo(_valor, campo), do: {:error, {:campo_invalido, campo}}

  # Funciones privadas

  defp buscar_en_catalogo(texto, catalogo) do
    normalizado = normalizar(texto)

    case Enum.find(catalogo, fn atomo -> Atom.to_string(atomo) == normalizado end) do
      nil -> :error
      atomo -> {:ok, atomo}
    end
  end

  defp normalizar(texto) do
    texto
    |> String.trim()
    |> String.downcase()
    |> String.replace(["á", "é", "í", "ó", "ú"], fn
      "á" -> "a"
      "é" -> "e"
      "í" -> "i"
      "ó" -> "o"
      "ú" -> "u"
    end)
  end
end

defmodule Emergencia.Modelos.PuntoAtencion do
  @moduledoc "Estructura para los puntos de atención."

  alias Emergencia.Modelos.Catalogos

  @enforce_keys [:codigo, :nombre]
  defstruct [:codigo, :nombre, descripcion: ""]

  @type t :: %__MODULE__{
          codigo: String.t(),
          nombre: String.t(),
          descripcion: String.t()
        }

  @type error :: {:campo_vacio | :campo_invalido, atom()}

  @doc "Crea un punto de atención validado."
  @spec new(term(), term(), term()) :: {:ok, t()} | {:error, error()}
  def new(codigo, nombre, descripcion \\ "") do
    with {:ok, codigo} <- Catalogos.validar_texto(codigo, :codigo),
         {:ok, nombre} <- Catalogos.validar_texto(nombre, :nombre),
         {:ok, descripcion} <- validar_descripcion(descripcion) do
      {:ok, %__MODULE__{codigo: codigo, nombre: nombre, descripcion: descripcion}}
    end
  end

  defp validar_descripcion(nil), do: {:ok, ""}
  defp validar_descripcion(d) when is_binary(d), do: {:ok, String.trim(d)}
  defp validar_descripcion(_), do: {:error, {:campo_invalido, :descripcion}}
end

defmodule Emergencia.Modelos.Sector do
  @moduledoc "Estructura para los sectores de una zona."

  alias Emergencia.Modelos.{Catalogos, PuntoAtencion}

  @enforce_keys [:codigo, :nombre]
  defstruct [:codigo, :nombre, puntos_atencion: []]

  @type t :: %__MODULE__{
          codigo: String.t(),
          nombre: String.t(),
          puntos_atencion: [PuntoAtencion.t()]
        }

  @type error ::
          {:campo_vacio | :campo_invalido, atom()}
          | :punto_atencion_invalido
          | :punto_atencion_duplicado

  @doc "Crea un sector validado."
  @spec new(term(), term(), term()) :: {:ok, t()} | {:error, error()}
  def new(codigo, nombre, puntos_atencion \\ []) do
    with {:ok, codigo} <- Catalogos.validar_texto(codigo, :codigo),
         {:ok, nombre} <- Catalogos.validar_texto(nombre, :nombre),
         {:ok, puntos} <- validar_puntos(puntos_atencion) do
      {:ok, %__MODULE__{codigo: codigo, nombre: nombre, puntos_atencion: puntos}}
    end
  end

  @doc "Agrega un punto de atención al sector validando duplicados."
  @spec agregar_punto(t(), PuntoAtencion.t()) :: {:ok, t()} | {:error, error()}
  def agregar_punto(%__MODULE__{puntos_atencion: puntos} = sector, %PuntoAtencion{} = punto) do
    if Enum.any?(puntos, &(&1.codigo == punto.codigo)) do
      {:error, :punto_atencion_duplicado}
    else
      {:ok, %__MODULE__{sector | puntos_atencion: puntos ++ [punto]}}
    end
  end

  def agregar_punto(%__MODULE__{}, _otro), do: {:error, :punto_atencion_invalido}

  defp validar_puntos(puntos) when is_list(puntos) do
    cond do
      not Enum.all?(puntos, &match?(%PuntoAtencion{}, &1)) ->
        {:error, :punto_atencion_invalido}

      codigos_repetidos?(puntos) ->
        {:error, :punto_atencion_duplicado}

      true ->
        {:ok, puntos}
    end
  end

  defp validar_puntos(_), do: {:error, :punto_atencion_invalido}

  defp codigos_repetidos?(puntos) do
    codigos = Enum.map(puntos, & &1.codigo)
    length(codigos) != length(Enum.uniq(codigos))
  end
end

defmodule Emergencia.Modelos.Zona do
  @moduledoc "Estructura para las zonas afectadas."

  alias Emergencia.Modelos.{Catalogos, Sector}

  @enforce_keys [:codigo, :nombre, :nivel_afectacion]
  defstruct [:codigo, :nombre, :nivel_afectacion, sectores: %{}, total_afectados: 0]

  @type t :: %__MODULE__{
          codigo: String.t(),
          nombre: String.t(),
          nivel_afectacion: Catalogos.nivel_afectacion(),
          sectores: %{optional(String.t()) => Sector.t()},
          total_afectados: non_neg_integer()
        }

  @type error ::
          {:campo_vacio | :campo_invalido | :cantidad_negativa, atom()}
          | :nivel_invalido
          | :sector_invalido
          | :sector_duplicado

  @doc "Crea una zona validada."
  @spec new(term(), term(), term(), term(), term()) :: {:ok, t()} | {:error, error()}
  def new(codigo, nombre, nivel, total_afectados \\ 0, sectores \\ []) do
    with {:ok, codigo} <- Catalogos.validar_texto(codigo, :codigo),
         {:ok, nombre} <- Catalogos.validar_texto(nombre, :nombre),
         {:ok, nivel} <- Catalogos.parse_nivel(nivel),
         {:ok, total} <- Catalogos.validar_entero_no_negativo(total_afectados, :total_afectados),
         {:ok, mapa} <- indexar_sectores(sectores) do
      {:ok,
       %__MODULE__{
         codigo: codigo,
         nombre: nombre,
         nivel_afectacion: nivel,
         sectores: mapa,
         total_afectados: total
       }}
    end
  end

  @doc "Agrega un sector a la zona validando duplicados."
  @spec agregar_sector(t(), Sector.t()) :: {:ok, t()} | {:error, error()}
  def agregar_sector(%__MODULE__{sectores: sectores} = zona, %Sector{codigo: cod} = sector) do
    if Map.has_key?(sectores, cod) do
      {:error, :sector_duplicado}
    else
      {:ok, %__MODULE__{zona | sectores: Map.put(sectores, cod, sector)}}
    end
  end

  def agregar_sector(%__MODULE__{}, _otro), do: {:error, :sector_invalido}

  @doc "Reemplaza un sector existente."
  @spec actualizar_sector(t(), Sector.t()) :: {:ok, t()} | {:error, :sector_inexistente}
  def actualizar_sector(%__MODULE__{sectores: sectores} = zona, %Sector{codigo: cod} = sector) do
    if Map.has_key?(sectores, cod) do
      {:ok, %__MODULE__{zona | sectores: Map.put(sectores, cod, sector)}}
    else
      {:error, :sector_inexistente}
    end
  end

  @doc "Cambia el nivel de afectación de la zona."
  @spec actualizar_nivel(t(), term()) :: {:ok, t()} | {:error, :nivel_invalido}
  def actualizar_nivel(%__MODULE__{} = zona, nivel) do
    with {:ok, nivel} <- Catalogos.parse_nivel(nivel) do
      {:ok, %__MODULE__{zona | nivel_afectacion: nivel}}
    end
  end

  @doc "Actualiza el número de personas afectadas."
  @spec actualizar_total_afectados(t(), term()) ::
          {:ok, t()} | {:error, {:cantidad_negativa | :campo_invalido, atom()}}
  def actualizar_total_afectados(%__MODULE__{} = zona, total) do
    with {:ok, total} <- Catalogos.validar_entero_no_negativo(total, :total_afectados) do
      {:ok, %__MODULE__{zona | total_afectados: total}}
    end
  end

  defp indexar_sectores(sectores) when is_list(sectores) do
    Enum.reduce_while(sectores, {:ok, %{}}, fn
      %Sector{codigo: cod} = sector, {:ok, acc} ->
        if Map.has_key?(acc, cod) do
          {:halt, {:error, :sector_duplicado}}
        else
          {:cont, {:ok, Map.put(acc, cod, sector)}}
        end

      _otro, _acc ->
        {:halt, {:error, :sector_invalido}}
    end)
  end

  defp indexar_sectores(_), do: {:error, :sector_invalido}
end

defmodule Emergencia.Modelos.Usuario do
  @moduledoc "Estructura para los usuarios del sistema. Las contraseñas se guardan con SHA-256."

  alias Emergencia.Modelos.Catalogos

  @enforce_keys [:nombre_usuario, :password, :nombre_completo, :rol, :zona_principal]
  defstruct [:nombre_usuario, :password, :nombre_completo, :rol, :zona_principal]

  @type t :: %__MODULE__{
          nombre_usuario: String.t(),
          password: String.t(),
          nombre_completo: String.t(),
          rol: Catalogos.rol(),
          zona_principal: String.t()
        }

  @type error :: {:campo_vacio | :campo_invalido, atom()} | :rol_invalido

  @doc "Crea un usuario validado."
  @spec new(term(), term(), term(), term(), term()) :: {:ok, t()} | {:error, error()}
  def new(nombre_usuario, password, nombre_completo, rol, zona_principal) do
    with {:ok, usuario} <- Catalogos.validar_texto(nombre_usuario, :nombre_usuario),
         {:ok, password} <- Catalogos.validar_texto(password, :password),
         {:ok, completo} <- Catalogos.validar_texto(nombre_completo, :nombre_completo),
         {:ok, rol} <- parse_rol(rol),
         {:ok, zona} <- Catalogos.validar_texto(zona_principal, :zona_principal) do
      {:ok,
       %__MODULE__{
         nombre_usuario: usuario,
         password: hashear(password),
         nombre_completo: completo,
         rol: rol,
         zona_principal: zona
       }}
    end
  end

  @doc "Verifica una contraseña en texto plano contra el hash guardado."
  @spec password_correcto?(t(), String.t()) :: boolean()
  def password_correcto?(%__MODULE__{password: hash}, password) when is_binary(password),
    do: hash == hashear(password)

  def password_correcto?(%__MODULE__{}, _), do: false

  @doc "Valida credenciales para el inicio de sesión."
  @spec autenticar(t(), String.t()) :: {:ok, t()} | {:error, :credenciales_invalidas}
  def autenticar(%__MODULE__{} = usuario, password) do
    if password_correcto?(usuario, password),
      do: {:ok, usuario},
      else: {:error, :credenciales_invalidas}
  end

  @doc "Indica si el usuario tiene alguno de los roles dados."
  @spec tiene_rol?(t(), [Catalogos.rol()]) :: boolean()
  def tiene_rol?(%__MODULE__{rol: rol}, roles) when is_list(roles), do: rol in roles

  defp parse_rol(rol), do: Catalogos.parse_rol(rol)

  defp hashear(password),
    do: :crypto.hash(:sha256, password) |> Base.encode16(case: :lower)
end

defmodule Emergencia.Modelos do
  @moduledoc "Fachada principal para los modelos de la Persona 1."

  alias Emergencia.Modelos.{Catalogos, PuntoAtencion, Sector, Usuario, Zona}

  @type rol :: Catalogos.rol()
  @type nivel_afectacion :: Catalogos.nivel_afectacion()
  @type usuario :: Usuario.t()
  @type zona :: Zona.t()
  @type sector :: Sector.t()
  @type punto_atencion :: PuntoAtencion.t()
  @type resultado(t) :: {:ok, t} | {:error, term()}

  defdelegate nuevo_usuario(nombre_usuario, password, nombre_completo, rol, zona_principal),
    to: Usuario,
    as: :new

  defdelegate nueva_zona(codigo, nombre, nivel, total_afectados \\ 0, sectores \\ []),
    to: Zona,
    as: :new

  defdelegate nuevo_sector(codigo, nombre, puntos_atencion \\ []), to: Sector, as: :new

  defdelegate nuevo_punto_atencion(codigo, nombre, descripcion \\ ""),
    to: PuntoAtencion,
    as: :new

  defdelegate roles(), to: Catalogos
  defdelegate niveles(), to: Catalogos
  defdelegate parse_rol(valor), to: Catalogos
  defdelegate parse_nivel(valor), to: Catalogos
end
