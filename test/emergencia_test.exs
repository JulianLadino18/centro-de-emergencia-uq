# Pruebas de albergues, mascotas, servidor GenServer y supervisor OTP.
# Ejecutar desde la raíz del proyecto:
#     elixir test/emergencia_test.exs

raiz = Path.expand("..", __DIR__)

Code.require_file("servidor/util.ex", raiz)
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

ExUnit.start(autorun: true)

defmodule EmergenciaTest do
  use ExUnit.Case, async: false

  alias Emergencia.{Albergues, Mascotas, Persistencia}

  # ============================================================== Albergues

  describe "Albergues: registro y validaciones" do
    test "registra un albergue y rechaza códigos duplicados" do
      assert {:ok, albergue, lista} = Albergues.registrar([], "a01", "Albergue Norte", "Z1", 10)
      assert albergue.codigo == "A01"
      assert albergue.capacidad == 10
      assert albergue.ocupantes == []
      assert length(lista) == 1

      assert {:error, :albergue_duplicado} =
               Albergues.registrar(lista, "A01", "Otro", "Z2", 5)
    end

    test "valida campos y capacidad" do
      assert {:error, :campo_vacio} = Albergues.registrar([], "", "N", "Z1", 5)
      assert {:error, :campo_vacio} = Albergues.registrar([], "A1", " ", "Z1", 5)
      assert {:error, :campo_vacio} = Albergues.registrar([], "A1", "N", "", 5)
      assert {:error, :capacidad_invalida} = Albergues.registrar([], "A1", "N", "Z1", 0)
      assert {:error, :capacidad_invalida} = Albergues.registrar([], "A1", "N", "Z1", "mucho")
      assert {:error, :capacidad_negativa} = Albergues.registrar([], "A1", "N", "Z1", -1)
    end
  end

  describe "Albergues: entradas, salidas y cupos" do
    setup do
      {:ok, _, albergues} = Albergues.registrar([], "A01", "Norte", "Z1", 2)
      %{albergues: albergues}
    end

    test "registra ocupantes mientras haya cupo", %{albergues: albergues} do
      assert {:ok, albergue, albergues} = Albergues.registrar_entrada(albergues, "A01", "DOC1")
      assert albergue.ocupantes == ["DOC1"]
      assert Albergues.cupos_disponibles(albergue) == 1

      assert {:ok, albergue, albergues} = Albergues.registrar_entrada(albergues, "A01", "DOC2")
      assert Albergues.cupos_disponibles(albergue) == 0

      assert {:error, :capacidad_excedida} =
               Albergues.registrar_entrada(albergues, "A01", "DOC3")
    end

    test "no repite ocupante y valida documento y albergue" do
      {:ok, _, albergues} = Albergues.registrar_entrada(albergues_base(), "A01", "DOC1")

      assert {:error, :ocupante_duplicado} =
               Albergues.registrar_entrada(albergues, "A01", "doc1")

      assert {:error, :campo_vacio} = Albergues.registrar_entrada(albergues, "A01", "  ")

      assert {:error, :albergue_no_encontrado} =
               Albergues.registrar_entrada(albergues, "A99", "DOC1")
    end

    test "registrar_salida libera cupo", %{albergues: albergues} do
      {:ok, _, albergues} = Albergues.registrar_entrada(albergues, "A01", "DOC1")

      assert {:ok, albergue, albergues} = Albergues.registrar_salida(albergues, "A01", "DOC1")
      assert albergue.ocupantes == []
      assert Albergues.cupos_disponibles(albergue) == 2

      assert {:error, :ocupante_no_encontrado} =
               Albergues.registrar_salida(albergues, "A01", "DOC1")
    end
  end

  describe "Albergues: funciones recursivas y reportes" do
    setup do
      {:ok, _, albergues} = Albergues.registrar([], "A01", "Norte", "Z1", 10)
      {:ok, _, albergues} = Albergues.registrar(albergues, "A02", "Sur", "Z2", 20)
      {:ok, _, albergues} = Albergues.registrar_entrada(albergues, "A01", "D1")
      {:ok, _, albergues} = Albergues.registrar_entrada(albergues, "A01", "D2")
      {:ok, _, albergues} = Albergues.registrar_entrada(albergues, "A02", "D3")
      %{albergues: albergues}
    end

    test "contar_ocupantes/1 recursivo", %{albergues: albergues} do
      assert Albergues.contar_ocupantes(albergues) == 3
      assert Albergues.contar_ocupantes([]) == 0
      [primero | _] = albergues
      assert Albergues.contar_ocupantes(primero) == 2
    end

    test "cupos_disponibles/1 recursivo", %{albergues: albergues} do
      assert Albergues.cupos_disponibles(albergues) == 27
      assert Albergues.cupos_disponibles([]) == 0
    end

    test "totales/3 y totales/1", %{albergues: albergues} do
      assert Albergues.totales(albergues, 0, 0) == {30, 3}
      assert Albergues.totales(albergues) == %{capacidad: 30, ocupacion: 3, disponibles: 27}
    end

    test "porcentaje_ocupacion/1", %{albergues: albergues} do
      assert Albergues.porcentaje_ocupacion(albergues) == 10.0
      assert Albergues.porcentaje_ocupacion([]) == 0.0
    end

    test "reporte/1 y texto_albergue/1", %{albergues: albergues} do
      reporte = Albergues.reporte(albergues)
      assert reporte.total_albergues == 2
      assert reporte.capacidad == 30
      assert reporte.ocupacion == 3
      assert reporte.disponibles == 27
      assert reporte.porcentaje == 10.0
      assert length(reporte.detalle) == 2
      assert Albergues.texto_albergue(hd(albergues)) =~ "A01"
    end

    test "mensaje_error/1" do
      assert Albergues.mensaje_error(:capacidad_excedida) =~ "cupos"
      assert Albergues.mensaje_error(:albergue_no_encontrado) =~ "Albergue"
    end
  end

  describe "Albergues: persistencia" do
    test "ciclo línea -> estructura" do
      {:ok, _, albergues} = Albergues.registrar([], "A01", "Norte", "Z1", 2)
      {:ok, _, albergues} = Albergues.registrar_entrada(albergues, "A01", "D1")

      assert albergues ==
               albergues |> Albergues.a_lineas() |> Albergues.desde_lineas()
    end

    test "lee el formato existente de data/shelters.txt" do
      linea = "A|A01|Albergue Norte|Z1|2|2|DOC100,DOC200"
      assert {:ok, albergue} = Albergues.desde_linea(linea)
      assert albergue.capacidad == 2
      assert albergue.ocupantes == ["DOC100", "DOC200"]
      assert Albergues.cupos_disponibles(albergue) == 0
    end

    test "ignora líneas inválidas" do
      assert {:error, :linea_invalida} = Albergues.desde_linea("basura")
      assert [] == Albergues.desde_lineas(["", "basura", "A|A1|N|Z|mal|0|"])
    end
  end

  # =============================================================== Mascotas

  describe "Mascotas: reportes y validaciones" do
    test "reporta mascotas perdidas y encontradas con IDs en orden" do
      assert {:ok, mascota, lista} =
               Mascotas.reportar([], "perdida", "perro", "Luna", "collar rojo", "negra", "mediana", "Z1", "300")

      assert mascota.id == "M001"
      assert mascota.tipo == :perdida
      assert mascota.estado == :abierta

      assert {:ok, segunda, lista} =
               Mascotas.reportar(lista, "encontrada", "perro", "", "", "negra", "mediana", "Z1", "301")

      assert segunda.id == "M002"
      assert segunda.nombre == "Desconocida"
      assert length(lista) == 2
    end

    test "acepta lost/found y rechaza tipo inválido" do
      assert {:ok, %{tipo: :perdida}, _} =
               Mascotas.reportar([], "lost", "gato", "Michi", "", "gris", "pequeño", "Z2", "")

      assert {:ok, %{tipo: :encontrada}, _} =
               Mascotas.reportar([], "found", "gato", "Michi", "", "gris", "pequeño", "Z2", "")

      assert {:error, :tipo_invalido} =
               Mascotas.reportar([], "otro", "gato", "Michi", "", "gris", "pequeño", "Z2", "")
    end

    test "valida campos obligatorios" do
      assert {:error, :campo_vacio} =
               Mascotas.reportar([], "perdida", "", "Luna", "", "negra", "mediana", "Z1", "")

      assert {:error, :campo_vacio} =
               Mascotas.reportar([], "perdida", "perro", "Luna", "", "", "mediana", "Z1", "")

      assert {:error, :campo_vacio} =
               Mascotas.reportar([], "perdida", "perro", "Luna", "", "negra", "", "Z1", "")

      assert {:error, :campo_vacio} =
               Mascotas.reportar([], "perdida", "perro", "Luna", "", "negra", "mediana", "", "")
    end

    test "convertir_tipo/1 y convertir_estado/1" do
      assert Mascotas.convertir_tipo("perdido") == :perdida
      assert Mascotas.convertir_tipo("encontrado") == :encontrada
      assert Mascotas.convertir_tipo("x") == :error
      assert Mascotas.convertir_estado("resuelto") == :resuelta
      assert Mascotas.convertir_estado("abierta") == :abierta
      assert Mascotas.convertir_estado("x") == :error
    end
  end

  describe "Mascotas: puntaje de similitud" do
    setup do
      {:ok, perdida, lista} =
        Mascotas.reportar([], "perdida", "perro", "Luna", "collar rojo", "negra", "mediana", "Z1", "300")

      {:ok, encontrada, _} =
        Mascotas.reportar(lista, "encontrada", "perro", "X", "collar rojo", "negra", "mediana", "Z1", "301")

      %{perdida: perdida, encontrada: encontrada}
    end

    test "puntaje máximo 100 cuando coincide todo", %{perdida: perdida, encontrada: encontrada} do
      assert Mascotas.puntaje(perdida, encontrada) == 100
      assert Mascotas.coincidencia?(perdida, encontrada)
    end

    test "coincidencia?/2 respeta el umbral mínimo de 30", %{perdida: perdida} do
      {:ok, solo_especie, _} =
        Mascotas.reportar([], "encontrada", "perro", "X", "", "blanca", "grande", "Z9", "")

      assert Mascotas.puntaje(perdida, solo_especie) == 30
      assert Mascotas.coincidencia?(perdida, solo_especie)

      {:ok, solo_color, _} =
        Mascotas.reportar([], "encontrada", "gato", "X", "", "negra", "grande", "Z9", "")

      assert Mascotas.puntaje(perdida, solo_color) == 25
      refute Mascotas.coincidencia?(perdida, solo_color)
    end

    test "no considera coincidencia entre reportes del mismo tipo", %{perdida: perdida, encontrada: encontrada} do
      {:ok, otra_perdida, _} =
        Mascotas.reportar([], "perdida", "perro", "Otra", "collar rojo", "negra", "mediana", "Z1", "302")

      refute Mascotas.coincidencia?(perdida, otra_perdida)
      assert Mascotas.coincidencia?(perdida, encontrada)
    end

    test "las características coinciden parcialmente sobre palabras" do
      {:ok, perdida, lista} =
        Mascotas.reportar([], "perdida", "perro", "Luna", "collar rojo con placa", "negra", "mediana", "Z1", "")

      {:ok, encontrada, _} =
        Mascotas.reportar(lista, "encontrada", "perro", "X", "collar rojo", "negra", "mediana", "Z1", "")

      assert Mascotas.puntaje(perdida, encontrada) == 95
    end
  end

  describe "Mascotas: emparejamiento" do
    setup do
      {:ok, p1, lista} = Mascotas.reportar([], "perdida", "perro", "Luna", "collar rojo", "negra", "mediana", "Z1", "300")
      {:ok, e1, lista} = Mascotas.reportar(lista, "encontrada", "perro", "X", "collar rojo", "negra", "mediana", "Z1", "301")
      {:ok, p2, lista} = Mascotas.reportar(lista, "perdida", "gato", "Michi", "", "gris", "pequeño", "Z2", "302")
      {:ok, e2, lista} = Mascotas.reportar(lista, "encontrada", "gato", "Y", "", "gris", "pequeño", "Z2", "303")

      %{mascotas: lista, p1: p1, e1: e1, p2: p2, e2: e2}
    end

    test "comparar_con_todas/3 filtra por tipo y umbral", %{mascotas: lista, p1: p1, e1: e1} do
      coincidencias = Mascotas.comparar_con_todas(p1, lista, 30)

      assert Enum.any?(coincidencias, fn %{perdida: p, encontrada: e} ->
               p.id == p1.id and e.id == e1.id
             end)

      assert Mascotas.comparar_con_todas(p1, lista, 101) == []
    end

    test "emparejar/2 ordena por puntaje descendente", %{mascotas: lista} do
      coincidencias = Mascotas.emparejar(lista)

      assert length(coincidencias) == 2
      puntajes = Enum.map(coincidencias, & &1.puntaje)
      assert puntajes == Enum.sort(puntajes, :desc)
      assert Enum.all?(coincidencias, &(&1.puntaje >= 30))
    end

    test "emparejar/2 excluye reportes resueltos", %{mascotas: lista, p1: p1, e1: e1} do
      {:ok, _, lista} = Mascotas.confirmar_match(lista, p1.id, e1.id)
      coincidencias = Mascotas.emparejar(lista)

      refute Enum.any?(coincidencias, fn %{perdida: p, encontrada: e} ->
               p.id == p1.id or e.id == e1.id
             end)

      assert length(coincidencias) == 1
    end
  end

  describe "Mascotas: confirmar_match" do
    setup do
      {:ok, perdida, lista} =
        Mascotas.reportar([], "perdida", "perro", "Luna", "collar rojo", "negra", "mediana", "Z1", "300")

      {:ok, encontrada, lista} =
        Mascotas.reportar(lista, "encontrada", "perro", "X", "collar rojo", "negra", "mediana", "Z1", "301")

      %{mascotas: lista, perdida: perdida, encontrada: encontrada}
    end

    test "cierra ambos reportes como resuelta", %{mascotas: lista, perdida: perdida, encontrada: encontrada} do
      assert {:ok, %{perdida: %{estado: :resuelta}, encontrada: %{estado: :resuelta}}, lista} =
               Mascotas.confirmar_match(lista, perdida.id, encontrada.id)

      assert {:ok, %{estado: :resuelta}} = Mascotas.buscar(lista, perdida.id)
      assert {:ok, %{estado: :resuelta}} = Mascotas.buscar(lista, encontrada.id)
    end

    test "no resuelve el mismo reporte dos veces", %{mascotas: lista, perdida: perdida, encontrada: encontrada} do
      {:ok, _, lista} = Mascotas.confirmar_match(lista, perdida.id, encontrada.id)

      assert {:error, :reporte_ya_resuelto} =
               Mascotas.confirmar_match(lista, perdida.id, encontrada.id)

      {:ok, otra, lista} =
        Mascotas.reportar(lista, "encontrada", "perro", "Otra", "", "negra", "mediana", "Z1", "")

      assert {:error, :reporte_ya_resuelto} =
               Mascotas.confirmar_match(lista, perdida.id, otra.id)
    end

    test "rechaza el mismo reporte y tipos incompatibles", %{mascotas: lista, perdida: perdida} do
      assert {:error, :mismo_reporte} = Mascotas.confirmar_match(lista, perdida.id, perdida.id)

      {:ok, otra_perdida, lista} =
        Mascotas.reportar(lista, "perdida", "perro", "Otra", "", "negra", "mediana", "Z1", "")

      assert {:error, :tipos_incompatibles} =
               Mascotas.confirmar_match(lista, perdida.id, otra_perdida.id)
    end
  end

  describe "Mascotas: persistencia" do
    test "ciclo línea -> estructura" do
      {:ok, _, lista} =
        Mascotas.reportar([], "perdida", "perro", "Luna", "collar rojo", "negra", "mediana", "Z1", "300")

      assert lista == lista |> Mascotas.a_lineas() |> Mascotas.desde_lineas()
    end

    test "lee el formato existente de data/pets.txt" do
      linea =
        "MA|M_1794527726322000_488350|encontrada|perro|Desconocida|collar rojo|negra|mediana|Z1|300456|resuelta"

      assert {:ok, mascota} = Mascotas.desde_linea(linea)
      assert mascota.tipo == :encontrada
      assert mascota.estado == :resuelta
      assert mascota.especie == "perro"
    end

    test "ignora líneas inválidas" do
      assert {:error, :linea_invalida} = Mascotas.desde_linea("basura")

      assert [] ==
               Mascotas.desde_lineas([
                 "",
                 "basura",
                 "MA|M1|raro|perro|X|c|negra|mediana|Z1|300|abierta"
               ])
    end

    test "texto_mascota/1 y mensaje_error/1" do
      {:ok, mascota, _} =
        Mascotas.reportar([], "perdida", "perro", "Luna", "collar rojo", "negra", "mediana", "Z1", "300")

      assert Mascotas.texto_mascota(mascota) =~ "Luna"
      assert Mascotas.mensaje_error(:reporte_ya_resuelto) =~ "resuelto"
    end
  end

  # =============================================================== Servidor

  describe "Servidor: GenServer y persistencia" do
    test "registra albergue y persiste en shelters.txt" do
      {pid, directorio} = servidor_temporal()

      assert {:ok, %{codigo: "A01"}} =
               GenServer.call(pid, {:registrar_albergue, "A01", "Norte", "Z1", 2})

      assert {:ok, _} = GenServer.call(pid, {:entrada_albergue, "A01", "D1"})
      assert File.exists?(Path.join(directorio, "shelters.txt"))

      assert File.read!(Path.join(directorio, "shelters.txt")) =~
               "A|A01|Norte|Z1|2|1|D1"
    end

    test "serializa las mutaciones concurrentes de cupos" do
      {pid, _directorio} = servidor_temporal()

      {:ok, _} = GenServer.call(pid, {:registrar_albergue, "A01", "Norte", "Z1", 10})

      resultados =
        1..50
        |> Task.async_stream(
          fn numero -> GenServer.call(pid, {:entrada_albergue, "A01", "D#{numero}"}) end,
          max_concurrency: 20
        )
        |> Enum.map(fn {:ok, resultado} -> resultado end)

      assert Enum.count(resultados, &match?({:ok, _}, &1)) == 10
      assert Enum.count(resultados, &match?({:error, :capacidad_excedida}, &1)) == 40

      {:ok, albergue} = GenServer.call(pid, {:buscar_albergue, "A01"})
      assert length(albergue.ocupantes) == 10
    end

    test "persiste personas y las recarga al reiniciar" do
      {pid, directorio} = servidor_temporal()

      {:ok, _} =
        GenServer.call(pid, {:registrar_persona, "DOC1", "Ana", 30, "Z1", "reportada"})

      assert {:ok, %{documento: "DOC1"}} = GenServer.call(pid, {:buscar_persona, "DOC1"})

      GenServer.stop(pid)

      {:ok, pid2} = Emergencia.Servidor.start_link(directorio: directorio, name: nil)
      assert {:ok, %{documento: "DOC1"}} = GenServer.call(pid2, {:buscar_persona, "DOC1"})
      GenServer.stop(pid2)
    end

    test "asignar_recurso actualiza necesidad y recurso y persiste ambos" do
      {pid, directorio} = servidor_temporal()

      {:ok, _} =
        GenServer.call(pid, {:registrar_recurso, "R001", "agua", "agua", 50, "litros", "acopio1"})

      {:ok, _} =
        GenServer.call(pid, {:registrar_necesidad, "agua", 30, "critica", "Z1", "sector", "laura"})

      assert {:ok, resultado} = GenServer.call(pid, {:asignar_recurso, "N001", "agua", 30})
      assert resultado.necesidad.estado == :asignada
      assert resultado.necesidad.asignado == 30

      assert File.read!(Path.join(directorio, "resources.txt")) =~ "R|R001|agua|agua|20"
      assert File.read!(Path.join(directorio, "needs.txt")) =~ "asignada"
    end

    test "resumen global" do
      {pid, _directorio} = servidor_temporal()

      {:ok, _} = GenServer.call(pid, {:registrar_albergue, "A01", "Norte", "Z1", 2})
      {:ok, _} = GenServer.call(pid, {:entrada_albergue, "A01", "D1"})

      resumen = GenServer.call(pid, :resumen)
      assert resumen.albergues == 1
      assert resumen.albergues_totales == %{capacidad: 2, ocupacion: 1, disponibles: 1}
      assert resumen.porcentaje_ocupacion == 50.0
    end
  end

  # =========================================================== Persistencia

  describe "Persistencia: semillas en formato de barras" do
    test "parsea usuarios con y sin prefijo U y valida la contraseña" do
      assert {:ok, laura} =
               Persistencia.deserializar_usuario(
                 "U|laura|1234|coordinador|centro|Laura Gómez"
               )

      assert laura.nombre_usuario == "laura"
      assert laura.nombre_completo == "Laura Gómez"
      assert laura.rol == :coordinador
      assert laura.zona_principal == "centro"
      assert {:ok, _} = Emergencia.Modelos.Usuario.autenticar(laura, "1234")

      assert {:error, :credenciales_invalidas} =
               Emergencia.Modelos.Usuario.autenticar(laura, "incorrecta")

      # También acepta el formato anterior sin prefijo.
      assert {:ok, ana} = Persistencia.deserializar_usuario("ana|1234|ciudadano|sur|Ana")
      assert ana.rol == :ciudadano
      assert ana.zona_principal == "sur"
    end

    test "parsea zonas con y sin sectores" do
      assert {:ok, zona} =
               Persistencia.deserializar_zona(
                 "Z|Z1|Centro|alto|120|S1~Sector Norte^P1~Punto 1~Frente al parque"
               )

      assert zona.codigo == "Z1"
      assert zona.nivel_afectacion == :alto
      assert zona.total_afectados == 120
      assert map_size(zona.sectores) == 1
      assert [punto] = zona.sectores["S1"].puntos_atencion
      assert punto.codigo == "P1"
      assert punto.descripcion == "Frente al parque"

      assert {:ok, simple} = Persistencia.deserializar_zona("Z|Z2|Norte|medio|80")
      assert simple.sectores == %{}
      assert simple.total_afectados == 80
    end

    test "carga los 3 usuarios semilla cuando usuarios.txt está vacío" do
      directorio = directorio_temporal()
      Application.put_env(:emergencia, :persistencia, directorio: directorio)

      on_exit(fn ->
        Application.delete_env(:emergencia, :persistencia)
        File.rm_rf!(directorio)
      end)

      File.write!(Path.join(directorio, "users.txt"), """
      U|laura|1234|coordinador|centro|Laura Gómez
      U|carlos|1234|voluntario|norte|Carlos Pérez
      U|ana|1234|ciudadano|sur|Ana Rodríguez
      """)

      assert :ok = Persistencia.inicializar()
      assert {:ok, usuarios} = Persistencia.cargar_usuarios()

      assert map_size(usuarios) == 3
      assert Map.has_key?(usuarios, "laura")
      assert Map.has_key?(usuarios, "carlos")
      assert Map.has_key?(usuarios, "ana")
    end

    test "el servidor carga las 3 zonas semilla desde zones.txt" do
      directorio = directorio_temporal()

      File.write!(Path.join(directorio, "zones.txt"), """
      Z|Z1|Centro|alto|120|S1~Sector Norte^P1~Punto 1~Frente al parque
      Z|Z2|Norte|medio|80
      Z|Z3|Sur|critico|200
      """)

      {:ok, pid} = Emergencia.Servidor.start_link(directorio: directorio, name: nil)

      on_exit(fn ->
        try do
          if Process.alive?(pid), do: GenServer.stop(pid)
        catch
          :exit, _ -> :ok
        end

        File.rm_rf!(directorio)
      end)

      resumen = GenServer.call(pid, :resumen_zonas)
      assert resumen.total_zonas == 3
      assert resumen.total_sectores == 1
      assert resumen.total_puntos == 1
      assert resumen.total_afectados == 400
      assert resumen.nivel_maximo == {:ok, :critico}

      assert {:ok, zona} = GenServer.call(pid, {:buscar_zona, "Z1"})
      assert zona.nombre == "Centro"
      assert map_size(zona.sectores) == 1
    end
  end

  # ============================================================ Supervisor

  describe "Supervisor OTP" do
    test "usa one_for_one e inicia servidor y sesión" do
      directorio = directorio_temporal()
      Application.put_env(:emergencia, :persistencia, directorio: directorio)

      on_exit(fn ->
        Application.delete_env(:emergencia, :persistencia)
        File.rm_rf!(directorio)
      end)

      {:ok, supervisor} = Emergencia.Supervisor.start_link(directorio: directorio, name: nil)

      on_exit(fn ->
        try do
          if Process.alive?(supervisor), do: Supervisor.stop(supervisor)
        catch
          :exit, _ -> :ok
        end
      end)

      assert Process.whereis(Emergencia.Servidor) != nil
      assert Process.whereis(Emergencia.Sesion) != nil
      assert Supervisor.count_children(supervisor).active == 2
    end
  end

  # ------------------------------------------------------------- Helpers

  defp albergues_base do
    {:ok, _, albergues} = Albergues.registrar([], "A01", "Norte", "Z1", 2)
    albergues
  end

  defp directorio_temporal do
    directorio =
      Path.join(System.tmp_dir!(), "emergencia_test_#{System.unique_integer([:positive])}")

    File.mkdir_p!(directorio)
    directorio
  end

  defp servidor_temporal do
    directorio = directorio_temporal()
    {:ok, pid} = Emergencia.Servidor.start_link(directorio: directorio, name: nil)

    on_exit(fn ->
      try do
        if Process.alive?(pid), do: GenServer.stop(pid)
      catch
        :exit, _ -> :ok
      end

      File.rm_rf!(directorio)
    end)

    {pid, directorio}
  end
end
