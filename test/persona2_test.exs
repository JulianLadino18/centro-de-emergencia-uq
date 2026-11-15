# Pruebas de Persona 2: ciudadanos, necesidades y recursos.
# -version 1.0
# -autor: Daniel Gil
# -fecha: 2026-11-14
#
# Ejecutar desde la raíz del proyecto (la carpeta que tiene main.exs):
#     elixir test/persona2_test.exs

raiz = Path.expand("..", __DIR__)

# Dependencias mínimas (en este proyecto no se usa mix)
Code.require_file("servidor/util.ex", raiz)
Code.require_file("lib/emergencia/ciudadanos.ex", raiz)
Code.require_file("lib/emergencia/recursos.ex", raiz)
Code.require_file("lib/emergencia/necesidades.ex", raiz)

ExUnit.start(autorun: true)

defmodule Persona2Test do
  use ExUnit.Case, async: true

  alias Emergencia.{Ciudadanos, Necesidades, Recursos}

  # ---------------------------------------------------------------- Ciudadanos

  describe "Ciudadanos: registro y estados" do
    test "registra personas con ID en orden y rechaza documentos repetidos" do
      assert {:ok, p1, lista} = Ciudadanos.registrar_persona([], "DOC100", "Andrés", 32, "Z1", "localizada")
      assert p1.id == "P001"
      assert p1.estado == :localizada
      assert {:ok, %{id: "P002"}, lista} = Ciudadanos.registrar_persona(lista, "DOC200", "Marta", "45", "Z1")
      assert {:error, :documento_duplicado} = Ciudadanos.registrar_persona(lista, "doc100", "Otro", 20, "Z2")
      assert length(lista) == 2
    end

    test "valida las entradas antes de modificar el estado" do
      assert {:error, :campo_vacio} = Ciudadanos.registrar_persona([], "D1", "  ", 20, "Z1")
      assert {:error, :campo_vacio} = Ciudadanos.registrar_persona([], "D1", "Ana", 20, nil)
      assert {:error, :edad_negativa} = Ciudadanos.registrar_persona([], "D1", "Ana", -3, "Z1")
      assert {:error, :edad_invalida} = Ciudadanos.registrar_persona([], "D1", "Ana", "abc", "Z1")
      assert {:error, :edad_invalida} = Ciudadanos.registrar_persona([], "D1", "Ana", 500, "Z1")
      assert {:error, :estado_invalido} = Ciudadanos.registrar_persona([], "D1", "Ana", 20, "Z1", "volando")
      assert {:ok, %{edad: nil}, _} = Ciudadanos.registrar_persona([], "D1", "Ana", nil, "Z1")
    end

    test "solo permite transiciones válidas y guarda el historial" do
      {:ok, _, lista} = Ciudadanos.registrar_persona([], "D1", "Ana", 20, "Z1", "reportada")

      assert {:ok, persona, lista} = Ciudadanos.cambiar_estado(lista, "D1", "en albergue")
      assert persona.estado == :en_albergue
      assert {:error, :mismo_estado} = Ciudadanos.cambiar_estado(lista, "D1", "en albergue")
      assert {:ok, _, lista} = Ciudadanos.cambiar_estado(lista, "P001", "reunificada")

      # reunificada es un estado final
      assert {:error, :transicion_invalida} = Ciudadanos.cambiar_estado(lista, "D1", "localizada")
      assert {:error, :estado_invalido} = Ciudadanos.cambiar_estado(lista, "D1", "rara")

      assert {:ok, historial} = Ciudadanos.historial(lista, "D1")
      assert Enum.map(historial, fn {_fecha, estado} -> estado end) == [:reportada, :en_albergue, :reunificada]
      assert {:error, :persona_no_encontrada} = Ciudadanos.cambiar_estado(lista, "nada", "localizada")
    end
  end

  describe "Ciudadanos: búsqueda recursiva" do
    setup do
      {:ok, _, l} = Ciudadanos.registrar_persona([], "D1", "Andrés Gómez", 32, "Z1", "en albergue")
      {:ok, _, l} = Ciudadanos.registrar_persona(l, "D2", "Andrea Ruiz", 28, "Z2", "reportada")
      {:ok, _, l} = Ciudadanos.registrar_persona(l, "D3", "Luis Pérez", 60, "Z1", "reportada")
      %{personas: l}
    end

    test "busca por nombre sin distinguir tildes ni mayúsculas", %{personas: l} do
      assert ["Andrés Gómez"] == l |> Ciudadanos.buscar(nombre: "ANDRES G") |> Enum.map(& &1.nombre)
      assert 2 == l |> Ciudadanos.buscar(nombre: "andre") |> length()
    end

    test "combina varios criterios y conserva el orden", %{personas: l} do
      assert ["D3"] == l |> Ciudadanos.buscar(zona: "z1", estado: "reportada") |> Enum.map(& &1.documento)
      assert ["D1", "D3"] == l |> Ciudadanos.buscar(zona: "Z1") |> Enum.map(& &1.documento)
      assert ["D2"] == l |> Ciudadanos.buscar(documento: "d2") |> Enum.map(& &1.documento)
      assert [] == Ciudadanos.buscar(l, estado: "estado_falso")
      assert [] == Ciudadanos.buscar(l, color: "rojo")
      assert [] == Ciudadanos.buscar([], zona: "Z1")
      assert length(Ciudadanos.buscar(l, [])) == 3
    end

    test "cuenta por estado", %{personas: l} do
      assert %{en_albergue: 1, reportada: 2} == Ciudadanos.contar_por_estado(l)
    end
  end

  describe "Ciudadanos: mensajería" do
    setup do
      {:ok, _, l} = Ciudadanos.registrar_persona([], "DOC100", "Andrés", 32, "Z1", "localizada")
      %{personas: l}
    end

    test "registra mensajes, los lista y cambia su estado", %{personas: personas} do
      assert {:ok, m, mensajes} =
               Ciudadanos.enviar_mensaje([], personas, "familiar", "DOC100", "Estoy bien | en el albergue")

      assert m.id == "MSG001"
      assert m.estado == :pendiente
      refute String.contains?(m.contenido, "|")

      assert {:ok, %{estado: :entregado}, mensajes} = Ciudadanos.marcar_mensaje(mensajes, "MSG001", "entregado")
      assert [%{estado: :entregado}] = Ciudadanos.listar_mensajes(mensajes, "doc100")
      assert [] == Ciudadanos.listar_mensajes(mensajes, "OTRO")
      assert {:ok, %{estado: :pendiente}, _} = Ciudadanos.marcar_mensaje(mensajes, "MSG001", :pendiente)
      assert {:error, :mensaje_no_encontrado} = Ciudadanos.marcar_mensaje(mensajes, "MSG999", "entregado")
      assert {:error, :estado_mensaje_invalido} = Ciudadanos.marcar_mensaje(mensajes, "MSG001", "leido")
    end

    test "valida destinatario y contenido", %{personas: personas} do
      assert {:error, :destinatario_no_encontrado} = Ciudadanos.enviar_mensaje([], personas, "x", "NOEXISTE", "hola")
      assert {:error, :campo_vacio} = Ciudadanos.enviar_mensaje([], personas, "x", "DOC100", " ")
    end

    test "arma los textos para mostrar en consola", %{personas: [persona]} do
      assert Ciudadanos.texto_persona(persona) =~ "Andrés"
      assert Ciudadanos.texto_persona(persona) =~ "localizada"
      assert Ciudadanos.texto_estado(:sin_informacion) == "sin información"
      assert Ciudadanos.mensaje_error(:documento_duplicado) =~ "documento"
    end
  end

  describe "Ciudadanos: persistencia" do
    test "personas y mensajes sobreviven al ciclo línea -> estructura" do
      {:ok, _, l} = Ciudadanos.registrar_persona([], "D1", "Andrés", 32, "Z1", "en albergue")
      {:ok, _, l} = Ciudadanos.cambiar_estado(l, "D1", "reunificada")
      {:ok, _, mensajes} = Ciudadanos.enviar_mensaje([], l, "yo", "D1", "hola")

      assert l == l |> Ciudadanos.personas_a_lineas() |> Ciudadanos.personas_desde_lineas()
      assert mensajes == mensajes |> Ciudadanos.mensajes_a_lineas() |> Ciudadanos.mensajes_desde_lineas()
    end

    test "lee las líneas que ya existían en data/ (formato antiguo, con \\r\\n)" do
      assert {:ok, p} = Ciudadanos.linea_a_persona("P|P_1794527726276000_459254|Andrés|DOC100|32|Z1|en albergue\r\n")
      assert p.estado == :en_albergue and p.historial == []

      linea = "M|MSG_1794527726288000_234922|2026-11-12 18:55:26|familiar|DOC100|Estoy bien|entregado\r\n"
      assert {:ok, %{estado: :entregado}} = Ciudadanos.linea_a_mensaje(linea)
      assert {:error, :linea_invalida} = Ciudadanos.linea_a_persona("basura")
      assert [] == Ciudadanos.personas_desde_lineas(["", "basura"])
    end
  end

  # ------------------------------------------------------------------ Recursos

  describe "Recursos: inventario" do
    test "registra recursos y no permite duplicados ni negativos" do
      assert {:ok, r, lista} = Recursos.registrar([], "r001", "agua", "agua", 200, "litros", "centro_acopio_1")
      assert r.codigo == "R001" and r.cantidad == 200
      assert {:error, :recurso_duplicado} = Recursos.registrar(lista, "R001", "agua", "agua", 5, "litros", "Centro_Acopio_1")
      assert {:error, :datos_distintos} = Recursos.registrar(lista, "R001", "arroz", "alimentos", 5, "kg", "otro")
      assert {:error, :cantidad_negativa} = Recursos.registrar([], "R2", "agua", "agua", -5, "l", "c")
      assert {:error, :cantidad_invalida} = Recursos.registrar([], "R2", "agua", "agua", "mucho", "l", "c")
      assert {:error, :campo_vacio} = Recursos.registrar([], "R2", "agua", "agua", 5, " ", "c")
    end

    test "entradas y salidas actualizan la cantidad y el historial" do
      {:ok, _, lista} = Recursos.registrar([], "R001", "agua", "agua", 50, "litros", "c1")

      assert {:ok, %{cantidad: 70}, lista} = Recursos.entrada(lista, "R001", "c1", 20)
      assert {:ok, %{cantidad: 60}, lista} = Recursos.salida(lista, "R001", "c1", "10")
      assert {:error, {:stock_insuficiente, 60}} = Recursos.salida(lista, "R001", "c1", 61)
      assert {:error, :cantidad_invalida} = Recursos.salida(lista, "R001", "c1", 0)
      assert {:error, :cantidad_negativa} = Recursos.entrada(lista, "R001", "c1", -4)
      assert {:error, :recurso_no_encontrado} = Recursos.entrada(lista, "R999", "c1", 1)

      assert {:ok, historial} = Recursos.historial(lista, "R001", "c1")
      assert Enum.map(historial, fn {_fecha, tipo, _cantidad, _detalle} -> tipo end) == [:registro, :entrada, :salida]
    end

    test "transfiere entre centros y crea el destino si no existe" do
      {:ok, _, lista} = Recursos.registrar([], "R001", "agua", "agua", 100, "litros", "centro_acopio_1")

      assert {:ok, {origen, destino}, lista} = Recursos.transferir(lista, "R001", "centro_acopio_1", "albergue_2", 30)
      assert origen.cantidad == 70 and destino.cantidad == 30 and destino.unidad == "litros"
      assert Recursos.total_disponible(lista, "agua") == 100

      assert {:ok, _, lista} = Recursos.transferir(lista, "R001", "centro_acopio_1", "albergue_2", 10)
      assert {:ok, %{cantidad: 40}} = Recursos.buscar(lista, "R001", "albergue_2")
      assert length(lista) == 2

      assert {:error, {:stock_insuficiente, 60}} = Recursos.transferir(lista, "R001", "centro_acopio_1", "albergue_2", 61)
      assert {:error, :mismo_centro} = Recursos.transferir(lista, "R001", "albergue_2", "ALBERGUE_2", 1)
      assert {:error, :recurso_no_encontrado} = Recursos.transferir(lista, "R001", "no_existe", "x", 1)
      assert Recursos.total_disponible(lista, "R001") == 100
    end
  end

  describe "Recursos: funciones recursivas y consultas" do
    setup do
      {:ok, _, l} = Recursos.registrar([], "R001", "agua", "agua", 50, "litros", "acopio1")
      {:ok, _, l} = Recursos.registrar(l, "R001", "agua", "agua", 30, "litros", "albergue1")
      {:ok, _, l} = Recursos.registrar(l, "R002", "arroz", "alimentos", 5, "kg", "acopio1")
      %{recursos: l}
    end

    test "suma_recursiva/2 y total_disponible/2", %{recursos: l} do
      assert Recursos.suma_recursiva(l, 0) == 85
      assert Recursos.suma_recursiva([], 0) == 0
      assert Recursos.total_disponible(l, "agua") == 80
      assert Recursos.total_disponible(l, "R001") == 80
      assert Recursos.total_disponible(l, "alimentos") == 5
      assert Recursos.total_disponible(l, "inexistente") == 0
    end

    test "consulta por categoría y ubicación y detecta críticos", %{recursos: l} do
      assert 2 == l |> Recursos.consultar(categoria: "agua") |> length()
      assert [%{ubicacion: "albergue1"}] = Recursos.consultar(l, categoria: "AGUA", ubicacion: "albergue1")
      assert [%{codigo: "R002"}] = Recursos.criticos(l, 10)
      assert 3 == l |> Recursos.criticos(1000) |> length()
    end

    test "arma el texto para mostrar en consola", %{recursos: [recurso | _]} do
      assert Recursos.texto_recurso(recurso) =~ "50 litros"
      assert Recursos.mensaje_error({:stock_insuficiente, 20}) =~ "20"
    end

    test "persistencia: ciclo línea -> estructura y formato antiguo", %{recursos: l} do
      {:ok, _, l} = Recursos.entrada(l, "R002", "acopio1", 7, "donación; con | símbolos")
      assert l == l |> Recursos.a_lineas() |> Recursos.desde_lineas()

      antigua = "R|R002|agua|agua|20|litros|acopio1|2026-11-12 18:55:26 asignado 30 litros a N_1\r\n"
      assert {:ok, %{cantidad: 20, historial: [{"", :registro, 0, texto}]}} = Recursos.desde_linea(antigua)
      assert texto =~ "asignado 30 litros"
    end
  end

  # --------------------------------------------------------------- Necesidades

  describe "Necesidades: registro, filtros y prioridad" do
    setup do
      {:ok, _, l} = Necesidades.registrar([], "agua", 30, "crítica", "centro", "Punto sector 3", "laura")
      {:ok, _, l} = Necesidades.registrar(l, "alimentos", 10, "baja", "norte", "Comida")
      {:ok, _, l} = Necesidades.registrar(l, "medicamentos", 5, "alta", "centro", "Insulina")
      {:ok, _, l} = Necesidades.registrar(l, "agua", 8, "critica", "norte", "Más agua")
      {:ok, _, l} = Necesidades.registrar(l, "rescate", 2, "alta", "centro", "Atrapados")
      %{necesidades: l}
    end

    test "valida los datos y genera IDs únicos", %{necesidades: l} do
      assert Enum.map(l, & &1.id) == ["N001", "N002", "N003", "N004", "N005"]
      assert {:error, :tipo_invalido} = Necesidades.registrar(l, "oro", 1, "alta", "z", "d")
      assert {:error, :prioridad_invalida} = Necesidades.registrar(l, "agua", 1, "urgentisima", "z", "d")
      assert {:error, :cantidad_negativa} = Necesidades.registrar(l, "agua", -1, "alta", "z", "d")
      assert {:error, :cantidad_invalida} = Necesidades.registrar(l, "agua", 0, "alta", "z", "d")
      assert {:error, :cantidad_invalida} = Necesidades.registrar(l, "agua", "diez", "alta", "z", "d")
      assert {:error, :campo_vacio} = Necesidades.registrar(l, "agua", 1, "alta", " ", "d")
      assert {:ok, %{tipo: :primeros_auxilios}, _} = Necesidades.registrar(l, "primeros auxilios", 1, "alta", "z", "d")
    end

    test "ordenar_por_prioridad/1 es recursivo y estable", %{necesidades: l} do
      assert ["N001", "N004", "N003", "N005", "N002"] == l |> Necesidades.ordenar_por_prioridad() |> Enum.map(& &1.id)
      assert [] == Necesidades.ordenar_por_prioridad([])
    end

    test "filtrar/2 combina zona, tipo, prioridad y estado", %{necesidades: l} do
      assert ["N001", "N003", "N005"] == l |> Necesidades.filtrar(zona: "centro") |> Enum.map(& &1.id)
      assert ["N001"] == l |> Necesidades.filtrar(zona: "centro", prioridad: "critica") |> Enum.map(& &1.id)
      assert ["N001", "N004"] == l |> Necesidades.filtrar(tipo: "agua", estado: "pendiente") |> Enum.map(& &1.id)
      assert [] == Necesidades.filtrar(l, estado: "atendida")
      assert [] == Necesidades.filtrar(l, zona: "inexistente")
    end

    test "pendientes y siguiente usan la prioridad", %{necesidades: l} do
      assert {:ok, %{id: "N001"}} = Necesidades.siguiente(l)
      assert hd(Necesidades.pendientes(l)).id == "N001"
      assert {:error, :sin_pendientes} = Necesidades.siguiente([])
      assert %{pendiente: 5} == Necesidades.contar_por_estado(l)
    end

    test "arma el texto para mostrar en consola", %{necesidades: [primera | _]} do
      assert Necesidades.texto_necesidad(primera) =~ "N001 | agua | Cantidad: 30 | Prioridad: crítica"
    end
  end

  describe "Necesidades: estados" do
    setup do
      {:ok, _, l} = Necesidades.registrar([], "agua", 30, "alta", "centro", "d")
      %{necesidades: l}
    end

    test "no se cierra dos veces ni se reabre", %{necesidades: l} do
      assert {:error, :transicion_invalida} = Necesidades.cambiar_estado(l, "N001", "atendida")
      assert {:error, :usar_asignar_recurso} = Necesidades.cambiar_estado(l, "N001", "asignada")
      assert {:ok, %{estado: :cancelada}, l} = Necesidades.cambiar_estado(l, "N001", "cancelada")
      assert {:error, :necesidad_cerrada} = Necesidades.cambiar_estado(l, "N001", "cancelada")
      assert {:error, :necesidad_cerrada} = Necesidades.cambiar_estado(l, "N001", "pendiente")
      assert {:error, :necesidad_no_encontrada} = Necesidades.cambiar_estado(l, "N999", "cancelada")
      assert {:error, :estado_invalido} = Necesidades.cambiar_estado(l, "N001", "rara")
    end
  end

  describe "Necesidades: asignación de recursos" do
    setup do
      {:ok, _, recursos} = Recursos.registrar([], "R001", "agua", "agua", 50, "litros", "centro_acopio_1")
      {:ok, _, necesidades} = Necesidades.registrar([], "agua", 30, "critica", "centro", "Punto sector 3")
      {:ok, _, necesidades} = Necesidades.registrar(necesidades, "agua", 25, "alta", "centro", "Otro punto")
      %{necesidades: necesidades, recursos: recursos}
    end

    test "asigna, descuenta y deja la necesidad como asignada", %{necesidades: n, recursos: r} do
      assert {:ok, res} = Necesidades.asignar_recurso(n, r, "N001", "agua", 30)
      assert res.necesidad.estado == :asignada and res.necesidad.asignado == 30
      assert res.necesidad.recursos == ["R001"]
      assert res.usados == [{"R001", "centro_acopio_1", 30}]
      assert Recursos.total_disponible(res.recursos, "agua") == 20
    end

    test "el ejemplo del enunciado: 30 + 25 litros sobre un inventario de 50", %{necesidades: n, recursos: r} do
      {:ok, res} = Necesidades.asignar_recurso(n, r, "N001", "agua", 30)

      assert {:error, {:stock_insuficiente, 20}} =
               Necesidades.asignar_recurso(res.necesidades, res.recursos, "N002", "agua", 25)

      # el fallo no modificó nada
      assert Recursos.total_disponible(res.recursos, "agua") == 20
      assert {:ok, %{estado: :pendiente, asignado: 0}} = Necesidades.buscar_por_id(res.necesidades, "N002")
    end

    test "no asigna más de lo que la necesidad pide, ni cantidades inválidas", %{necesidades: n, recursos: r} do
      assert {:error, :excede_requerido} = Necesidades.asignar_recurso(n, r, "N001", "agua", 31)
      assert {:error, :cantidad_invalida} = Necesidades.asignar_recurso(n, r, "N001", "agua", 0)
      assert {:error, :cantidad_negativa} = Necesidades.asignar_recurso(n, r, "N001", "agua", -5)
      assert {:error, :recurso_no_encontrado} = Necesidades.asignar_recurso(n, r, "N001", "oro", 5)
      assert {:error, :necesidad_no_encontrada} = Necesidades.asignar_recurso(n, r, "N999", "agua", 5)
    end

    test "asignaciones parciales acumulan y una necesidad atendida no vuelve a consumir", %{necesidades: n, recursos: r} do
      {:ok, a} = Necesidades.asignar_recurso(n, r, "N001", "agua", 10)
      {:ok, b} = Necesidades.asignar_recurso(a.necesidades, a.recursos, "N001", "R001", 20)
      assert b.necesidad.asignado == 30
      assert {:error, :excede_requerido} = Necesidades.asignar_recurso(b.necesidades, b.recursos, "N001", "agua", 1)

      {:ok, _, ns} = Necesidades.cambiar_estado(b.necesidades, "N001", "atendida")
      assert {:error, :necesidad_cerrada} = Necesidades.asignar_recurso(ns, b.recursos, "N001", "agua", 1)
      assert Recursos.total_disponible(b.recursos, "agua") == 20
    end

    test "toma de varios centros cuando uno solo no alcanza", %{necesidades: n, recursos: r} do
      {:ok, _, r} = Recursos.registrar(r, "R001", "agua", "agua", 10, "litros", "albergue_1")

      {:ok, _, r2} = Recursos.salida(r, "R001", "centro_acopio_1", 35)
      assert {:ok, res} = Necesidades.asignar_recurso(n, r2, "N001", "agua", 20)
      assert res.usados == [{"R001", "centro_acopio_1", 15}, {"R001", "albergue_1", 5}]
      assert Recursos.suma_recursiva(res.recursos, 0) == 5
    end
  end

  describe "Necesidades: persistencia" do
    test "ciclo línea -> estructura y lectura del formato antiguo" do
      {:ok, _, l} = Necesidades.registrar([], "primeros auxilios", 4, "crítica", "Z1", "Botiquín", "laura")
      assert l == l |> Necesidades.a_lineas() |> Necesidades.desde_lineas()

      antigua = "N|N_1794527726261000_824011|agua|100|crítica|Z1|Sector 3|R002|asignada|30\r\n"
      assert {:ok, n} = Necesidades.desde_linea(antigua)
      assert n.estado == :asignada and n.asignado == 30 and n.recursos == ["R002"] and n.prioridad == :critica
      assert {:error, :linea_invalida} = Necesidades.desde_linea("basura")
    end
  end

  # -------------------------------------------------------------- Concurrencia

  describe "Concurrencia: conflicto por el mismo recurso" do
    # Simula el GenServer del servidor: un solo proceso con el estado, que
    # atiende los mensajes de uno en uno. Aquí se usa un Agent por simplicidad.
    defp iniciar_estado(inventario, cantidades_requeridas) do
      {:ok, _, recursos} = Recursos.registrar([], "R001", "agua", "agua", inventario, "litros", "centro_acopio_1")

      necesidades =
        Enum.reduce(cantidades_requeridas, [], fn cantidad, acumulado ->
          {:ok, _, nuevas} = Necesidades.registrar(acumulado, "agua", cantidad, "alta", "centro", "solicitud")
          nuevas
        end)

      {:ok, pid} = Agent.start_link(fn -> %{necesidades: necesidades, recursos: recursos} end)
      pid
    end

    defp solicitar(pid, id, cantidad) do
      Agent.get_and_update(pid, fn estado ->
        case Necesidades.asignar_recurso(estado.necesidades, estado.recursos, id, "agua", cantidad) do
          {:ok, res} -> {{:ok, id}, %{necesidades: res.necesidades, recursos: res.recursos}}
          {:error, motivo} -> {{:error, motivo}, estado}
        end
      end)
    end

    test "30 y 25 litros al mismo tiempo sobre 50 disponibles: solo se confirma una" do
      pid = iniciar_estado(50, [30, 25])

      resultados =
        ["N001", "N002"]
        |> Enum.zip([30, 25])
        |> Task.async_stream(fn {id, cantidad} -> solicitar(pid, id, cantidad) end, max_concurrency: 2)
        |> Enum.map(fn {:ok, resultado} -> resultado end)

      assert Enum.count(resultados, &match?({:ok, _}, &1)) == 1
      assert Enum.count(resultados, &match?({:error, {:stock_insuficiente, _}}, &1)) == 1

      estado = Agent.get(pid, & &1)
      asignado = estado.necesidades |> Enum.map(& &1.asignado) |> Enum.sum()
      assert asignado in [30, 25]
      assert Recursos.total_disponible(estado.recursos, "agua") == 50 - asignado
    end

    test "100 solicitudes simultáneas de 7 litros nunca superan el inventario" do
      inventario = 50
      pid = iniciar_estado(inventario, List.duplicate(7, 100))

      resultados =
        1..100
        |> Task.async_stream(
          fn n -> solicitar(pid, "N" <> String.pad_leading(Integer.to_string(n), 3, "0"), 7) end,
          max_concurrency: 50
        )
        |> Enum.map(fn {:ok, resultado} -> resultado end)

      confirmadas = Enum.count(resultados, &match?({:ok, _}, &1))
      assert confirmadas == div(inventario, 7)

      estado = Agent.get(pid, & &1)
      assert Enum.sum(Enum.map(estado.necesidades, & &1.asignado)) == confirmadas * 7
      assert Recursos.total_disponible(estado.recursos, "agua") == inventario - confirmadas * 7
      assert Recursos.total_disponible(estado.recursos, "agua") >= 0
    end
  end
end
