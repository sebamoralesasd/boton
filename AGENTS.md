# Boton
Boton es un programa de línea de comandos que sincroniza notificaciones de compra de Banco Macro
desde Gmail y las guarda en una base SQLite local, agrupadas en resúmenes (períodos) para llevar
la cuenta de un ciclo de facturación.

Los datos se obtienen leyendo emails de Gmail (OAuth2, sólo lectura) filtrados por remitente y
asunto; cada email se parsea para extraer monto, comercio, fecha y hora, y se guarda evitando
duplicados por el id del mensaje de Gmail. Los reversos de compra se buscan por separado, se
registran en la tabla `reversals` y anulan la transacción original cuando hay una única candidata
(mismo comercio y monto). Los que quedan pendientes se reintentan en cada sync, sin consultar Gmail.

## Comandos

```shell
# Setup
bundle install

# Correr aplicación
boton                         # Sincronizar transacciones de hoy desde Gmail
    ayer                      # Sincronizar transacciones de ayer
    desde FECHA|ayer          # Sincronizar desde esa fecha hasta hoy
    FECHA                     # Sincronizar transacciones de una fecha específica (YYYY-MM-DD)
    --local                   # No consultar Gmail: mostrar sólo lo registrado en la base local
    open FECHA                # Abrir nuevo resumen (cierra el anterior si existe)
    reversos [FECHA]          # Buscar reversos de FECHA (hoy por defecto) y marcarlos en la DB
    list [FECHA|PALABRA]      # Transacciones del resumen actual (opcionalmente filtradas)
    all [FECHA|PALABRA]       # Transacciones de todo el historial (opcionalmente filtradas)
    help                      # Ayuda

# Lint
bundle exec rubocop

# Depuración
BOTON_LOG_LEVEL=DEBUG boton   # Logs detallados (requests a Gmail, decodificación de HTML, etc.)
```

## Variables de entorno

| Variable | Default | Para qué |
|---|---|---|
| `BOTON_DB` | `data/transactions.db` en la raíz del repo | Path del archivo SQLite |
| `BOTON_CREDENTIALS` | `config/credentials.json` en la raíz del repo | Credenciales OAuth2 de Google Cloud |
| `BOTON_TOKEN` | `config/token.yaml` en la raíz del repo | Token OAuth2 (se genera en la primera autorización) |
| `BOTON_LOG_LEVEL` | `INFO` | Nivel del logger |

## Estructura

`bin/boton` despacha a `Boton::CLI`, que arma el logger, abre la `Database` y se lo pasa a
`Boton::Application`. `Application` usa `CommandParser` para convertir ARGV en una acción y,
según la acción, delega a `SyncService` / `ReversalService` (sincronizan y comparan contra Gmail
vía `GmailClient` + `EmailParser`) o a `ListService` (consulta la `Database` y delega la salida a
`TransactionPresenter`).

- `cli.rb` es el único lugar que rescata errores, decide el exit code y cierra la conexión a la DB;
  el resto lanza `Boton::Error` (o `Boton::UsageError` para errores de uso), definidos en `errors.rb`
- `command_parser.rb` traduce ARGV a un hash `{action:, ...}`, sin ejecutar nada
- `gmail_client.rb` maneja OAuth2 y la extracción de HTML de los mensajes de Gmail
- `email_parser.rb` aplica los regex sobre el HTML y arma un `Transaction`
- `database.rb` tiene la conexión, el schema y todas las queries (con bind params). El schema
  evoluciona con migraciones numeradas (`MIGRATIONS`, versión en `PRAGMA user_version`); para
  cambiarlo, agregar una migración al final de la lista, nunca editar una existente
- Los montos se guardan y operan en centavos enteros (`amount_cents`); sólo se pasan a pesos al mostrarlos
- `transaction_presenter.rb` imprime la tabla de transacciones; es de los pocos lugares con `puts`
- `help_presenter.rb` imprime el texto de ayuda (`boton help`)
- Los "resúmenes" agrupan transacciones por período; sólo puede haber uno abierto
  (`periodo_fin IS NULL`) a la vez. `open FECHA` rechaza fechas que se superpongan con un resumen
  existente y mueve al nuevo las transacciones del anterior con fecha ≥ FECHA. `list`/`all` filtran
  distinto: `list` sólo mira el resumen que contiene la fecha de hoy (no necesariamente el abierto),
  `all` mira todo el historial

## Code style
- Respetar separación de responsabilidades
- Todo bajo el namespace `Boton`, un archivo por clase, el path espeja el namespace (`lib/boton/*.rb`)
- snake_case para métodos y variables, CamelCase para clases y módulos
- Definir errores heredando `StandardError`
- Usar `Logger` para logs sobre puntos relevantes, nunca `puts` salvo en los presenters (la salida real del programa)
- Usar patrón `ENV.fetch('KEY', default)` para variables de entorno
- Usar `attr_*` en lugar de getters explícitos
- Usar SQLite3 para la base de datos, siempre con bind params
- Inyectar colaboradores por keyword args (`logger:`) con default concreto, para poder testear
- No comentar las funciones

## Misc
- Priorizar plan sobre ejecución. Realizar las preguntas necesarias
- Seguir los cuatro principios de calidad de escritura de Zinsser:
1. Simplicidad
2. Brevedad
3. Claridad
4. Humanidad
