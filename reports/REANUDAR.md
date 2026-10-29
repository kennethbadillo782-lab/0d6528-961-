# Estado para continuar

Backend local real funcionando en Docker, publicado solo en 127.0.0.1. Suite completa `Test-All.ps1 -Live` terminada correctamente: 48 pruebas HTTP, 137 ataques SQL en stack real y regresión independiente, pruebas de concurrencia y cron. No hay modificaciones remotas de Supabase.

GitHub conectado: kennethbadillo782-lab. Repositorio privado MiCatalogo creado. Workflow manual iOS Simulator preparado; verificar su ejecución real y corregir errores de Swift antes de añadir autenticación/sincronización. El código iOS aún es local. No afirmar que una preparación equivale a una compilación.

Actions tiene cuota incluida disponible y sobreconsumo bloqueado con presupuesto cero. No aumentar presupuestos ni contratar servicios. Codemagic es una alternativa, no un requisito.

Después de compilar: implementar fase 3 de AGENTS.md; comprobar acceso existente a Appetize y Supabase antes de pedir cuentas. Un backend remoto requiere autorización específica y copia previa si contiene datos. El ZIP de fuentes no es el ZIP de simulador para Appetize.

Excluir .tools, .local, .venv y backend/supabase/.temp de Git y del paquete. Nunca imprimir tokens.
