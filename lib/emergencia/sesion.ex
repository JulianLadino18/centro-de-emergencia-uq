defmodule Emergencia.Sesion do
  @moduledoc """
  GenServer para manejar el estado global de los usuarios conectados,
  las sesiones (cookies) y el historial de actividad.
  -version 1.0
  -autor: Samuel Franco Salazar
  -fecha: 2026-11-15
  """

  use GenServer

  require Logger

  alias Emergencia.Modelos.{Catalogos, Usuario}
  alias Emergencia.Persistencia

  @zona_por_defecto "sin_zona"
  @historial_max 1_000
  @limite_historial 50
  @timeout 5_000

  @type cookie :: String.t()
  @type usuario_publico :: %{
          nombre_usuario: String.t(),
          nombre_completo: String.t(),
          rol: Catalogos.rol(),
          zona_principal: String.t()
        }
  @type evento :: %{
          en: DateTime.t(),
          usuario: String.t(),
          accion: atom() | String.t(),
          detalle: String.t() | nil
        }

  # API Pública

  @doc "Inicia el servidor GenServer."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) when is_list(opts) do
    nombre = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: nombre)
  end

  @doc "Conecta a un usuario. Si no existe, lo registra y lo guarda. Devuelve la cookie de sesión."
  @spec connect(term(), term(), keyword()) ::
          {:ok, %{cookie: cookie(), usuario: usuario_publico(), nuevo: boolean()}}
          | {:error, term()}
  def connect(username, password, opts \\ [])

  def connect(username, password, opts) when is_list(opts) do
    llamar({:connect, username, password, Keyword.take(opts, [:rol, :zona, :nombre_completo])}, opts)
  end

  def connect(_username, _password, _opts), do: {:error, :opciones_invalidas}

  @doc "Cierra la sesión usando la cookie."
  @spec disconnect(cookie(), keyword()) :: :ok | {:error, term()}
  def disconnect(cookie, opts \\ []) when is_list(opts), do: llamar({:disconnect, cookie}, opts)

  @doc "Obtiene los datos públicos del usuario según su cookie."
  @spec usuario_actual(cookie(), keyword()) :: {:ok, usuario_publico()} | {:error, term()}
  def usuario_actual(cookie, opts \\ []) when is_list(opts),
    do: llamar({:usuario_actual, cookie}, opts)

  @doc "Verifica que el usuario de la sesión tenga uno de los roles permitidos."
  @spec autorizar(cookie(), [Catalogos.rol()], keyword()) ::
          {:ok, usuario_publico()} | {:error, term()}
  def autorizar(cookie, roles, opts \\ [])

  def autorizar(cookie, roles, opts) when is_list(roles) and is_list(opts),
    do: llamar({:autorizar, cookie, roles}, opts)

  def autorizar(_cookie, _roles, _opts), do: {:error, :roles_invalidos}

  @doc "Guarda un evento en el historial del usuario."
  @spec registrar_actividad(cookie(), atom() | String.t(), keyword()) :: :ok
  def registrar_actividad(cookie, accion, opts \\ []) when is_list(opts) do
    GenServer.cast(servidor(opts), {:registrar_actividad, cookie, accion, Keyword.get(opts, :detalle)})
  end

  @doc "Muestra el historial de eventos."
  @spec historial(keyword()) :: {:ok, [evento()]} | {:error, term()}
  def historial(opts \\ []) when is_list(opts),
    do: llamar({:historial, Keyword.take(opts, [:usuario, :limite])}, opts)

  @doc "Lista las sesiones activas en el sistema."
  @spec conectados(keyword()) ::
          {:ok, [%{nombre_usuario: String.t(), pid: pid(), desde: DateTime.t()}]}
          | {:error, term()}
  def conectados(opts \\ []) when is_list(opts), do: llamar(:conectados, opts)

  @doc "Lista todos los usuarios registrados (solo datos públicos)."
  @spec listar_usuarios(keyword()) :: {:ok, [usuario_publico()]} | {:error, term()}
  def listar_usuarios(opts \\ []) when is_list(opts), do: llamar(:listar_usuarios, opts)

  # Callbacks de GenServer

  @impl true
  def init(opts) do
    with :ok <- Persistencia.inicializar(),
         {:ok, usuarios} <- cargar_usuarios_seguro() do
      {:ok,
       %{
         usuarios: usuarios,
         sesiones: %{},
         historial: [],
         historial_max: positivo(Keyword.get(opts, :historial_max), @historial_max),
         permitir_admin: Keyword.get(opts, :permitir_admin_en_registro, false) == true
       }}
    else
      {:error, razon} ->
        Logger.error("Sesion: no se pudo iniciar la persistencia: #{inspect(razon)}")
        {:stop, {:persistencia, razon}}
    end
  end

  @impl true
  def handle_call({:connect, username, password, opts}, {pid, _tag}, state) do
    case autenticar_o_registrar(username, password, opts, state) do
      {:ok, usuario, nuevo?, state} ->
        {cookie, state} = abrir_sesion(state, usuario.nombre_usuario, pid)

        state =
          if nuevo?,
            do: registrar(state, usuario.nombre_usuario, :registro, nil),
            else: state

        state = registrar(state, usuario.nombre_usuario, :connect, nil)

        {:reply, {:ok, %{cookie: cookie, usuario: publico(usuario), nuevo: nuevo?}}, state}

      {:error, razon, state} ->
        {:reply, {:error, razon}, state}
    end
  end

  def handle_call({:disconnect, cookie}, _from, state) do
    case Map.pop(state.sesiones, cookie) do
      {nil, _} ->
        {:reply, {:error, :sesion_invalida}, state}

      {sesion, sesiones} ->
        Process.demonitor(sesion.ref, [:flush])
        state = registrar(%{state | sesiones: sesiones}, sesion.username, :disconnect, nil)
        {:reply, :ok, state}
    end
  end

  def handle_call({:usuario_actual, cookie}, _from, state) do
    case usuario_de_cookie(state, cookie) do
      {:ok, usuario} -> {:reply, {:ok, publico(usuario)}, state}
      {:error, _} = error -> {:reply, error, state}
    end
  end

  def handle_call({:autorizar, cookie, roles}, _from, state) do
    case usuario_de_cookie(state, cookie) do
      {:ok, usuario} ->
        if usuario.rol in roles do
          {:reply, {:ok, publico(usuario)}, state}
        else
          state = registrar(state, usuario.nombre_usuario, :acceso_denegado, nil)
          {:reply, {:error, :no_autorizado}, state}
        end

      {:error, _} = error ->
        {:reply, error, state}
    end
  end

  def handle_call({:historial, opts}, _from, state) do
    limite = positivo(Keyword.get(opts, :limite), @limite_historial)

    eventos =
      case Keyword.get(opts, :usuario) do
        nil -> state.historial
        usuario -> Enum.filter(state.historial, &(&1.usuario == usuario))
      end

    {:reply, {:ok, Enum.take(eventos, limite)}, state}
  end

  def handle_call(:conectados, _from, state) do
    lista =
      state.sesiones
      |> Map.values()
      |> Enum.sort_by(& &1.desde, DateTime)
      |> Enum.map(&%{nombre_usuario: &1.username, pid: &1.pid, desde: &1.desde})

    {:reply, {:ok, lista}, state}
  end

  def handle_call(:listar_usuarios, _from, state) do
    lista =
      state.usuarios
      |> Map.values()
      |> Enum.sort_by(& &1.nombre_usuario)
      |> Enum.map(&publico/1)

    {:reply, {:ok, lista}, state}
  end

  def handle_call(_mensaje, _from, state), do: {:reply, {:error, :operacion_desconocida}, state}

  @impl true
  def handle_cast({:registrar_actividad, cookie, accion, detalle}, state)
      when is_atom(accion) or is_binary(accion) do
    case Map.fetch(state.sesiones, cookie) do
      {:ok, %{username: username}} -> {:noreply, registrar(state, username, accion, detalle)}
      :error -> {:noreply, state}
    end
  end

  def handle_cast(_mensaje, state), do: {:noreply, state}

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _razon}, state) do
    case Enum.find(state.sesiones, fn {_cookie, sesion} -> sesion.ref == ref end) do
      {cookie, sesion} ->
        state = %{state | sesiones: Map.delete(state.sesiones, cookie)}
        {:noreply, registrar(state, sesion.username, :desconexion_automatica, nil)}

      nil ->
        {:noreply, state}
    end
  end

  def handle_info(_mensaje, state), do: {:noreply, state}

  # Funciones Privadas

  defp autenticar_o_registrar(username, password, opts, state) do
    with {:ok, username} <- Catalogos.validar_texto(username, :nombre_usuario),
         {:ok, password} <- Catalogos.validar_texto(password, :password) do
      case Map.fetch(state.usuarios, username) do
        {:ok, usuario} -> autenticar(usuario, password, state)
        :error -> registrar_usuario(username, password, opts, state)
      end
    else
      {:error, razon} -> {:error, razon, state}
    end
  rescue
    excepcion ->
      Logger.error("Sesion: error inesperado en connect: " <> Exception.format(:error, excepcion, __STACKTRACE__))
      {:error, :error_interno, state}
  end

  defp autenticar(usuario, password, state) do
    case Usuario.autenticar(usuario, password) do
      {:ok, usuario} ->
        {:ok, usuario, false, state}

      {:error, razon} ->
        {:error, razon, registrar(state, usuario.nombre_usuario, :login_fallido, nil)}
    end
  end

  defp registrar_usuario(username, password, opts, state) do
    zona = Keyword.get(opts, :zona, @zona_por_defecto)
    nombre = Keyword.get(opts, :nombre_completo, username)

    with {:ok, rol} <- Catalogos.parse_rol(Keyword.get(opts, :rol, :ciudadano)),
         :ok <- validar_rol_permitido(rol, state),
         {:ok, usuario} <- Usuario.new(username, password, nombre, rol, zona),
         usuarios = Map.put(state.usuarios, username, usuario),
         :ok <- persistir(usuarios) do
      {:ok, usuario, true, %{state | usuarios: usuarios}}
    else
      {:error, razon} -> {:error, razon, state}
    end
  end

  defp validar_rol_permitido(:administrador, %{permitir_admin: false}),
    do: {:error, :rol_no_permitido}

  defp validar_rol_permitido(_rol, _state), do: :ok

  defp persistir(usuarios) do
    case Persistencia.guardar_usuarios(usuarios) do
      :ok -> :ok
      {:error, causa} -> {:error, {:persistencia, causa}}
    end
  end

  defp cargar_usuarios_seguro do
    case Persistencia.cargar_usuarios() do
      {:ok, usuarios} ->
        {:ok, usuarios}

      {:error, {:archivo_corrupto, ruta, errores}} ->
        Logger.error("Sesion: archivo de usuarios corrupto (#{ruta}): #{inspect(errores)}")

        case Persistencia.poner_en_cuarentena(:usuarios) do
          {:ok, destino} ->
            Logger.warning("Sesion: archivo corrupto movido a #{destino}; se inicia sin usuarios")
            {:ok, %{}}

          {:error, _} = error ->
            error
        end

      {:error, _} = error ->
        error
    end
  end

  defp abrir_sesion(state, username, pid) do
    cookie = :crypto.strong_rand_bytes(24) |> Base.url_encode64(padding: false)
    ref = Process.monitor(pid)
    sesion = %{username: username, pid: pid, ref: ref, desde: DateTime.utc_now()}
    {cookie, %{state | sesiones: Map.put(state.sesiones, cookie, sesion)}}
  end

  defp usuario_de_cookie(state, cookie) do
    with {:ok, %{username: username}} <- Map.fetch(state.sesiones, cookie),
         {:ok, usuario} <- Map.fetch(state.usuarios, username) do
      {:ok, usuario}
    else
      :error -> {:error, :sesion_invalida}
    end
  end

  defp registrar(state, username, accion, detalle) do
    evento = %{
      en: DateTime.utc_now(),
      usuario: username,
      accion: accion,
      detalle: normalizar_detalle(detalle)
    }

    %{state | historial: Enum.take([evento | state.historial], state.historial_max)}
  end

  defp normalizar_detalle(nil), do: nil
  defp normalizar_detalle(detalle) when is_binary(detalle), do: String.slice(detalle, 0, 500)
  defp normalizar_detalle(detalle), do: inspect(detalle, limit: 20, printable_limit: 200)

  defp publico(%Usuario{} = usuario) do
    %{
      nombre_usuario: usuario.nombre_usuario,
      nombre_completo: usuario.nombre_completo,
      rol: usuario.rol,
      zona_principal: usuario.zona_principal
    }
  end

  defp positivo(valor, _defecto) when is_integer(valor) and valor > 0, do: valor
  defp positivo(_valor, defecto), do: defecto

  defp servidor(opts), do: Keyword.get(opts, :servidor, __MODULE__)

  defp llamar(mensaje, opts) do
    GenServer.call(servidor(opts), mensaje, @timeout)
  catch
    :exit, {:timeout, _} -> {:error, :timeout}
    :exit, _ -> {:error, :servidor_no_disponible}
  end
end
