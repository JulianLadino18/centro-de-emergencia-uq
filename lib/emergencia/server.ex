defmodule Emergencia.Servidor do
  @moduledoc """
  GenServer principal del sistema de emergencias.

  Mantiene el estado global y serializa todas las mutaciones. Esto resuelve
  la regla de concurrencia obligatoria: aunque varios procesos soliciten
  recursos al mismo tiempo, el GenServer atiende una solicitud a la vez y
  valida el inventario antes de descontar.
  """


  # ============ Personas y mensajería ============


  # ============ Necesidades ============


  # ============ Recursos ============


  # ============ Albergues ============



  # ============ Mascotas ============


  # ============ Resumen ============



  # ============ Helpers ============


  # ---------- Lógica de asignación (concurrencia) ----------

end
