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
│       ├── zonas.ex             # Zonas → sectores → puntos (recursivo)
│       ├── ciudadanos.ex        # Personas y mensajería (búsqueda recursiva)
│       ├── necesidades.ex       # Necesidades y priorización (recursivo)
│       ├── recursos.ex          # Inventario y suma recursiva
│       ├── albergues.ex         # Albergues y capacidad (recursivo)
│       └── mascotas.ex          # Mascotas y emparejamiento (recursivo)
└── data/                        # Archivos de persistencia (se crean al ejecutar)
```

---

## Ejecución

```powershell
cd C:\Users\jladi\OneDrive\Escritorio\proyecto
elixir main.exs
```

Este comando ejecuta todo el sistema sin necesidad de `iex` ni modo interactivo.

### Ejecutar nodo servidor por separado

```powershell
elixir servidor/nodo-servidor.exs
```

### Ejecutar nodo cliente por separado

```powershell
elixir cliente/nodo-cliente.exs summary
elixir cliente/nodo-cliente.exs register_zone Z1 Centro alto 120
elixir cliente/nodo-cliente.exs connect laura 1234 coordinador centro
```

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
| Persistencia en texto plano | ✅ `data/*.txt` |
| Validaciones `{:ok, ...}` / `{:error, ...}` | ✅ Todos los módulos |
| GenServer | ✅ `Sesion` y `Servidor` |
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

Todos los datos se guardan en `data/` como archivos de texto plano, un
registro por línea con campos separados por `|`:

- `users.txt` - Usuarios
- `people.txt` - Personas afectadas
- `messages.txt` - Mensajes familiares
- `needs.txt` - Necesidades
- `resources.txt` - Recursos
- `shelters.txt` - Albergues
- `pets.txt` - Mascotas
- `zones.txt` - Zonas
- `session.txt` - Sesión
- `cookie.txt` - Cookie de autenticación

---

## Comandos del cliente

```
connect usuario contraseña [tipo] [zona]
disconnect
register_zone codigo nombre nivel [personas]
register_sector zona codigo nombre nivel
register_point zona sector punto
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
assign_resource id_necesidad codigo|nombre|categoria cantidad
register_resource codigo nombre categoria cantidad unidad ubicacion
list_resources
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
```

Proyecto académico — Universidad del Quindío.
