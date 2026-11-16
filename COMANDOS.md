elixir --sname servidor servidor/nodo-servidor.exs

elixir --sname cliente cliente/nodo-cliente.exs connect laura 1234 coordinador centro
elixir --sname cliente cliente/nodo-cliente.exs help
elixir --sname cliente cliente/nodo-cliente.exs summary
elixir --sname cliente cliente/nodo-cliente.exs disconnect

elixir --sname cliente cliente/nodo-cliente.exs register_zone Z2 "Zona Prueba" medio 50
elixir --sname cliente cliente/nodo-cliente.exs register_sector Z2 S9 "Sector Prueba"
elixir --sname cliente cliente/nodo-cliente.exs register_point Z2 S9 P9 "Punto Prueba" "Frente al parque"
elixir --sname cliente cliente/nodo-cliente.exs zone_status Z2
elixir --sname cliente cliente/nodo-cliente.exs zones_summary

elixir --sname cliente cliente/nodo-cliente.exs report_person DOC900 "Ana Prueba" 32 Z2 reportada
elixir --sname cliente cliente/nodo-cliente.exs find_person DOC900
elixir --sname cliente cliente/nodo-cliente.exs find_person "nombre=ana"
elixir --sname cliente cliente/nodo-cliente.exs list_people
elixir --sname cliente cliente/nodo-cliente.exs change_person_status DOC900 localizada
elixir --sname cliente cliente/nodo-cliente.exs send_family_message DOC900 "Estoy bien, en el albergue"
elixir --sname cliente cliente/nodo-cliente.exs list_family_messages DOC900

elixir --sname cliente cliente/nodo-cliente.exs register_need agua 40 critica Z2 "Prueba de necesidad"
elixir --sname cliente cliente/nodo-cliente.exs list_needs tipo=agua
elixir --sname cliente cliente/nodo-cliente.exs pending_needs
elixir --sname cliente cliente/nodo-cliente.exs assign_resource N001 agua 40

elixir --sname cliente cliente/nodo-cliente.exs register_resource R900 agua agua 100 litros acopioX
elixir --sname cliente cliente/nodo-cliente.exs list_resources categoria=agua
elixir --sname cliente cliente/nodo-cliente.exs resource_entry R900 acopioX 20
elixir --sname cliente cliente/nodo-cliente.exs resource_exit R900 acopioX 10
elixir --sname cliente cliente/nodo-cliente.exs transfer_resource R900 acopioX acopioY 30
elixir --sname cliente cliente/nodo-cliente.exs critical_resources 100

elixir --sname cliente cliente/nodo-cliente.exs report_pet perdida perro "Luna Prueba" "collar azul" negra mediana Z2 300999
elixir --sname cliente cliente/nodo-cliente.exs report_pet encontrada perro "Desconocida" "collar azul" negra mediana Z2 300888
elixir --sname cliente cliente/nodo-cliente.exs list_pets tipo=perdida
elixir --sname cliente cliente/nodo-cliente.exs match_pets
elixir --sname cliente cliente/nodo-cliente.exs confirm_match M001 M002

elixir --sname cliente cliente/nodo-cliente.exs register_shelter A900 "Albergue Prueba" Z2 2
elixir --sname cliente cliente/nodo-cliente.exs check_shelter A900
elixir --sname cliente cliente/nodo-cliente.exs register_entry A900 D900
elixir --sname cliente cliente/nodo-cliente.exs register_exit A900 D900
elixir --sname cliente cliente/nodo-cliente.exs shelter_report

elixir test/persona2_test.exs
elixir test/emergencia_test.exs
elixir test/nodos_test.exs
elixir main.exs

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
