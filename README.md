# Sistema Distribuido de Coordinación y Gestión de Emergencias

Proyecto final de Programación III (Universidad del Quindío). Sistema en
Elixir para gestionar emergencias post-terremoto con arquitectura distribuida,
concurrencia OTP, persistencia en texto plano y separación de responsabilidades.

No usa dependencias externas: solo Elixir/OTP y la biblioteca estándar.

---

## Estructura del proyecto (fiel al repositorio)

```
proyecto/
├── main.exs                     # Punto de entrada único: elixir main.exs
├── .gitignore
├── README.md
├── cliente/
│   ├── cookie.txt               # Cookie generada al ejecutar
│   ├── nodo-cliente.exs         # Nodo cliente (envía comandos al servidor)
│   └── util.ex                  # Utilidades del cliente
├── servidor/
│   ├── cookie.txt               # Cookie generada al ejecutar
│   ├── cookie.exs               # Generación y gestión de cookies
│   ├── nodo-servidor.exs        # Nodo servidor (inicia el GenServer)
│   └── util.ex                  # Utilidades del servidor
├── lib/
│   └── emergencia/
│       ├── modelos.ex           # Structs y constructores de dominio
│       ├── persistencia.ex      # Lectura/escritura de archivos de texto
│       ├── sesion.ex            # GenServer: usuarios, autenticación, roles
│       ├── server.ex            # GenServer: estado global y lógica de negocio
│       ├── supervisor.ex        # Supervisor OTP (one_for_one)
│       ├── nodo_servidor.ex     # Fachada RPC: despacho de comandos y permisos
│       ├── zonas.ex             # Zonas → sectores → puntos (recursivo)
│       ├── ciudadanos.ex        # Personas y mensajería (búsqueda recursiva)
│       ├── necesidades.ex       # Necesidades y priorización (recursivo)
│       ├── recursos.ex          # Inventario y suma recursiva
│       ├── albergues.ex         # Albergues y capacidad (recursivo)
│       ├── mascotas.ex          # Mascotas y emparejamiento (recursivo)
│       └── data/                # Archivos de persistencia (datos iniciales)
└── test/
    ├── persona2_test.exs        # Ciudadanos, necesidades y recursos
    ├── emergencia_test.exs      # Albergues, mascotas, GenServer y supervisor
    └── nodos_test.exs           # Fachada de comandos del nodo servidor
```

---

## Ejecución

```powershell
cd <ruta-del-proyecto>
elixir main.exs
```

Este comando ejecuta todo el sistema sin necesidad de `iex` ni modo interactivo
y muestra una demostración de albergues, mascotas y el resumen global.

### Ejecutar las pruebas

```powershell
elixir test/persona2_test.exs
elixir test/emergencia_test.exs
elixir test/nodos_test.exs
```

`test/emergencia_test.exs` cubre albergues, mascotas, el GenServer y el
supervisor. `test/nodos_test.exs` recorre los 33 comandos del cliente contra
la fachada `Emergencia.NodoServidor` y comprueba permisos, filtros y
persistencia. Cada prueba usa un directorio temporal, así que no toca los
datos reales.

### Ejecución distribuida (dos nodos)

El servidor y el cliente son nodos Erlang independientes. El servidor genera la
cookie en `servidor/cookie.txt` y la copia a `cliente/cookie.txt` para que ambos
nodos se autentiquen. **Los dos deben arrancar con `--sname`.**

Terminal 1 — nodo servidor:

```powershell
elixir --sname servidor servidor/nodo-servidor.exs
```

Terminal 2 — nodo cliente (cada comando es una ejecución independiente):

```powershell
elixir --sname cliente cliente/nodo-cliente.exs help
elixir --sname cliente cliente/nodo-cliente.exs connect laura 1234 coordinador centro
elixir --sname cliente cliente/nodo-cliente.exs summary
elixir --sname cliente cliente/nodo-cliente.exs disconnect
```

La cookie de la sesión del usuario se guarda en `cliente/sesion.txt`, de modo
que los comandos posteriores a `connect` conservan la sesión aunque cada uno
se ejecute en un proceso nuevo. `disconnect` borra ese archivo. Si el servidor
corre en otra máquina, indique su nombre con la variable `NODO_SERVIDOR`
(por defecto `servidor@<mismo host>`).

Cada solicitud queda registrada en la terminal del servidor con la hora, el
comando, sus argumentos y el proceso cliente que la envió. La contraseña de
`connect` se enmascara y también se registra el resultado:

```text
19:30:54.319 [info] [NodoServidor] servidor@HOST <- connect args=["laura", "***", "coordinador", "centro"] cliente=#PID<0.223.0>
19:30:54.341 [info] [NodoServidor] -> connect: OK (Sesión iniciada: laura (coordinador, ...))
19:30:54.865 [info] [NodoServidor] servidor@HOST <- summary args=[] cliente=#PID<0.229.0>
19:30:54.873 [info] [NodoServidor] -> summary: OK (Personas: 1 | Mensajes: 1 | Zonas: 0)
```

Los comandos rechazados se registran con nivel `warning` y el motivo del error.

### Verificación realizada

Con el servidor en `servidor@<host>` y `epmd` activo, se ejecutaron los 33
comandos del cliente contra el nodo real, en este orden y con resultado
satisfactorio:

1. **Sesión y zonas:** `connect`, `register_zone`, `register_sector`,
   `register_point`, `zone_status`, `zones_summary`.
2. **Personas:** `report_person`, `find_person` (por documento y por
   `nombre=...`), `list_people`, `change_person_status`,
   `send_family_message`, `list_family_messages`.
3. **Necesidades y recursos:** `register_need`, `list_needs`,
   `pending_needs`, `assign_resource`, `register_resource`, `list_resources`,
   `resource_entry`, `resource_exit`, `transfer_resource`,
   `critical_resources`.
4. **Mascotas:** `report_pet`, `list_pets`, `match_pets`, `confirm_match`.
5. **Albergues:** `register_shelter`, `check_shelter`, `register_entry`,
   `register_exit`, `shelter_report`.
6. **Cierre:** `summary`, `help`, `disconnect` (y verificación de que tras
   `disconnect` los comandos exigen iniciar sesión).

Las operaciones de escritura persistieron en `lib/emergencia/data/*.txt` y los
datos se restauraron al finalizar la prueba.

### Comandos y roles: alcance

Los comandos de escritura exigen sesión y rol suficiente; las consultas también
exigen sesión (salvo `connect`, `disconnect` y `help`). El detalle está en la
tabla de permisos más abajo.

---

## Características implementadas

| Requisito | Estado |
|---|---|
| Usuarios, autenticación y roles | ✅ GenServer `Emergencia.Sesion` |
| Zonas → Sectores → Puntos (recursivo) | ✅ `Emergencia.Zonas` |
| Necesidades con prioridad y estados | ✅ `Emergencia.Necesidades` |
| Recursos con concurrencia controlada | ✅ `Emergencia.Recursos` |
| Comunicación familiar (mensajes) | ✅ `Emergencia.Ciudadanos` |
| Mascotas con emparejamiento | ✅ `Emergencia.Mascotas` |
| Albergues con capacidad | ✅ `Emergencia.Albergues` |
| Persistencia en texto plano | ✅ `lib/emergencia/data/*.txt` |
| Validaciones `{:ok, ...}` / `{:error, ...}` | ✅ Todos los módulos |
| GenServer | ✅ `Sesion`, `Servidor` y `NodoServidor` |
| Supervisor OTP | ✅ Árbol de supervisión |
| Al menos 4 funciones recursivas | ✅ 9+ funciones recursivas |
| Conflicto concurrente resuelto | ✅ Prueba con 2 Task simultáneas |
| Cookie guardada en archivo txt | ✅ `servidor/cookie.txt` / `cliente/cookie.txt` |

---

## Funciones recursivas propias

1. `Zonas.recorrer_sectores/3` - Estadísticas de la jerarquía
2. `Zonas.contar_puntos/1` - Puntos de atención de un sector
3. `Zonas.nivel_maximo/2` - Nivel más severo de sectores
4. `Ciudadanos.buscar/2` - Búsqueda por criterios múltiples
5. `Necesidades.ordenar_por_prioridad/1` - Ordenamiento por inserción
6. `Necesidades.filtrar/2` - Filtrado recursivo
7. `Recursos.suma_recursiva/2` - Suma de inventario
8. `Albergues.totales/3`, `cupos_disponibles/1`, `contar_ocupantes/1`
9. `Mascotas.emparejar/2`, `ordenar_por_puntaje/1`, `coincidencia?/2`

---

## Persistencia

Todos los datos se guardan como archivos de texto plano, un registro por línea
con campos separados por `|`. `Emergencia.Servidor` escribe en el directorio
que recibe al iniciar (`directorio:`); por defecto usa `lib/emergencia/data/`,
donde están los datos iniciales del proyecto, y guarda después de cada cambio.

- `users.txt` - Semilla de usuarios (`U|usuario|contraseña|rol|zona|nombre`)
- `zones.txt` - Semilla de zonas (`Z|codigo|nombre|nivel|afectados[|sectores]`)
- `usuarios.txt` - Usuarios activos (literal de Elixir, un mapa por línea).
  Si está vacío se cargan los de `users.txt`.
- `people.txt` - Personas afectadas (`P|...`)
- `messages.txt` - Mensajes familiares (`M|...`)
- `needs.txt` - Necesidades (`N|...`)
- `resources.txt` - Recursos (`R|...`)
- `shelters.txt` - Albergues (`A|...`)
- `pets.txt` - Mascotas (`MA|...`)
- `zonas.txt` - Zonas activas (literal de Elixir, una zona por línea).
  Si está vacío se cargan las de `zones.txt`.
- `servidor/cookie.txt` y `cliente/cookie.txt` - Cookie de distribución

### Usuarios y zonas de prueba

`users.txt` trae tres usuarios (contraseña `1234`) y `zones.txt` tres zonas:

| Usuario | Contraseña | Rol | Zona |
|---|---|---|---|
| `laura` | `1234` | `coordinador` | `centro` |
| `carlos` | `1234` | `voluntario` | `norte` |
| `ana` | `1234` | `ciudadano` | `sur` |

| Zona | Nombre | Nivel | Afectados |
|---|---|---|---|
| `Z1` | Centro | alto | 120 |
| `Z2` | Norte | medio | 80 |
| `Z3` | Sur | crítico | 200 |

`Z1` incluye el sector `S1` con el punto de atención `P1`, para probar la
jerarquía completa. El parser acepta tanto el formato de barras (`U|...`,
`Z|...`) como el literal de Elixir que escribe el sistema.

---

## Comandos del cliente

```
connect usuario contraseña [rol] [zona]
disconnect
register_zone codigo nombre nivel [personas]
register_sector zona codigo nombre [nivel]
register_point zona sector codigo [nombre] [descripcion]
zone_status codigo
zones_summary
report_person documento nombre [edad] zona estado
find_person documento | find_person nombre=texto
list_people
change_person_status id|documento estado
send_family_message documento "texto del mensaje"
list_family_messages documento
register_need tipo cantidad prioridad zona descripcion [responsable]
list_needs [zona=... tipo=... prioridad=... estado=...]
assign_resource id_necesidad codigo cantidad
register_resource codigo nombre categoria cantidad unidad ubicacion
list_resources [codigo=... nombre=... categoria=... ubicacion=...]
resource_entry codigo ubicacion cantidad
resource_exit codigo ubicacion cantidad
transfer_resource codigo origen destino cantidad
report_pet tipo especie nombre [caracteristicas] color tamano zona contacto
list_pets [tipo=... especie=... zona=... estado=...]
match_pets
confirm_match id_perdida id_encontrada
register_shelter codigo nombre zona capacidad
check_shelter codigo
register_entry codigo documento
register_exit codigo documento
shelter_report
pending_needs
critical_resources [umbral]
summary
help
```

Los comandos de consulta aceptan filtros `clave=valor` (por ejemplo
`list_needs tipo=agua prioridad=critica`). Los resultados salen por `stdout`;
los errores por `stderr` y con código de salida 1.

### Permisos por rol

| Rol | Comandos |
|---|---|
| `ciudadano` | Consultas y reportes (`report_person`, `report_pet`, `summary`, ...) |
| `voluntario` | Además: recursos, albergues y `confirm_match` |
| `coordinador` | Además: zonas (`register_zone`, `register_sector`, `register_point`) y `assign_resource` |
| `administrador` | Todos |

---

## Notas de compatibilidad

Los módulos no usan expresiones regulares literales (`~r/.../`): en su lugar
`Emergencia.Util` ofrece utilidades recursivas (`sin_tildes/1`, `palabras/1`,
`numero_id/2`, `hex_valido?/1`). Así el proyecto compila igual con Elixir
compilado para OTP 27 aunque se ejecute sobre OTP 29, donde las expresiones
regulares literales fallan con `cannot escape #Reference<...>`.

---

Proyecto académico — Universidad del Quindío.
