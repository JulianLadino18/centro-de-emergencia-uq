defmodule Nodo.Cliente do
  @moduledoc """
  Nodo cliente del sistema de emergencias.
  Envía comandos al GenServer :servicio_emergencia del nodo servidor
  usando llamadas remotas (RPC).

  Uso:
    elixir --sname cliente --cookie MI_COOKIE cliente/nodo-cliente.exs [comando] [args...]
  """

  # Cargar solo utilidades del cliente (no módulos de dominio que dependen
  # de Emergencia.Servidor.call/1 localmente)

  # ---------- Construcción de mensajes para el servidor ----------


  # Punto de entrada cuando se ejecuta como script

end
