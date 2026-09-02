# Boton

Programa Ruby que lee emails de transacciones de Banco Macro desde Gmail, extrae información relevante (monto, comercio, fecha, hora) y la almacena en una base de datos SQLite3.

## Requisitos Previos

- Ruby 3.3.0 (gestionado con mise)
- Cuenta de Gmail con emails de Banco Macro
- Proyecto en Google Cloud Console con Gmail API habilitada

## Instalación

### 1. Instalar Ruby

```bash
mise install ruby@3.3.0
```

### 2. Instalar Dependencias

```bash
bundle install
```

### 3. Configurar Google Cloud

#### A. Crear Proyecto en Google Cloud

1. Ir a https://console.cloud.google.com/
2. Click en "New Project"
3. Nombre: `macro-email-parser`
4. Click "Create"

#### B. Habilitar Gmail API

1. En el proyecto, ir a "APIs & Services" → "Library"
2. Buscar "Gmail API"
3. Click "Enable"

#### C. Configurar OAuth Consent Screen

1. Ir a "APIs & Services" → "OAuth consent screen"
2. Seleccionar "External"
3. Completar:
   - App name: `Macro Transaction Parser`
   - User support email: tu email
   - Developer contact: tu email
4. Click "Save and Continue"

**Scopes:**
1. Click "Add or Remove Scopes"
2. Buscar y seleccionar: `https://www.googleapis.com/auth/gmail.readonly`
3. Click "Save and Continue"

**Test users:**
1. Click "Add Users"
2. Agregar tu dirección de Gmail
3. Click "Save and Continue"

#### D. Crear Credenciales OAuth 2.0

1. Ir a "APIs & Services" → "Credentials"
2. Click "Create Credentials" → "OAuth client ID"
3. Application type: **Desktop app**
4. Name: `Macro Parser Desktop Client`
5. Click "Create"
6. Descargar el archivo JSON

#### E. Configurar Credenciales en el Proyecto

```bash
# Mover el archivo descargado
mv ~/Downloads/client_secret_*.json config/credentials.json

# Verificar
ls -la config/credentials.json
```

## Uso

Ver [AGENTS.md](AGENTS.md) para la lista completa de comandos y variables de entorno.

### Primera Ejecución

En la primera ejecución, el programa abrirá tu navegador para autorizar el acceso a Gmail:

1. Selecciona tu cuenta de Gmail
2. Click "Advanced" → "Go to Macro Transaction Parser (unsafe)"
3. Click "Allow"
4. El token se guardará en `config/token.yaml` para futuras ejecuciones

## Consultar la Base de Datos

```bash
# Abrir SQLite
sqlite3 data/transactions.db

# Ver todas las transacciones
SELECT * FROM transactions ORDER BY transaction_date DESC, transaction_time DESC;

# Ver transacciones de una fecha
SELECT * FROM transactions WHERE transaction_date = '2026-01-03';

# Contar transacciones
SELECT COUNT(*) FROM transactions;

# Salir
.exit
```

## Troubleshooting

### Error: credentials.json not found

Verificar que descargaste las credenciales de Google Cloud Console y las colocaste en `config/credentials.json`.

### Error: invalid_grant (Token expirado)

Eliminar el token y re-autorizar:

```bash
rm config/token.yaml
boton
```

### No se encontraron emails

Verificar que:
1. La fecha tiene emails de Banco Macro
2. Los emails vienen de `info@notificaciones.bancomacro.com.ar`
3. El subject contiene "Aviso de compra"

### Database locked

Verificar que no hay otra instancia corriendo:

```bash
ps aux | grep ruby
# Si hay procesos, matarlos
kill -9 <pid>
```

## Características

- ✅ Autenticación OAuth2 con Gmail (solo lectura)
- ✅ Búsqueda filtrada por remitente, subject y fecha
- ✅ Parser robusto de HTML con quoted-printable
- ✅ Prevención de duplicados por Message-ID
- ✅ Logging detallado (nivel INFO por defecto)
- ✅ Validaciones de seguridad (fecha futura, formato)
- ✅ Almacenamiento en SQLite3 con índices
- ✅ Normalización de datos (montos, fechas, comercios)

## Datos Extraídos

De cada email de transacción se extrae:

- **Monto**: `$19.390,00` → `19390.0`
- **Comercio**: `SAN CAYETANO AUTOSERV`
- **Fecha**: `03/01/2026` → `2026-01-03`
- **Hora**: `11:39hs` → `11:39`
- **Email ID**: Message-ID único de Gmail (para evitar duplicados)

## Especificaciones Técnicas

- **Ruby**: 3.3.0
- **Base de datos**: SQLite3 (`data/transactions.db`)
- **Logging**: Logger::INFO por defecto
- **Zona horaria**: Se almacena tal cual viene en el email (ART)
- **Formato de monto**: DECIMAL (19390.00)

## Archivos Sensibles (No Commitear)

El `.gitignore` está configurado para proteger:

- `config/credentials.json` - Credenciales OAuth2
- `config/token.yaml` - Token de acceso
- `data/*.db` - Base de datos con transacciones
- `*.eml` - Ejemplos de emails

## Licencia

Proyecto personal - Uso privado
