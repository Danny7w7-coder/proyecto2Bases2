# Sistema de Gestión de Estudios Médicos Distribuido

- **Curso:** Bases de Datos II — Instituto Tecnológico de Costa Rica, Sede San Carlos
- **Profesor:** MSc. Leonardo Víquez Acuña
- **Integrantes:** Danny Jesús Gonzalez Molina · Dylan Yoel Méndez Zamora · Francisco Javier Castillo Duarte
- **Repositorio:** https://github.com/Danny7w7-coder/proyecto2Bases2

> Este README es la guía técnica del repositorio: explica cómo está armado el sistema, cómo instalarlo y cómo fluyen los datos entre los tres motores. La documentación formal para entregar está en [docs/Documentacion_Proyecto2.docx](docs/Documentacion_Proyecto2.docx).

## Contenido

1. [Descripción general](#1-descripción-general)
2. [Arquitectura](#2-arquitectura)
3. [Estructura del repositorio](#3-estructura-del-repositorio)
4. [Instalación paso a paso](#4-instalación-paso-a-paso)
5. [Modelo de datos y segmentación](#5-modelo-de-datos-y-segmentación)
6. [Canales FDW](#6-canales-fdw)
7. [Roles y seguridad](#7-roles-y-seguridad)
8. [Flujos de datos](#8-flujos-de-datos)
9. [Operaciones requeridas](#9-operaciones-requeridas)
10. [Demostración y resultados esperados](#10-demostración-y-resultados-esperados)
11. [Solución de problemas](#11-solución-de-problemas)
12. [Referencias](#12-referencias)

---

## 1. Descripción general

El proyecto construye la **infraestructura de datos distribuida** de una plataforma de estudios médicos (laboratorio, radiografías y ultrasonidos). No incluye la aplicación web ni la móvil, solo las bases de datos, su comunicación y los usuarios con los que esas aplicaciones se conectarían.

Se combinan tres motores, cada uno con un propósito distinto:

| Motor | Propósito | Segmentación |
|---|---|---|
| **PostgreSQL 16** | Núcleo transaccional: pacientes, citas, órdenes, resultados y diagnósticos | Horizontal (por sucursal) |
| **SQL Server 2022** | Integración con aseguradoras, ministerio y facturación | Vertical (solo columnas de interoperabilidad) |
| **MongoDB 7** | Reportes y estadísticas con datos desnormalizados | No relacional (documentos) |

PostgreSQL es el **centro** del sistema y se comunica con los otros dos motores por medio de *Foreign Data Wrappers* (FDW):
- `tds_fdw` hacia SQL Server: lee tablas y ejecuta procedimientos almacenados.
- `mongo_fdw` hacia MongoDB: inserta, actualiza y borra documentos.

---

## 2. Arquitectura

![Arquitectura y mapa de conexiones](docs/diagramas/01_arquitectura.png)

Los tres servidores corren en contenedores Docker dentro de la misma red privada (`red_medica`). Dentro de la red se llaman por su nombre de servicio (`postgres`, `sqlserver`, `mongodb`), y desde Windows se accede por puertos distintos a los de siempre, para no chocar con instalaciones locales:

| Servidor | Contenedor | Base de datos | Puerto en Windows | Puerto en la red Docker |
|---|---|---|---|---|
| PostgreSQL 16 | `pg_clinica` | `clinica_db` | 5433 | 5432 |
| SQL Server 2022 | `mssql_integra` | `IntegracionMedica` | 1434 | 1433 |
| MongoDB 7 | `mongo_reportes` | `reportes_medicos` | 27018 | 27017 |

**Canales de comunicación:**

| Origen → Destino | Mecanismo | Usuario remoto | Qué se hace |
|---|---|---|---|
| PostgreSQL → SQL Server (lectura) | `tds_fdw`, tablas foráneas del esquema `mssql` | `usr_fdw_pg_mssql` | Leer el estado de facturación, convenios y resúmenes |
| PostgreSQL → SQL Server (escritura) | `tds_fdw` ejecutando `EXEC dbo.sp_registrar_*` | `usr_fdw_pg_mssql` | Registrar pacientes nuevos y facturas de estudios |
| PostgreSQL → MongoDB | `mongo_fdw`, tablas foráneas del esquema `mongo` | `usr_fdw_pg_mongo` | Exportar estudios, resúmenes e indicadores |
| Aplicación web → PostgreSQL | Conexión directa, `scram-sha-256` | `usr_api_web` | Consultar las vistas del esquema `api_web` |
| Aplicación móvil → PostgreSQL | Conexión directa, `scram-sha-256` | `usr_api_mobile` | Consultar las vistas del esquema `api_movil` |

---

## 3. Estructura del repositorio

```
├── docker-compose.yml                 Los 3 servidores, la red y los volumenes
├── instalar.ps1                       Instalacion automatica (ejecuta todo en orden)
├── reporte.ps1                        Demostracion completa como pagina web
├── README.md                          Esta guia
├── postgres/
│   ├── Dockerfile                     PostgreSQL 16 + tds_fdw + mongo_fdw
│   ├── config/
│   │   ├── postgresql.conf            Parametros del servidor
│   │   └── pg_hba.conf                Reglas de autenticacion
│   └── scripts/
│       ├── 01_modelo_segmentado.sql   Tablas y fragmentos horizontales
│       ├── 02_datos_prueba.sql        Datos de ejemplo
│       ├── 03_roles.sql               Roles internos y externos
│       ├── 04_fdw_sqlserver.sql       Canal tds_fdw (servidor, mapeos, tablas foraneas)
│       ├── 05_fdw_mongodb.sql         Canal mongo_fdw
│       ├── 06_operaciones_distribuidas.sql  Funciones y procedimientos distribuidos
│       ├── 07_vistas_api.sql          Vistas para web y movil + permisos
│       ├── 08_consultas_prueba.sql    Demostracion de todas las operaciones
│       └── 09_pruebas_pgadmin.sql     Pruebas por bloques para ejecutar en pgAdmin
├── sqlserver/
│   ├── 01_crear_bd.sql                Base y tablas (segmentacion vertical)
│   ├── 02_datos_prueba.sql
│   ├── 03_procedimientos.sql          Procedimientos almacenados
│   ├── 04_seguridad.sql               Login y rol del FDW
│   └── 05_consultas_prueba.sql
├── mongodb/
│   ├── 01_crear_bd.js                 Colecciones, validacion e indices
│   ├── 02_seguridad.js                Roles y usuarios
│   ├── 03_consultas_analiticas.js     Agregaciones (por medico y tipo de estudio)
│   └── 04_prueba_permisos.js          Prueba de permisos de usr_api_mobile
└── docs/
    ├── Documentacion_Proyecto2.docx   Documentacion formal del proyecto
    ├── diagramas/                     Diagramas (.svg editable y .png)
    ├── evidencia/                     Capturas de la ejecucion real de cada operacion
    └── render_diagramas.ps1           Convierte los .svg a .png
```

---

## 4. Instalación paso a paso

### 4.1 Requisitos

- Windows 10/11 con **Docker Desktop** encendido. No hace falta instalar PostgreSQL, SQL Server ni MongoDB: vienen dentro de los contenedores.
- Unos **10 GB libres** en disco.
- Conexión a internet la primera vez, para descargar las imágenes (~2.5 GB en total). Después ya no se descarga nada.

### 4.2 Instalar

Desde la carpeta del proyecto, en PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File .\instalar.ps1
```

La primera vez tarda unos minutos, según la velocidad de internet. El script hace lo siguiente:

| Paso | Qué hace |
|---|---|
| 1 | Descarga las 3 imágenes y levanta los contenedores. La de PostgreSQL (con `tds_fdw` y `mongo_fdw` ya compilados) se baja de GitHub Container Registry: `ghcr.io/danny7w7-coder/clinica-postgres:1.0`. Si no se puede descargar, se construye desde `postgres/Dockerfile` |
| 2 | Espera a que los 3 servidores respondan |
| 3 | SQL Server: ejecuta `sqlserver/01` a `04` (base, datos, procedimientos, seguridad) |
| 4 | MongoDB: ejecuta `mongodb/01` y `02` (colecciones y usuarios) |
| 5 | PostgreSQL: ejecuta `postgres/scripts/01` a `07` (modelo, datos, roles, FDW, funciones, vistas) |
| 6 | Carga inicial: exporta los estudios a MongoDB y sincroniza los convenios desde SQL Server |

Si un script falla, la instalación se detiene y muestra cuál fue. Si el sistema ya estaba instalado, el script lo indica y no modifica nada.

### 4.3 Reinstalar desde cero

```powershell
powershell -ExecutionPolicy Bypass -File .\instalar.ps1 -Reiniciar   # borra contenedores Y datos, y reinstala
```

> Reinstalar es necesario antes de grabar el video: la demostración registra el resultado de la orden 13 y al paciente 13, y esas operaciones solo se pueden hacer una vez.

### 4.4 Conectarse con herramientas gráficas

| Motor | Herramienta sugerida | Servidor | Usuario / contraseña |
|---|---|---|---|
| PostgreSQL | pgAdmin o DBeaver | `localhost`, puerto `5433`, base `clinica_db` | `postgres` / `Admin_Pg2026` |
| SQL Server | SSMS o Azure Data Studio | `localhost,1434` (marcar *Trust server certificate*) | `sa` / `Admin_Sql2026!` |
| MongoDB | MongoDB Compass | `mongodb://admin:Admin_Mongo2026@localhost:27018/` | `admin` / `Admin_Mongo2026` |

Las aplicaciones usarían `usr_api_web` / `Api_Web2026` o `usr_api_mobile` / `Api_Mobile2026` contra PostgreSQL.

> Las contraseñas están escritas en los scripts para que el proyecto se pueda revisar fácilmente. En un sistema real irían en variables de entorno o en un gestor de secretos.

---

## 5. Modelo de datos y segmentación

![Modelo de datos y segmentación](docs/diagramas/02_modelo_segmentacion.png)

### 5.1 PostgreSQL — segmentación horizontal

Las tablas con más movimiento se dividen **por filas** según la sucursal (`id_sucursal`), con particionamiento declarativo (`PARTITION BY LIST`):

| Tabla padre | San José (1) | Alajuela (2) | Cartago (3) |
|---|---|---|---|
| `pacientes` | `pacientes_san_jose` | `pacientes_alajuela` | `pacientes_cartago` |
| `citas` | `citas_san_jose` | `citas_alajuela` | `citas_cartago` |
| `ordenes_medicas` | `ordenes_medicas_san_jose` | `ordenes_medicas_alajuela` | `ordenes_medicas_cartago` |
| `resultados_estudios` | `resultados_estudios_san_jose` | `resultados_estudios_alajuela` | `resultados_estudios_cartago` |

Ejemplo (de [01_modelo_segmentado.sql](postgres/scripts/01_modelo_segmentado.sql)):

```sql
CREATE TABLE pacientes (
    id_paciente  SERIAL,
    id_sucursal  SMALLINT NOT NULL REFERENCES sucursales(id_sucursal),
    ...
    PRIMARY KEY (id_paciente, id_sucursal)
) PARTITION BY LIST (id_sucursal);

CREATE TABLE pacientes_san_jose PARTITION OF pacientes FOR VALUES IN (1);
CREATE TABLE pacientes_alajuela PARTITION OF pacientes FOR VALUES IN (2);
CREATE TABLE pacientes_cartago  PARTITION OF pacientes FOR VALUES IN (3);
```

Cómo funciona:
- **Inserción:** se inserta en la tabla padre y PostgreSQL guarda la fila en el fragmento que le corresponde.
- **Consulta:** si se filtra por `id_sucursal`, PostgreSQL lee **solo un fragmento** (*partition pruning*). Se puede comprobar con `EXPLAIN`.
- **Integridad referencial:** la llave primaria incluye la columna de partición, y las llaves foráneas son compuestas, por ejemplo `(id_paciente, id_sucursal)`.
- **Catálogos sin segmentar:** `sucursales`, `medicos`, `tipos_estudio` y `usuarios_admin` son pequeños y todas las sucursales los usan.
- **`convenios_cache`:** copia local de los convenios de SQL Server, que se llena por sincronización.

El resultado de cada estudio se guarda en una columna `JSONB`, porque cada tipo de estudio tiene campos distintos (un hemograma no se parece a un ultrasonido).

### 5.2 SQL Server — segmentación vertical

El paciente completo vive en PostgreSQL. SQL Server guarda **solo las columnas** que necesitan los sistemas externos:

| Tabla | Columnas que SÍ se guardan | Columnas que NO se guardan |
|---|---|---|
| `paciente_integracion` | `id_paciente`, `id_aseguradora`, `codigo_externo`, `estado_facturacion` | cédula, nombre, apellidos, fecha de nacimiento, teléfono, correo |
| `facturas_externas` | `id_estudio`, `id_paciente`, `codigo_estudio`, `costo`, `fecha`, `codigo_institucion`, `estado` | resultado clínico, diagnóstico, médico |

Otras tablas: `aseguradoras`, `convenios` y `resumen_facturacion`. Esta última la llena un procedimiento almacenado.

Las **llaves comunes** `id_paciente`, `codigo_estudio` e `id_estudio` permiten unir los fragmentos desde PostgreSQL.

Procedimientos almacenados ([03_procedimientos.sql](sqlserver/03_procedimientos.sql)):

| Procedimiento | Qué hace | Quién lo usa |
|---|---|---|
| `sp_generar_resumen_facturacion` | Calcula, por paciente, el total facturado, pagado y pendiente, y lo guarda en `resumen_facturacion` | Interno y `sp_registrar_factura` |
| `sp_actualizar_estado_facturacion` | Regla de negocio: con facturas rechazadas el paciente queda MOROSO; con pendientes, PENDIENTE; si no, AL_DIA | Interno y `sp_registrar_factura` |
| `sp_registrar_paciente_integracion` | Crea o actualiza el fragmento vertical de un paciente | PostgreSQL (vía `tds_fdw`) |
| `sp_registrar_factura` | Crea la factura de un estudio y recalcula los resúmenes | PostgreSQL (vía `tds_fdw`) |

### 5.3 MongoDB — modelo no relacional

| Colección | Contenido | Quién la llena |
|---|---|---|
| `resultados_estudios` | Un documento por estudio, con paciente, médico, tipo, resultado (subdocumento), sucursal y costo | `mongo.fn_exportar_resultados()` / `mongo.fn_publicar_estudio()` |
| `resumen_paciente` | Un documento por paciente con totales, último estudio y último diagnóstico | `mongo.fn_actualizar_resumen_paciente()` |
| `indicadores_mensuales` | Cantidad de estudios, pacientes e ingresos por mes, sucursal y tipo | `mongo.fn_exportar_indicadores_mensuales()` |
| `reporte_medico_tipo` | Resultado de la agregación por médico y tipo de estudio | `03_consultas_analiticas.js` (`$merge`) |

Ejemplo real de documento, tal como lo deja `mongo_fdw`:

```json
{
  "id_estudio": 1,
  "id_paciente": 1,
  "paciente": "José Pérez Rodríguez",
  "medico": "Dra. Ana Rojas Solís",
  "especialidad": "Patología Clínica",
  "codigo_estudio": "LAB-HEM",
  "tipo": "Laboratorio",
  "estudio": "Hemograma completo",
  "resultado": { "plaquetas": 250000, "unidad_hb": "g/dL", "leucocitos": 7200, "hemoglobina": 14.2 },
  "diagnostico": "Hemograma dentro de rangos normales",
  "fecha": "2026-09-02T10:00:00Z",
  "sucursal": "San Jose",
  "costo": 12000
}
```

La colección `resultados_estudios` tiene un validador `$jsonSchema` con campos obligatorios y varios índices: `id_estudio` único, `medico + tipo` y `sucursal + fecha`.

---

## 6. Canales FDW

### 6.1 Configuración del servidor PostgreSQL

**[postgresql.conf](postgres/config/postgresql.conf)** (solo se listan los parámetros que cambian):

| Parámetro | Valor | Para qué |
|---|---|---|
| `listen_addresses` | `'*'` | Aceptar conexiones de la red Docker |
| `password_encryption` | `scram-sha-256` | Guardar las contraseñas cifradas con SCRAM |
| `log_connections` / `log_disconnections` | `on` | Ver en la bitácora quién se conecta |
| `log_statement` | `'ddl'` | Registrar `CREATE`, `ALTER` y `DROP` |
| `timezone` | `America/Costa_Rica` | Hora local |

**[pg_hba.conf](postgres/config/pg_hba.conf)** (se lee de arriba hacia abajo y gana la primera regla que coincide):

| Tipo | Base | Usuario | Método | Motivo |
|---|---|---|---|---|
| local | all | `postgres` | `trust` | Administración dentro del contenedor |
| host | all | `usr_fdw_pg_mssql`, `usr_fdw_pg_mongo` | `reject` | Roles internos: nadie entra con ellos desde afuera |
| host | `clinica_db` | `usr_api_web`, `usr_api_mobile` | `scram-sha-256` | Las apps solo entran a su base, con contraseña cifrada |
| host | all | `postgres` | `scram-sha-256` | Administración remota (pgAdmin) |
| host | all | all | `reject` | Cualquier otra conexión se rechaza |

Los dos archivos se montan en el contenedor y se activan desde [docker-compose.yml](docker-compose.yml):

```yaml
command: >
  postgres -c config_file=/etc/postgresql/postgresql.conf
           -c hba_file=/etc/postgresql/pg_hba.conf
```

### 6.2 Instalación de las extensiones

En [postgres/Dockerfile](postgres/Dockerfile), sobre `postgres:16-trixie` (Debian 13):

| Extensión | Cómo se instala | Detalles |
|---|---|---|
| `tds_fdw` | Paquete `postgresql-16-tds-fdw` del repositorio oficial de PostgreSQL | Usa FreeTDS. Se configura `client charset = UTF-8` (para los acentos) y la fecha en formato ISO en `locales.conf` |
| `mongo_fdw` | Se compila la versión estable `REL-5_5_3` | Primero se compila el driver de MongoDB `libmongoc` **1.30.2**. La librería `json-c` se compila dentro de la extensión y permite enviar columnas `JSON` como subdocumentos |

### 6.3 Canal PostgreSQL ↔ SQL Server (`tds_fdw`)

Script: [04_fdw_sqlserver.sql](postgres/scripts/04_fdw_sqlserver.sql)

```sql
CREATE EXTENSION tds_fdw;

-- 1) Donde esta el servidor remoto
CREATE SERVER srv_mssql_integracion FOREIGN DATA WRAPPER tds_fdw
    OPTIONS (servername 'sqlserver', port '1433',
             database 'IntegracionMedica', tds_version '7.4');

-- 2) Con que usuario se entra
CREATE USER MAPPING FOR usr_fdw_pg_mssql SERVER srv_mssql_integracion
    OPTIONS (username 'usr_fdw_pg_mssql', password '...');

-- 3) Tablas locales que apuntan a las remotas
CREATE FOREIGN TABLE mssql.paciente_integracion (
    id_paciente INT, id_aseguradora INT,
    codigo_externo VARCHAR(20), estado_facturacion VARCHAR(15)
) SERVER srv_mssql_integracion
  OPTIONS (schema_name 'dbo', table_name 'paciente_integracion');
```

Tablas foráneas del esquema `mssql`: `aseguradoras`, `paciente_integracion`, `convenios`, `facturas_externas`, `resumen_facturacion` y `v_facturacion_aseguradora` (una vista remota).

**Lectura:** se consulta con `SELECT` como cualquier tabla.

**Escritura:** `tds_fdw` no permite `INSERT` en tablas foráneas, pero una tabla foránea puede definirse con la opción `query`, y esa consulta se ejecuta en SQL Server al hacer `SELECT`. La función `mssql.fn_ejecutar_procedimiento` aprovecha esto para ejecutar un procedimiento almacenado remoto:

```sql
-- 1. tabla foranea temporal cuya "consulta" es el procedimiento
CREATE FOREIGN TABLE mssql.tmp_exec_123 (resultado VARCHAR(500))
    SERVER srv_mssql_integracion
    OPTIONS (query 'EXEC dbo.sp_registrar_factura @id_estudio = 13, ...',
             use_remote_estimate 'false');
-- 2. al leerla, SQL Server ejecuta el procedimiento y devuelve 'OK: ...'
SELECT resultado FROM mssql.tmp_exec_123;
-- 3. se borra
DROP FOREIGN TABLE mssql.tmp_exec_123;
```

Así, la escritura en SQL Server queda **limitada a dos procedimientos**: el usuario remoto sigue sin poder hacer `INSERT`, `UPDATE` ni `DELETE` directo.

### 6.4 Canal PostgreSQL → MongoDB (`mongo_fdw`)

Script: [05_fdw_mongodb.sql](postgres/scripts/05_fdw_mongodb.sql)

```sql
CREATE EXTENSION mongo_fdw;

CREATE SERVER srv_mongo_reportes FOREIGN DATA WRAPPER mongo_fdw
    OPTIONS (address 'mongodb', port '27017',
             authentication_database 'reportes_medicos');

CREATE USER MAPPING FOR usr_fdw_pg_mongo SERVER srv_mongo_reportes
    OPTIONS (username 'usr_fdw_pg_mongo', password '...');

CREATE FOREIGN TABLE mongo.resultados_estudios (
    _id NAME,                 -- obligatorio y primero; MongoDB genera el ObjectId
    id_estudio INT, paciente TEXT, ..., resultado JSON, fecha TIMESTAMP, ...
) SERVER srv_mongo_reportes
  OPTIONS (database 'reportes_medicos', collection 'resultados_estudios');
```

Tablas foráneas del esquema `mongo`: `resultados_estudios`, `resumen_paciente` e `indicadores_mensuales`. `mongo_fdw` permite `SELECT`, `INSERT`, `UPDATE` y `DELETE`.

---

## 7. Roles y seguridad

### 7.1 Perfiles internos del clúster

| Perfil | Dónde existe | Autenticación | Permisos |
|---|---|---|---|
| `usr_fdw_pg_mssql` | PostgreSQL (rol `NOLOGIN`) y SQL Server (login) | SQL Server: contraseña con `CHECK_POLICY = ON`. PostgreSQL: `reject` en `pg_hba.conf` | **SQL Server**, rol `rol_fdw_integracion`: `SELECT` en las 6 tablas/vistas de integración, `EXECUTE` en `sp_registrar_paciente_integracion` y `sp_registrar_factura`, y `DENY INSERT/UPDATE/DELETE` sobre el esquema `dbo`. **PostgreSQL:** dueño de las tablas foráneas `mssql.*` y `SELECT` en algunas tablas locales |
| `usr_fdw_pg_mongo` | PostgreSQL (rol `NOLOGIN`) y MongoDB (usuario) | MongoDB: SCRAM-SHA-256. PostgreSQL: `reject` | **MongoDB**, rol propio `rol_fdw_escritura`: `find`, `insert`, `update` y `remove` **solo** en las 3 colecciones (no puede borrar colecciones ni crear usuarios). **PostgreSQL:** dueño de las tablas foráneas `mongo.*` y `SELECT` en las tablas locales que exporta |

**¿Cómo se usan si no pueden iniciar sesión?**
- Las funciones que tocan otro motor son `SECURITY DEFINER` y su dueño es el rol interno. Quien las ejecute se conecta al motor remoto **como el rol interno**, con sus permisos mínimos.
- En SQL Server, los procedimientos pueden insertar aunque el rol tenga `DENY INSERT` gracias al **encadenamiento de propiedad**: el procedimiento y las tablas tienen el mismo dueño (`dbo`), así que SQL Server no revisa los permisos de las tablas.
- `tds_fdw` busca el `USER MAPPING` del usuario que hace la consulta. Por eso `usr_api_web` y `usr_api_mobile` también tienen uno, pero apunta al **mismo login remoto** `usr_fdw_pg_mssql`: las apps nunca tienen en SQL Server más permisos que el perfil interno. El administrador (`postgres`) también tiene mapeos hacia los mismos usuarios internos, para poder ver las tablas remotas desde pgAdmin.

### 7.2 Perfiles externos (aplicaciones)

| Política | `usr_api_web` | `usr_api_mobile` |
|---|---|---|
| Qué puede ver en PostgreSQL | Esquema `api_web`: 4 vistas completas | Esquema `api_movil`: 3 vistas simplificadas (sin cédula, correo ni JSON) |
| Tablas base | Sin acceso | Sin acceso |
| Solo lectura | `default_transaction_read_only = on` | `default_transaction_read_only = on` |
| Tiempo máximo por consulta | 30 s | 5 s |
| Conexiones simultáneas | 50 | 20 |
| Vencimiento de la contraseña | 2027-12-31 | 2027-12-31 |
| Autenticación | `scram-sha-256`, solo a `clinica_db` | `scram-sha-256`, solo a `clinica_db` |
| MongoDB | Rol `read` en toda `reportes_medicos` | Rol `rol_movil_lectura`: `find` solo en `resumen_paciente` e `indicadores_mensuales` |

Vistas disponibles ([07_vistas_api.sql](postgres/scripts/07_vistas_api.sql)):

| Vista | Datos | Origen |
|---|---|---|
| `api_web.v_pacientes_facturacion` | Paciente, sucursal, aseguradora, estado y saldos de facturación | Local + SQL Server |
| `api_web.v_estudios` | Estudios con resultado completo y diagnóstico | Local |
| `api_web.v_citas` | Citas con médico y sucursal | Local |
| `api_web.v_cobertura_ordenes` | Costo de cada orden, cobertura del convenio y monto a pagar por el paciente | Local + SQL Server |
| `api_movil.v_mis_citas` | Fecha, médico, sucursal y estado | Local |
| `api_movil.v_mis_resultados` | Estudio, fecha y diagnóstico | Local |
| `api_movil.v_estado_cuenta` | Estado de facturación y saldo pendiente | SQL Server |

---

## 8. Flujos de datos

![Flujo de la transacción distribuida](docs/diagramas/03_flujo_transaccion.png)

Todas las operaciones que escriben en más de un motor siguen el mismo patrón:

1. Se guarda el dato en **PostgreSQL**, que es la fuente de verdad.
2. Se ejecuta **`COMMIT`**: el dato queda confirmado.
3. Recién después se **propaga** a MongoDB y/o SQL Server.
4. Si un motor remoto falla, el dato de PostgreSQL no se pierde: se muestra un `WARNING` con la función para reintentar. Las funciones de propagación son **idempotentes**, así que reintentarlas no duplica datos.

### Flujo A — Carga inicial (al instalar)

```sql
SELECT mongo.fn_exportar_resultados();             -- 12 estudios + 12 resumenes  -> MongoDB
SELECT mongo.fn_exportar_indicadores_mensuales();  -- 10 indicadores              -> MongoDB
SELECT mssql.fn_sincronizar_convenios();           -- 15 convenios SQL Server     -> convenios_cache
```

### Flujo B — Registrar un paciente (PostgreSQL → SQL Server)

```sql
CALL sp_registrar_paciente(2, '2-2222-0013', 'Sebastián', 'Rojas Umaña', '2000-02-14',
                           'M', '8888-0013', 'sebastian.rojas@correo.com', 2);
```

1. `INSERT` en `pacientes`: la fila queda en el fragmento `pacientes_alajuela`.
2. `COMMIT`.
3. `mssql.fn_registrar_paciente_integracion(13, 2)` ejecuta en SQL Server `sp_registrar_paciente_integracion`, que crea el fragmento vertical con el código `AVP-000013`.

### Flujo C — Registrar un resultado (PostgreSQL → MongoDB y SQL Server)

```sql
CALL sp_registrar_resultado(13, 1, 1, '{"glicemia": 92, "unidad": "mg/dL"}', 'Glicemia normal');
```

1. Se valida que la orden esté pendiente, se inserta el resultado en `resultados_estudios_san_jose` y la orden pasa a `COMPLETADA`.
2. `COMMIT`.
3. **MongoDB:** `mongo.fn_publicar_estudio(13)` inserta el documento del estudio y actualiza `resumen_paciente` (de 1 a 2 estudios).
4. **SQL Server:** `mssql.fn_registrar_factura(13)` ejecuta `sp_registrar_factura`, que crea la factura PENDIENTE y recalcula el estado y los resúmenes de facturación.

### Flujo D — Lectura combinada para la web (SQL Server → PostgreSQL)

`api_web.v_pacientes_facturacion` une `pacientes` (local) con `mssql.paciente_integracion` y `mssql.resumen_facturacion` (remotas). Cada vez que la web consulta la vista, los datos de SQL Server se leen en ese momento.

### Flujo E — Reportes (MongoDB)

Los reportes se calculan en MongoDB con *aggregation pipelines* sobre los documentos desnormalizados, sin cargar a PostgreSQL ([03_consultas_analiticas.js](mongodb/03_consultas_analiticas.js)).

---

## 9. Operaciones requeridas

| # | Operación pedida | Solución | Dónde |
|---|---|---|---|
| 1 | Consulta en PostgreSQL con la información del paciente y su estado de facturación desde SQL Server | `JOIN` entre `pacientes` y `mssql.paciente_integracion` / `mssql.aseguradoras`, más `mssql.resumen_facturacion` | [08_consultas_prueba.sql](postgres/scripts/08_consultas_prueba.sql) |
| 2 | Inserción en PostgreSQL que, tras confirmarse, actualiza un documento resumen en MongoDB | `sp_registrar_resultado`: `INSERT` → `COMMIT` → `fn_publicar_estudio` actualiza `resumen_paciente`. Además crea la factura en SQL Server | [06_operaciones_distribuidas.sql](postgres/scripts/06_operaciones_distribuidas.sql) |
| 3 | Vista en PostgreSQL que combina datos locales y remotos (SQL Server) para la web | `api_web.v_pacientes_facturacion` y `api_web.v_cobertura_ordenes` | [07_vistas_api.sql](postgres/scripts/07_vistas_api.sql) |
| 4 | Exportación de datos hacia MongoDB para reportes agregados | `mongo.fn_exportar_resultados()` y `mongo.fn_exportar_indicadores_mensuales()` | [06_operaciones_distribuidas.sql](postgres/scripts/06_operaciones_distribuidas.sql) |
| 5 | Consulta analítica en MongoDB con agregaciones por médico y tipo de estudio | `$group` por `{medico, tipo}` con cantidad, ingreso y promedio; ranking de médicos; rendimiento por sucursal | [03_consultas_analiticas.js](mongodb/03_consultas_analiticas.js) |
| Extra | Escritura PostgreSQL → SQL Server | `sp_registrar_paciente` y la factura de `sp_registrar_resultado`, mediante procedimientos remotos | [06_operaciones_distribuidas.sql](postgres/scripts/06_operaciones_distribuidas.sql) |

---

## 10. Demostración y resultados esperados

**Forma recomendada: reporte en el navegador.** Ejecuta las 9 pruebas en los tres servidores y abre una página web con tablas, colores por motor y el resultado esperado de cada paso:

```powershell
powershell -ExecutionPolicy Bypass -File .\reporte.ps1
```

**Desde pgAdmin:** abra `postgres/scripts/09_pruebas_pgadmin.sql` en el *Query Tool*, seleccione un bloque y presione F5. Desde PostgreSQL se ven los tres motores: las tablas normales, el esquema `mssql` (datos de SQL Server) y el esquema `mongo` (datos de MongoDB).

Forma detallada (scripts completos), **en este orden** después de una instalación limpia:

```powershell
# 1. PostgreSQL: todas las operaciones distribuidas
docker exec -it pg_clinica psql -U postgres -d clinica_db -f /scripts/08_consultas_prueba.sql

# 2. SQL Server: segmentacion vertical, datos que llegaron desde PostgreSQL y permisos
docker exec -it mssql_integra /opt/mssql-tools18/bin/sqlcmd -C -S localhost -U sa -P "Admin_Sql2026!" -i /scripts/05_consultas_prueba.sql

# 3. MongoDB: consultas analiticas
docker exec -it mongo_reportes mongosh -u admin -p Admin_Mongo2026 /scripts/03_consultas_analiticas.js

# 4. MongoDB: permisos del usuario movil
docker exec -it mongo_reportes mongosh -u usr_api_mobile -p Api_Mobile2026 --authenticationDatabase reportes_medicos /scripts/04_prueba_permisos.js
```

Resultados verificados:

| Prueba | Resultado esperado |
|---|---|
| Filas por fragmento | 4 pacientes en cada sucursal |
| `EXPLAIN ... WHERE id_sucursal = 3` | `Seq Scan on pacientes_cartago`: solo lee un fragmento |
| Operación 1 | 12 pacientes con código externo, estado de facturación y aseguradora |
| Operación 4 | 12 estudios y 10 indicadores exportados |
| Operación 2 | `resumen_paciente` del paciente 1 pasa de 1 a 2 estudios; aparece la factura del estudio 13 en SQL Server |
| Operación extra | El paciente 13 queda en `pacientes_alajuela` y en `paciente_integracion` con el código `AVP-000013` |
| Operación 3 | `usr_api_web` ve 13 pacientes con datos de facturación |
| Seguridad PostgreSQL | `usr_api_mobile` recibe `permission denied` en `pacientes` y en `api_web` |
| Seguridad SQL Server | `DELETE` como `usr_fdw_pg_mssql` → error 229 |
| Seguridad MongoDB | `usr_api_mobile` → `Unauthorized` en `resultados_estudios` y al insertar |
| Operación 5 | Estudios por médico y tipo, ranking de médicos y rendimiento por sucursal |

> Los mensajes `NOTICE: tds_fdw: Query executed correctly` son informativos de `tds_fdw` y no son errores.

---

## 11. Solución de problemas

| Síntoma | Causa | Solución |
|---|---|---|
| `Docker Desktop is unable to start` | Disco lleno o Docker apagado | Liberar espacio y reiniciar Docker Desktop |
| `failed to solve ... read-only file system` al construir | Disco lleno durante la compilación | Liberar espacio y volver a ejecutar `instalar.ps1` |
| Un puerto ya está en uso | Otra instalación local de PostgreSQL, SQL Server o MongoDB | Cambiar el puerto del lado izquierdo en `docker-compose.yml` (ej. `"5434:5432"`) |
| `La orden 13 no existe o no esta pendiente` | La demostración ya se ejecutó | Reinstalar con `.\instalar.ps1 -Reiniciar` |
| `WARNING: MongoDB no se actualizo` / `SQL Server no se actualizo` | El motor remoto no respondió | Revisar `docker ps` y reintentar con la función que indica el mensaje |
| `user mapping not found for "..."` | Se consultó una tabla foránea con un rol sin mapeo | Usar `SET ROLE usr_fdw_pg_mssql` / `usr_fdw_pg_mongo`, o consultar a través de las vistas |

---

## 12. Referencias

- EnterpriseDB. (2025). *mongo_fdw: PostgreSQL foreign data wrapper for MongoDB* [Software]. GitHub. https://github.com/EnterpriseDB/mongo_fdw
- Microsoft. (2024). *CREATE LOGIN (Transact-SQL)*. Microsoft Learn. https://learn.microsoft.com/sql/t-sql/statements/create-login-transact-sql
- Microsoft. (2024). *Ownership chains*. Microsoft Learn. https://learn.microsoft.com/sql/relational-databases/security/authentication-access/ownership-chains
- MongoDB, Inc. (2024). *Aggregation pipeline*. MongoDB Manual. https://www.mongodb.com/docs/manual/core/aggregation-pipeline/
- MongoDB, Inc. (2024). *Role-based access control*. MongoDB Manual. https://www.mongodb.com/docs/manual/core/authorization/
- Özsu, M. T., & Valduriez, P. (2020). *Principles of distributed database systems* (4.ª ed.). Springer.
- PostgreSQL Global Development Group. (2024). *PostgreSQL 16 documentation: Table partitioning*. https://www.postgresql.org/docs/16/ddl-partitioning.html
- PostgreSQL Global Development Group. (2024). *PostgreSQL 16 documentation: The pg_hba.conf file*. https://www.postgresql.org/docs/16/auth-pg-hba-conf.html
- PostgreSQL Global Development Group. (2024). *PostgreSQL 16 documentation: CREATE FOREIGN TABLE*. https://www.postgresql.org/docs/16/sql-createforeigntable.html
- tds-fdw. (2024). *tds_fdw: PostgreSQL foreign data wrapper for Sybase and Microsoft SQL Server* [Software]. GitHub. https://github.com/tds-fdw/tds_fdw
