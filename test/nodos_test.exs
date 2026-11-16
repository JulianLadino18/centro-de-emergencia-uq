# Pruebas de la fachada del nodo servidor: recorre todos los comandos del
# cliente sobre GenServer + Sesión reales, pero sin distribución.
# Ejecutar desde la raíz del proyecto:
#     elixir test/nodos_test.exs

raiz = Path.expand("..", __DIR__)

Code.require_file("servidor/util.ex", raiz)
Code.require_file("servidor/cookie.exs", raiz)
Code.require_file("lib/emergencia/modelos.ex", raiz)
Code.require_file("lib/emergencia/persistencia.ex", raiz)
Code.require_file("lib/emergencia/zonas.ex", raiz)
Code.require_file("lib/emergencia/ciudadanos.ex", raiz)
Code.require_file("lib/emergencia/necesidades.ex", raiz)
Code.require_file("lib/emergencia/recursos.ex", raiz)
Code.require_file("lib/emergencia/albergues.ex", raiz)
Code.require_file("lib/emergencia/mascotas.ex", raiz)
Code.require_file("lib/emergencia/sesion.ex", raiz)
Code.require_file("lib/emergencia/server.ex", raiz)
Code.require_file("lib/emergencia/supervisor.ex", raiz)
Code.require_file("lib/emergencia/nodo_servidor.ex", raiz)
Code.require_file("cliente/util.ex", raiz)

ExUnit.start(autorun: true)

defmodule NodoServidorTest do
  use ExUnit.Case, async: false

  alias Emergencia.NodoServidor

  setup do
    dir = Path.join(System.tmp_dir!(), "emergencia_nodo_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    Application.put_env(:emergencia, :persistencia, directorio: dir)

    {:ok, sup} = Emergencia.Supervisor.start_link(directorio: dir, name: nil)
    {:ok, nodo} = NodoServidor.start_link(name: nil)

    on_exit(fn ->
      Application.delete_env(:emergencia, :persistencia)
      detener(nodo)
      detener(sup)
      File.rm_rf!(dir)
    end)

    %{dir: dir, nodo: nodo, sup: sup}
  end

  # ---------- Conexión y sesión ----------

  test "connect inicia sesión y devuelve la cookie", %{nodo: nodo} do
    assert {:ok, texto, %{cookie: cookie}} =
             cmd(nodo, "connect", ["laura", "1234", "coordinador", "centro"])

    assert texto =~ "laura"
    assert texto =~ "coordinador"
    assert is_binary(cookie) and cookie != ""

    assert {:error, texto} = cmd(nodo, "connect", ["laura", "incorrecta"])
    assert texto =~ "contraseña"
  end

  test "sin sesión no se pueden ejecutar comandos", %{nodo: nodo} do
    assert {:error, texto} = cmd(nodo, "summary")
    assert texto =~ "sesión"
    assert texto =~ "connect"
  end

  test "los roles limitan los comandos de escritura", %{nodo: nodo} do
    cookie = conectar(nodo, "ciudadano", "pedro")

    assert {:error, texto} = cmd(nodo, "register_zone", ["Z1", "Centro", "alto"], cookie)
    assert texto =~ "permisos"

    assert {:error, texto} = cmd(nodo, "register_shelter", ["A01", "Norte", "Z1", "5"], cookie)
    assert texto =~ "permisos"

    # Las consultas sí están permitidas
    assert {:ok, _texto} = cmd(nodo, "zones_summary", [], cookie)
  end

  test "disconnect cierra la sesión", %{nodo: nodo} do
    cookie = conectar(nodo, "coordinador")

    assert {:ok, texto, %{cerrar_sesion: true}} = cmd(nodo, "disconnect", [], cookie)
    assert texto =~ "cerrada"

    assert {:error, texto} = cmd(nodo, "summary", [], cookie)
    assert texto =~ "inválida"
  end

  # ---------- Zonas ----------

  test "register_zone, zone_status y zones_summary", %{nodo: nodo, dir: dir} do
    cookie = conectar(nodo, "coordinador")

    assert {:ok, texto} = cmd(nodo, "register_zone", ["Z1", "Centro", "alto", "120"], cookie)
    assert texto =~ "Z1"
    assert texto =~ "Afectados: 120"

    assert {:ok, texto} = cmd(nodo, "zone_status", ["Z1"], cookie)
    assert texto =~ "Centro"
    assert texto =~ "Nivel: alto"

    assert {:ok, texto} = cmd(nodo, "zones_summary", [], cookie)
    assert texto =~ "Zonas: 1"
    assert texto =~ "Nivel máximo: alto"

    assert {:error, texto} = cmd(nodo, "register_zone", ["Z1", "Otro", "bajo"], cookie)
    assert texto =~ "duplicado"

    assert File.read!(Path.join(dir, "zonas.txt")) =~ "Z1"
  end

  test "register_sector y register_point", %{nodo: nodo} do
    cookie = conectar(nodo, "coordinador")
    cmd(nodo, "register_zone", ["Z1", "Centro", "alto"], cookie)

    assert {:ok, texto} = cmd(nodo, "register_sector", ["Z1", "S1", "Sector Norte"], cookie)
    assert texto =~ "S1"

    assert {:ok, texto} = cmd(nodo, "register_sector", ["Z1", "S2", "Sector Sur", "critico"], cookie)
    assert texto =~ "critico"

    assert {:ok, texto} = cmd(nodo, "register_point", ["Z1", "S1", "P1", "Punto 1"], cookie)
    assert texto =~ "P1"

    assert {:ok, texto} = cmd(nodo, "zone_status", ["Z1"], cookie)
    assert texto =~ "Puntos: 1"
    assert texto =~ "Sector Norte"
  end

  # ---------- Personas y mensajería ----------

  test "report_person, find_person y list_people", %{nodo: nodo} do
    cookie = conectar(nodo, "coordinador")

    assert {:ok, texto} = cmd(nodo, "report_person", ["DOC100", "Ana", "32", "Z1", "reportada"], cookie)
    assert texto =~ "DOC100"

    assert {:ok, _texto} = cmd(nodo, "report_person", ["DOC200", "Luis", "Z1", "sin_informacion"], cookie)

    assert {:ok, texto} = cmd(nodo, "find_person", ["DOC100"], cookie)
    assert texto =~ "Ana"

    assert {:ok, texto} = cmd(nodo, "find_person", ["nombre=luis"], cookie)
    assert texto =~ "Luis"

    assert {:ok, texto} = cmd(nodo, "list_people", [], cookie)
    assert texto =~ "Personas registradas: 2"

    assert {:error, texto} = cmd(nodo, "report_person", ["DOC100", "Otra", "Z1", "reportada"], cookie)
    assert texto =~ "documento"
  end

  test "change_person_status valida las transiciones", %{nodo: nodo} do
    cookie = conectar(nodo, "coordinador")
    cmd(nodo, "report_person", ["DOC100", "Ana", "32", "Z1", "reportada"], cookie)

    assert {:ok, texto} = cmd(nodo, "change_person_status", ["DOC100", "localizada"], cookie)
    assert texto =~ "localizada"

    assert {:error, texto} = cmd(nodo, "change_person_status", ["DOC100", "sin_informacion"], cookie)
    assert texto =~ "No se puede pasar a ese estado"
  end

  test "send_family_message y list_family_messages", %{nodo: nodo} do
    cookie = conectar(nodo, "coordinador")
    cmd(nodo, "report_person", ["DOC300", "Marta", "40", "Z1", "reportada"], cookie)

    assert {:ok, texto} = cmd(nodo, "send_family_message", ["DOC300", "Estoy", "bien"], cookie)
    assert texto =~ "Mensaje enviado"

    assert {:ok, texto} = cmd(nodo, "list_family_messages", ["DOC300"], cookie)
    assert texto =~ "Estoy bien"

    assert {:error, texto} = cmd(nodo, "send_family_message", ["DOC999", "hola"], cookie)
    assert texto =~ "destinatario"
  end

  # ---------- Recursos ----------

  test "registro, listado y movimientos de recursos", %{nodo: nodo} do
    cookie = conectar(nodo, "coordinador")

    assert {:ok, texto} =
             cmd(nodo, "register_resource", ["R001", "agua", "agua", "50", "litros", "acopio1"], cookie)

    assert texto =~ "R001"
    assert texto =~ "50 litros"

    assert {:ok, texto} = cmd(nodo, "list_resources", ["categoria=agua"], cookie)
    assert texto =~ "Recursos: 1"

    assert {:ok, texto} = cmd(nodo, "resource_entry", ["R001", "acopio1", "10"], cookie)
    assert texto =~ "60 litros"

    assert {:ok, texto} = cmd(nodo, "resource_exit", ["R001", "acopio1", "5"], cookie)
    assert texto =~ "55 litros"

    assert {:error, texto} = cmd(nodo, "resource_exit", ["R001", "acopio1", "999"], cookie)
    assert texto =~ "insuficiente"
  end

  test "transfer_resource mueve cantidad entre centros", %{nodo: nodo} do
    cookie = conectar(nodo, "coordinador")
    cmd(nodo, "register_resource", ["R001", "agua", "agua", "50", "litros", "acopio1"], cookie)

    assert {:ok, texto} =
             cmd(nodo, "transfer_resource", ["R001", "acopio1", "acopio2", "20"], cookie)

    assert texto =~ "acopio1"
    assert texto =~ "acopio2"
    assert texto =~ "30 litros"
    assert texto =~ "20 litros"
  end

  test "critical_resources filtra por umbral", %{nodo: nodo} do
    cookie = conectar(nodo, "coordinador")
    cmd(nodo, "register_resource", ["R001", "agua", "agua", "5", "litros", "acopio1"], cookie)

    assert {:ok, texto} = cmd(nodo, "critical_resources", ["10"], cookie)
    assert texto =~ "Recursos críticos (<= 10): 1"

    assert {:error, texto} = cmd(nodo, "critical_resources", ["abc"], cookie)
    assert texto =~ "entero"
  end

  # ---------- Necesidades ----------

  test "necesidades: registro, filtros, pendientes y asignación", %{nodo: nodo} do
    cookie = conectar(nodo, "coordinador")
    cmd(nodo, "register_resource", ["R001", "agua", "agua", "200", "litros", "acopio1"], cookie)

    assert {:ok, texto} = cmd(nodo, "register_need", ["agua", "100", "critica", "Z1", "Sector 3"], cookie)
    assert texto =~ "N001"
    assert texto =~ "Estado: pendiente"
    assert texto =~ "Sector 3"

    assert {:ok, texto} = cmd(nodo, "list_needs", ["tipo=agua"], cookie)
    assert texto =~ "Necesidades: 1"

    assert {:ok, texto} = cmd(nodo, "pending_needs", [], cookie)
    assert texto =~ "Pendientes: 1"

    assert {:ok, texto} = cmd(nodo, "assign_resource", ["N001", "agua", "40"], cookie)
    assert texto =~ "Asignado: 40"

    assert {:error, texto} = cmd(nodo, "assign_resource", ["N999", "agua", "1"], cookie)
    assert texto =~ "no encontrada"
  end

  # ---------- Albergues ----------

  test "albergues: capacidad, ingresos, salidas y reporte", %{nodo: nodo} do
    cookie = conectar(nodo, "coordinador")

    assert {:ok, texto} = cmd(nodo, "register_shelter", ["A01", "Norte", "Z1", "2"], cookie)
    assert texto =~ "Capacidad: 2"

    assert {:ok, texto} = cmd(nodo, "check_shelter", ["A01"], cookie)
    assert texto =~ "Cupos: 2"

    assert {:ok, _texto} = cmd(nodo, "register_entry", ["A01", "D1"], cookie)
    assert {:ok, _texto} = cmd(nodo, "register_entry", ["A01", "D2"], cookie)

    assert {:error, texto} = cmd(nodo, "register_entry", ["A01", "D3"], cookie)
    assert texto =~ "cupos"

    assert {:ok, texto} = cmd(nodo, "register_exit", ["A01", "D1"], cookie)
    assert texto =~ "Ocupantes: 1"

    assert {:ok, texto} = cmd(nodo, "shelter_report", [], cookie)
    assert texto =~ "Albergues: 1"
    assert texto =~ "50.0%"
  end

  # ---------- Mascotas ----------

  test "mascotas: reportes, emparejamiento y confirmación", %{nodo: nodo} do
    cookie = conectar(nodo, "coordinador")

    assert {:ok, texto} =
             cmd(
               nodo,
               "report_pet",
               ["perdida", "perro", "Luna", "collar rojo", "negra", "mediana", "Z1", "300123"],
               cookie
             )

    assert texto =~ "M001"

    assert {:ok, texto} =
             cmd(
               nodo,
               "report_pet",
               ["encontrada", "perro", "Desconocida", "collar rojo", "negra", "mediana", "Z1", "300456"],
               cookie
             )

    assert texto =~ "M002"

    assert {:ok, texto} = cmd(nodo, "list_pets", ["tipo=perdida"], cookie)
    assert texto =~ "Reportes de mascotas: 1"

    assert {:ok, texto} = cmd(nodo, "match_pets", [], cookie)
    assert texto =~ "M001"
    assert texto =~ "puntaje 100"

    assert {:ok, texto} = cmd(nodo, "confirm_match", ["M001", "M002"], cookie)
    assert texto =~ "resueltas"

    assert {:error, texto} = cmd(nodo, "confirm_match", ["M001", "M002"], cookie)
    assert texto =~ "resuelto"
  end

  # ---------- Resumen, ayuda y errores ----------

  test "summary reúne el estado global", %{nodo: nodo} do
    cookie = conectar(nodo, "coordinador")
    cmd(nodo, "register_shelter", ["A01", "Norte", "Z1", "2"], cookie)

    assert {:ok, texto} = cmd(nodo, "summary", [], cookie)
    assert texto =~ "Personas:"
    assert texto =~ "Albergues: 1"
    assert texto =~ "Mascotas:"
  end

  test "help lista los comandos", %{nodo: nodo} do
    cookie = conectar(nodo, "coordinador")

    assert {:ok, texto} = cmd(nodo, "help", [], cookie)
    assert texto =~ "register_shelter"
    assert texto =~ "summary"
  end

  test "filtros y comandos inválidos", %{nodo: nodo} do
    cookie = conectar(nodo, "coordinador")

    assert {:error, texto} = cmd(nodo, "list_needs", ["color=rojo"], cookie)
    assert texto =~ "Filtro desconocido"

    assert {:error, texto} = cmd(nodo, "volando", [], cookie)
    assert texto =~ "Comando desconocido"

    assert {:error, texto} = cmd(nodo, "register_zone", ["Z1", "Centro"], cookie)
    assert texto =~ "Uso:"
  end

  # ---------- Persistencia ----------

  test "zonas y albergues sobreviven al reinicio", %{nodo: nodo, sup: sup, dir: dir} do
    cookie = conectar(nodo, "coordinador")
    cmd(nodo, "register_zone", ["Z9", "Nueva", "alto"], cookie)
    cmd(nodo, "register_shelter", ["A09", "Nuevo", "Z9", "5"], cookie)

    GenServer.stop(nodo)
    Supervisor.stop(sup)

    {:ok, sup2} = Emergencia.Supervisor.start_link(directorio: dir, name: nil)
    {:ok, nodo2} = NodoServidor.start_link(name: nil)

    {:ok, _texto, %{cookie: cookie2}} = cmd(nodo2, "connect", ["ana", "1", "coordinador", "Z9"])

    assert {:ok, texto} = cmd(nodo2, "zone_status", ["Z9"], cookie2)
    assert texto =~ "Nueva"

    assert {:ok, texto} = cmd(nodo2, "check_shelter", ["A09"], cookie2)
    assert texto =~ "Nuevo"

    GenServer.stop(nodo2)
    Supervisor.stop(sup2)
  end

  # ---------- Utilidades del cliente ----------

  test "utilidades del cliente" do
    assert {["summary"], []} == Emergencia.Cliente.Util.separar_filtros(["summary"])
    assert {[], ["zona=Z1"]} == Emergencia.Cliente.Util.separar_filtros(["zona=Z1"])
    assert Emergencia.Cliente.Util.normalizar_prioridad("crítica") == "critica"
    assert Emergencia.Cliente.Util.normalizar_nivel("CRÍTICO") == "critico"
    assert Emergencia.Cliente.Util.normalizar_tipo_mascota("lost") == "perdida"
    assert Emergencia.Cliente.Util.normalizar_tipo_mascota("found") == "encontrada"
  end

  # ---------- Helpers ----------

  defp cmd(nodo, comando, args \\ [], cookie \\ nil) do
    NodoServidor.comando(comando, args, cookie, nodo)
  end

  defp conectar(nodo, rol, nombre \\ "laura") do
    assert {:ok, _texto, %{cookie: cookie}} = cmd(nodo, "connect", [nombre, "1234", rol, "Z1"])
    cookie
  end

  defp detener(proceso) do
    if Process.alive?(proceso) do
      try do
        GenServer.stop(proceso)
      catch
        :exit, _ -> :ok
      end
    end
  end
end
