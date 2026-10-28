# Sistema de Gestión de Estudios Médicos Distribuido

- **Curso:** Bases de Datos II — Instituto Tecnológico de Costa Rica, Sede San Carlos
- **Profesor:** MSc. Leonardo Víquez Acuña
- **Integrantes:** Danny Jesús Gonzalez Molina · Dylan Yoel Méndez Zamora · Francisco Javier Castillo Duarte
- **Repositorio:** https://github.com/Danny7w7-coder/proyecto2Bases2
- **Documentación formal:** [docs/Documentacion_Proyecto2.docx](docs/Documentacion_Proyecto2.docx)

Este documento explica de qué trata el proyecto, cómo instalarlo y probarlo paso a paso, y cómo está diseñado por dentro.

## Contenido

**Parte I — Uso del proyecto**
1. [¿De qué trata el proyecto?](#1-de-qué-trata-el-proyecto)
2. [Conceptos básicos](#2-conceptos-básicos)
3. [Arquitectura](#3-arquitectura)
4. [Requisitos](#4-requisitos)
5. [Instalación paso a paso](#5-instalación-paso-a-paso)
6. [Comprobar que todo funciona](#6-comprobar-que-todo-funciona)
7. [Encender, apagar y reinstalar](#7-encender-apagar-y-reinstalar)
8. [Estructura del repositorio](#8-estructura-del-repositorio)

**Parte II — Diseño técnico**

9. [Modelo de datos y segmentación](#9-modelo-de-datos-y-segmentación)
10. [Canales FDW](#10-canales-fdw)
11. [Roles y seguridad](#11-roles-y-seguridad)
12. [Flujos de datos](#12-flujos-de-datos)
13. [Operaciones requeridas](#13-operaciones-requeridas)
14. [Solución de problemas](#14-solución-de-problemas)
15. [Referencias](#15-referencias)

---

# Parte I — Uso del proyecto

## 1. ¿De qué trata el proyecto?

Una red de clínicas (San José, Alajuela y Cartago) realiza estudios médicos: exámenes de laboratorio, radiografías y ultrasonidos. Sus datos tienen tres usos muy distintos, y por eso se guardan en **tres motores de bases de datos**, cada uno con su propósito:

| Motor | Para qué se usa | Cómo se dividen los datos |
|---|---|---|
| **PostgreSQL 16** | Operación diaria: pacientes, citas, órdenes médicas, resultados y diagnósticos | **Horizontal**: cada sucursal tiene su propio fragmento de filas |
| **SQL Server 2022** | Integración con aseguradoras y facturación | **Vertical**: solo guarda las columnas que necesitan las aseguradoras |
| **MongoDB 7** | Reportes y estadísticas | Documentos (no relacional) |

Los tres motores **se comunican entre sí**. PostgreSQL es el centro del sistema:
- **Lee** de SQL Server el estado de facturación de cada paciente.
- **Escribe** en SQL Server, por medio de procedimientos almacenados, los pacientes nuevos y las facturas.
- **Envía** a MongoDB los estudios y los indicadores para los reportes.

Además, cada usuario **solo puede hacer lo que le corresponde**: la aplicación web y la móvil solo leen sus vistas, y los usuarios internos que conectan los motores tienen los permisos mínimos.

> **Alcance:** el proyecto construye las bases de datos, su comunicación y su seguridad. **No incluye** la aplicación web ni la móvil: estas están representadas por los usuarios `usr_api_web` y `usr_api_mobile` y por las vistas que tienen permitido consultar.

---

## 2. Conceptos básicos

| Concepto | Qué significa en este proyecto |
|---|---|
| **Base de datos distribuida** | Los datos de un mismo sistema están repartidos en varios servidores que trabajan juntos |
| **Segmentación horizontal** | Una tabla se divide **por filas**. Ejemplo: los pacientes de San José en un fragmento y los de Cartago en otro |
| **Segmentación vertical** | Una tabla se divide **por columnas**. Ejemplo: SQL Server solo guarda la aseguradora y el estado de facturación del paciente, no su nombre ni su cédula |
| **FDW (Foreign Data Wrapper)** | Extensión de PostgreSQL que permite consultar tablas de **otro servidor** como si fueran locales. Se usan `tds_fdw` (hacia SQL Server) y `mongo_fdw` (hacia MongoDB) |
| **Tabla foránea** | Tabla que se ve en PostgreSQL pero cuyos datos viven en otro servidor |
| **Docker / contenedor** | Cada motor corre dentro de un contenedor: un "paquete" que ya trae el programa instalado y configurado. Así no hay que instalar PostgreSQL, SQL Server ni MongoDB en la computadora |
| **Imagen** | La plantilla con la que se crea un contenedor. La de PostgreSQL de este proyecto (con los FDW ya compilados) está publicada en GitHub |

---

## 3. Arquitectura

![Arquitectura y mapa de conexiones](docs/diagramas/01_arquitectura.png)

Los tres servidores corren en contenedores Docker dentro de la misma red privada (`red_medica`). Dentro de esa red se llaman por su nombre (`postgres`, `sqlserver`, `mongodb`). Desde Windows se entra por puertos distintos a los habituales, para no chocar con otras instalaciones:

| Servidor | Contenedor | Base de datos | Puerto en Windows | Puerto en la red Docker |
|---|---|---|---|---|
| PostgreSQL 16 | `pg_clinica` | `clinica_db` | **5433** | 5432 |
| SQL Server 2022 | `mssql_integra` | `IntegracionMedica` | **1434** | 1433 |
| MongoDB 7 | `mongo_reportes` | `reportes_medicos` | **27018** | 27017 |

**Quién se comunica con quién:**

| Origen → Destino | Mecanismo | Usuario que se usa | Qué se hace |
|---|---|---|---|
| PostgreSQL → SQL Server (lectura) | `tds_fdw`, tablas foráneas del esquema `mssql` | `usr_fdw_pg_mssql` | Leer el estado de facturación, convenios y resúmenes |
| PostgreSQL → SQL Server (escritura) | `tds_fdw` ejecutando procedimientos almacenados | `usr_fdw_pg_mssql` | Registrar pacientes nuevos y facturas |
| PostgreSQL → MongoDB | `mongo_fdw`, tablas foráneas del esquema `mongo` | `usr_fdw_pg_mongo` | Exportar estudios, resúmenes e indicadores |
| Aplicación web → PostgreSQL | Conexión directa con contraseña cifrada | `usr_api_web` | Consultar las vistas del esquema `api_web` |
| Aplicación móvil → PostgreSQL | Conexión directa con contraseña cifrada | `usr_api_mobile` | Consultar las vistas del esquema `api_movil` |

SQL Server y MongoDB no se conectan entre sí: toda la comunicación pasa por PostgreSQL.

---

## 4. Requisitos

- **Windows 10 u 11** con **[Docker Desktop](https://www.docker.com/products/docker-desktop/)** instalado y encendido.
- Unos **10 GB libres** en disco.
- **Internet** la primera vez, para descargar las imágenes (unos 2.5 GB). Después ya no se descarga nada.

**No hace falta instalar PostgreSQL, SQL Server ni MongoDB**: vienen dentro de los contenedores.

Opcional, para ver los datos con ventanas en lugar de la terminal:

| Motor | Programa |
|---|---|
| PostgreSQL | [pgAdmin](https://www.pgadmin.org/download/) |
| SQL Server | [SQL Server Management Studio (SSMS)](https://aka.ms/ssmsfullsetup) o la extensión *mssql* de VS Code |
| MongoDB | [MongoDB Compass](https://www.mongodb.com/try/download/compass) |

---

## 5. Instalación paso a paso

### Paso 1 — Encender Docker Desktop
Abrir Docker Desktop y esperar a que indique que está funcionando (*Engine running*).

### Paso 2 — Descargar el proyecto
Con Git:
```powershell
git clone https://github.com/Danny7w7-coder/proyecto2Bases2.git
cd proyecto2Bases2
```
O sin Git: en la página del repositorio, **Code → Download ZIP**, descomprimir y abrir PowerShell dentro de la carpeta.

### Paso 3 — Ejecutar el instalador
```powershell
powershell -ExecutionPolicy Bypass -File .\instalar.ps1
```

La primera vez tarda unos minutos. El script hace todo en orden:

| Paso | Qué hace |
|---|---|
| 1 | Descarga las 3 imágenes y levanta los contenedores. La de PostgreSQL se descarga ya lista desde GitHub (`ghcr.io/danny7w7-coder/clinica-postgres:1.0`); si no se pudiera descargar, se construye desde `postgres/Dockerfile` |
| 2 | Espera a que los 3 servidores respondan |
| 3 | **SQL Server:** crea la base, los datos de prueba, los procedimientos y la seguridad (`sqlserver/01` a `04`) |
| 4 | **MongoDB:** crea las colecciones, los roles y los usuarios (`mongodb/01` y `02`) |
| 5 | **PostgreSQL:** crea el modelo, los datos, los roles, los canales FDW, las funciones y las vistas (`postgres/scripts/01` a `07`) |
| 6 | **Carga inicial:** envía los estudios a MongoDB y copia los convenios desde SQL Server |

### Paso 4 — Verificar el final
Al terminar, el instalador muestra una tabla como esta:

```
 estudios | indicadores | convenios
----------+-------------+-----------
       12 |          10 |        15
```

Eso significa que los tres servidores están instalados y comunicados: se enviaron 12 estudios y 10 indicadores a MongoDB y se leyeron 15 convenios de SQL Server.

> Si un script falla, la instalación se detiene e indica cuál fue.

### ¿Ya estaba instalado antes?

Si el proyecto ya se había instalado en la computadora, `instalar.ps1` no vuelve a crear nada y muestra este mensaje:

```
El sistema YA ESTA INSTALADO: los 3 servidores estan funcionando.
```

En ese caso hay dos opciones:

| Situación | Qué hacer |
|---|---|
| Solo se quiere usar o revisar el sistema | Nada más: los servidores ya quedaron encendidos y listos |
| Se quieren los datos **como recién instalados** (por ejemplo, porque ya se ejecutaron las pruebas y se quieren repetir, o si no se sabe en qué estado quedaron) | Reinstalar desde cero: `powershell -ExecutionPolicy Bypass -File .\instalar.ps1 -Reiniciar` |

`-Reiniciar` borra los contenedores y sus datos y vuelve a ejecutar toda la instalación. **No vuelve a descargar las imágenes** (ya están en la computadora), así que es mucho más rápido que la primera instalación. Al final debe salir otra vez `12 | 10 | 15`.

**¿Cómo saber si los datos están como recién instalados?** Ejecutar:
```powershell
docker exec pg_clinica psql -U postgres -d clinica_db -tAc "SELECT estado FROM ordenes_medicas WHERE id_orden = 13"
```
- `PENDIENTE` → los datos están limpios y se pueden ejecutar todas las pruebas.
- `COMPLETADA` → las pruebas ya se ejecutaron; usar `-Reiniciar` para repetirlas.

---

## 6. Comprobar que todo funciona

Hay tres formas. La más rápida es la primera.

> **Importante:** algunas pruebas **registran datos nuevos** (el resultado del estudio 13 y el paciente 13), por lo que **solo se pueden ejecutar una vez**. Para repetirlas, primero se reinstala desde cero (ver [sección 7](#7-encender-apagar-y-reinstalar)).

### 6.1 Forma rápida: reporte en el navegador

```powershell
powershell -ExecutionPolicy Bypass -File .\reporte.ps1
```

Ejecuta 9 pruebas en los tres servidores y abre una página web con los resultados, cada uno con su explicación y lo que se esperaba obtener:

| Paso | Qué demuestra | Resultado esperado |
|---|---|---|
| 1 | Los 3 servidores están encendidos | `pg_clinica`, `mssql_integra` y `mongo_reportes` con estado *Up* |
| 2 | Segmentación horizontal | 4 pacientes en cada sucursal; la búsqueda por sucursal solo lee un fragmento |
| 3 | PostgreSQL lee de SQL Server | 12 pacientes con su estado de facturación y aseguradora |
| 4 | PostgreSQL envía datos a MongoDB | 12 estudios y 10 indicadores |
| 5 | Una operación toca los 3 motores | 3 mensajes de confirmación; el paciente 1 pasa de 1 a 2 estudios y aparece una factura PENDIENTE |
| 6 | PostgreSQL escribe en SQL Server | El paciente 13 queda en Alajuela y en SQL Server con el código `AVP-000013` |
| 7 | Vista para la aplicación web | `usr_api_web` ve 13 pacientes con datos de facturación |
| 8 | Reporte en MongoDB | Una fila por médico y tipo de estudio, con cantidad e ingresos |
| 9 | Seguridad | **Mensajes en rojo**: son los accesos indebidos que el sistema bloqueó, lo cual es correcto |

### 6.2 Con herramientas gráficas (los tres servidores)

**Datos de conexión:**

| Motor | Programa | Servidor | Usuario / contraseña |
|---|---|---|---|
| PostgreSQL | pgAdmin | Host `localhost`, puerto **`5433`**, base `clinica_db` | `postgres` / `Admin_Pg2026` |
| SQL Server | SSMS | `localhost,1434` (marcar *Trust server certificate*) | `sa` / `Admin_Sql2026!` |
| MongoDB | Compass | `mongodb://admin:Admin_Mongo2026@localhost:27018/` | `admin` / `Admin_Mongo2026` |

> Las contraseñas están escritas en los scripts para que el proyecto se pueda revisar fácilmente. En un sistema real irían en variables de entorno o en un gestor de secretos.

#### PostgreSQL en pgAdmin

1. Clic derecho en **Servers → Register → Server…** y llenar los datos de la tabla anterior.
2. En `clinica_db` abrir el **Query Tool** y cargar el archivo [postgres/scripts/09_pruebas_pgadmin.sql](postgres/scripts/09_pruebas_pgadmin.sql).
3. **Seleccionar un bloque con el mouse y presionar F5.** El resultado aparece abajo.

Desde PostgreSQL se ven los tres motores: las tablas normales son de PostgreSQL, el esquema `mssql` muestra datos de SQL Server y el esquema `mongo` muestra datos de MongoDB.

| Bloque | Qué hace | Resultado esperado |
|---|---|---|
| 1 | Cuenta los pacientes de cada fragmento | 4 por sucursal |
| 2 | Plan de una búsqueda por sucursal | Solo lee `pacientes_cartago` |
| 3 | Lee el fragmento vertical que está en SQL Server | 12 pacientes con 4 columnas |
| 4 | **Operación 1:** paciente + facturación | 12 pacientes con estado y aseguradora de SQL Server |
| 5 | Lee el resumen de pacientes que está en MongoDB | 12 resúmenes |
| 6 | **Operación 2** *(registra datos)*: resultado del estudio 13 | En la pestaña *Messages*: confirmación de PostgreSQL, MongoDB y SQL Server |
| 7 | Comprueba el bloque 6 | 2 estudios en MongoDB y 2 facturas en SQL Server para el paciente 1 |
| 8 | **Operación 3:** vista de la aplicación web | Pacientes con sus saldos de facturación |
| 9 | *(Registra datos)*: paciente nuevo en Alajuela | Confirmación de PostgreSQL y SQL Server |
| 10 | Comprueba el bloque 9 | Paciente en `pacientes_alajuela` con código `AVP-000013` |
| 11 | **Operación 4:** indicadores en MongoDB | 10 indicadores por mes, sucursal y tipo |

Para probar como **aplicación móvil**, registrar otro servidor en pgAdmin con el usuario `usr_api_mobile` / `Api_Mobile2026`:
```sql
SELECT * FROM api_movil.v_mis_citas WHERE id_paciente = 1;  -- funciona
SELECT * FROM pacientes;                                     -- permission denied (correcto)
```

#### SQL Server en SSMS

Abrir [sqlserver/06_demo_tres_motores.sql](sqlserver/06_demo_tres_motores.sql) y ejecutar cada bloque (seleccionar + F5). Está pensado para usarse junto con pgAdmin, comparando **antes y después**:

| Bloque | Qué muestra | Antes del bloque 6/9 de pgAdmin | Después |
|---|---|---|---|
| A | Fragmento vertical del paciente (4 columnas) | 12 pacientes | 13 pacientes |
| B | Facturas del paciente 1 | 1 factura | Aparece la factura del estudio 13, creada desde PostgreSQL |
| C | Resumen de facturación del paciente 1 | 0 pendiente | 5000 pendiente |
| D | Paciente 13 | Sin filas | Aparece con el código `AVP-000013` |
| E | La aseguradora paga la factura 13 (*requiere el bloque 6 de pgAdmin*) | — | El bloque 8 de pgAdmin muestra al paciente 1 **AL_DIA** sin volver a hacer nada en PostgreSQL |
| F | Seguridad del usuario del FDW | — | Puede leer, pero al intentar borrar recibe el **error 229** |

#### MongoDB en Compass

1. Conectarse con `mongodb://admin:Admin_Mongo2026@localhost:27018/`.
2. Abrir la base **`reportes_medicos`**. Sus colecciones son `resultados_estudios`, `resumen_paciente`, `indicadores_mensuales` y `reporte_medico_tipo`.
3. En `resumen_paciente`, filtrar con `{ id_paciente: 1 }`. Después del bloque 6 de pgAdmin, `total_estudios` pasa de 1 a 2.
4. **Operación 5:** en `resultados_estudios` → pestaña *Aggregations* → botón *Text*, pegar:
   ```js
   [
     { $group: { _id: { medico: "$medico", tipo: "$tipo" },
                 cantidad: { $sum: 1 }, ingreso_total: { $sum: "$costo" } } },
     { $sort: { cantidad: -1 } }
   ]
   ```

### 6.3 Pruebas completas desde la terminal

Scripts con todas las pruebas, en este orden y después de una instalación limpia:

```powershell
# 1. PostgreSQL: todas las operaciones distribuidas
docker exec -it pg_clinica psql -U postgres -d clinica_db -P pager=off -f /scripts/08_consultas_prueba.sql

# 2. SQL Server: segmentación vertical, datos que llegaron desde PostgreSQL y permisos
docker exec -it mssql_integra /opt/mssql-tools18/bin/sqlcmd -C -S localhost -U sa -P "Admin_Sql2026!" -i /scripts/05_consultas_prueba.sql

# 3. MongoDB: consultas analíticas
docker exec -it mongo_reportes mongosh -u admin -p Admin_Mongo2026 /scripts/03_consultas_analiticas.js

# 4. MongoDB: permisos del usuario móvil
docker exec -it mongo_reportes mongosh -u usr_api_mobile -p Api_Mobile2026 --authenticationDatabase reportes_medicos /scripts/04_prueba_permisos.js
```

> Los mensajes `NOTICE: tds_fdw: Query executed correctly` son informativos y no son errores.

---

## 7. Encender, apagar y reinstalar

| Acción | Comando | ¿Se conservan los datos? |
|---|---|---|
| Apagar los servidores | `docker compose stop` | Sí |
| Volver a encenderlos | `docker compose start` | Sí |
| Ver si están encendidos | `docker ps` | — |
| **Reinstalar desde cero** | `powershell -ExecutionPolicy Bypass -File .\instalar.ps1 -Reiniciar` | **No**: borra contenedores y datos, y vuelve a instalar todo |
| Eliminar todo el proyecto de Docker | `docker compose down -v` | No |

Reinstalar desde cero deja los datos como recién instalados, lo que permite volver a ejecutar las pruebas que registran datos. Si pgAdmin estaba conectado, hay que desconectarse y volver a conectar.

---

## 8. Estructura del repositorio

```
├── docker-compose.yml                 Los 3 servidores, la red y los volúmenes
├── instalar.ps1                       Instalación automática (ejecuta todo en orden)
├── reporte.ps1                        Pruebas en los 3 servidores, con resultado en una página web
├── README.md                          Esta guía
├── postgres/
│   ├── Dockerfile                     PostgreSQL 16 + tds_fdw + mongo_fdw
│   ├── config/
│   │   ├── postgresql.conf            Parámetros del servidor
│   │   └── pg_hba.conf                Reglas de autenticación
│   └── scripts/
│       ├── 01_modelo_segmentado.sql   Tablas y fragmentos horizontales
│       ├── 02_datos_prueba.sql        Datos de ejemplo
│       ├── 03_roles.sql               Roles internos y externos
│       ├── 04_fdw_sqlserver.sql       Canal tds_fdw (servidor, mapeos, tablas foráneas)
│       ├── 05_fdw_mongodb.sql         Canal mongo_fdw
│       ├── 06_operaciones_distribuidas.sql  Funciones y procedimientos distribuidos
│       ├── 07_vistas_api.sql          Vistas para web y móvil + permisos
│       ├── 08_consultas_prueba.sql    Pruebas completas (terminal)
│       └── 09_pruebas_pgadmin.sql     Pruebas por bloques para pgAdmin
├── sqlserver/
│   ├── 01_crear_bd.sql                Base y tablas (segmentación vertical)
│   ├── 02_datos_prueba.sql            Datos de ejemplo
│   ├── 03_procedimientos.sql          Procedimientos almacenados
│   ├── 04_seguridad.sql               Login y rol del FDW
│   ├── 05_consultas_prueba.sql        Pruebas completas (terminal)
│   └── 06_demo_tres_motores.sql       Pruebas por bloques para SSMS (antes y después)
├── mongodb/
│   ├── 01_crear_bd.js                 Colecciones, validación e índices
│   ├── 02_seguridad.js                Roles y usuarios
│   ├── 03_consultas_analiticas.js     Agregaciones (por médico y tipo de estudio)
│   ├── 04_prueba_permisos.js          Prueba de permisos de usr_api_mobile
│   └── 06_reporte_json.js             Consulta que usa reporte.ps1
└── docs/
    ├── Documentacion_Proyecto2.docx   Documentación formal del proyecto
    ├── diagramas/                     Diagramas (.svg editable y .png)
    ├── evidencia/                     Capturas de la ejecución real de cada operación
    └── render_diagramas.ps1           Convierte los .svg a .png
```

Los scripts de creación (`01` a `07` de PostgreSQL, `01` a `04` de SQL Server y `01` y `02` de MongoDB) los ejecuta `instalar.ps1`; **no hace falta ejecutarlos a mano**.

---

# Parte II — Diseño técnico

## 9. Modelo de datos y segmentación

![Modelo de datos y segmentación](docs/diagramas/02_modelo_segmentacion.png)

### 9.1 PostgreSQL — segmentación horizontal

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
- **Consulta:** si se filtra por `id_sucursal`, PostgreSQL lee **solo un fragmento** (*partition pruning*). Se comprueba con `EXPLAIN`.
- **Integridad referencial:** la llave primaria incluye la columna de partición, y las llaves foráneas son compuestas, por ejemplo `(id_paciente, id_sucursal)`.
- **Catálogos sin segmentar:** `sucursales`, `medicos`, `tipos_estudio` y `usuarios_admin` son pequeños y los usan todas las sucursales.
- **`convenios_cache`:** copia local de los convenios de SQL Server, que se llena por sincronización.

El resultado de cada estudio se guarda en una columna `JSONB`, porque cada tipo de estudio tiene campos distintos (un hemograma no se parece a un ultrasonido).

### 9.2 SQL Server — segmentación vertical

El paciente completo vive en PostgreSQL. SQL Server guarda **solo las columnas** que necesitan los sistemas externos:

| Tabla | Columnas que SÍ se guardan | Columnas que NO se guardan |
|---|---|---|
| `paciente_integracion` | `id_paciente`, `id_aseguradora`, `codigo_externo`, `estado_facturacion` | cédula, nombre, apellidos, fecha de nacimiento, teléfono, correo |
| `facturas_externas` | `id_estudio`, `id_paciente`, `codigo_estudio`, `costo`, `fecha`, `codigo_institucion`, `estado` | resultado clínico, diagnóstico, médico |

Otras tablas: `aseguradoras`, `convenios` y `resumen_facturacion` (esta última la llena un procedimiento almacenado).

Las **llaves comunes** `id_paciente`, `codigo_estudio` e `id_estudio` permiten unir los fragmentos desde PostgreSQL.

Procedimientos almacenados ([03_procedimientos.sql](sqlserver/03_procedimientos.sql)):

| Procedimiento | Qué hace | Quién lo usa |
|---|---|---|
| `sp_generar_resumen_facturacion` | Calcula, por paciente, el total facturado, pagado y pendiente, y lo guarda en `resumen_facturacion` | Interno y `sp_registrar_factura` |
| `sp_actualizar_estado_facturacion` | Regla de negocio: con facturas rechazadas el paciente queda MOROSO; con pendientes, PENDIENTE; si no, AL_DIA | Interno y `sp_registrar_factura` |
| `sp_registrar_paciente_integracion` | Crea o actualiza el fragmento vertical de un paciente | PostgreSQL (vía `tds_fdw`) |
| `sp_registrar_factura` | Crea la factura de un estudio y recalcula los resúmenes | PostgreSQL (vía `tds_fdw`) |

### 9.3 MongoDB — modelo no relacional

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

La colección `resultados_estudios` tiene un validador `$jsonSchema` con campos obligatorios e índices: `id_estudio` único, `medico + tipo` y `sucursal + fecha`.

---

## 10. Canales FDW

### 10.1 Configuración del servidor PostgreSQL

**[postgresql.conf](postgres/config/postgresql.conf)** (solo los parámetros que cambian):

| Parámetro | Valor | Para qué |
|---|---|---|
| `listen_addresses` | `'*'` | Aceptar conexiones de la red Docker |
| `password_encryption` | `scram-sha-256` | Guardar las contraseñas cifradas con SCRAM |
| `log_connections` / `log_disconnections` | `on` | Registrar en la bitácora quién se conecta |
| `log_statement` | `'ddl'` | Registrar `CREATE`, `ALTER` y `DROP` |
| `timezone` | `America/Costa_Rica` | Hora local |

**[pg_hba.conf](postgres/config/pg_hba.conf)** — controla quién puede conectarse, a qué base y con qué método. Se lee de arriba hacia abajo y se aplica la primera regla que coincide:

| Tipo | Base | Usuario | Método | Motivo |
|---|---|---|---|---|
| local | all | `postgres` | `trust` | Administración dentro del contenedor |
| host | all | `usr_fdw_pg_mssql`, `usr_fdw_pg_mongo` | `reject` | Roles internos: nadie entra con ellos desde afuera |
| host | `clinica_db` | `usr_api_web`, `usr_api_mobile` | `scram-sha-256` | Las aplicaciones solo entran a su base, con contraseña cifrada |
| host | all | `postgres` | `scram-sha-256` | Administración remota (pgAdmin) |
| host | all | all | `reject` | Cualquier otra conexión se rechaza |

Ambos archivos se montan en el contenedor y se activan desde [docker-compose.yml](docker-compose.yml), por lo que no hay que configurarlos a mano:

```yaml
command: >
  postgres -c config_file=/etc/postgresql/postgresql.conf
           -c hba_file=/etc/postgresql/pg_hba.conf
```

### 10.2 Instalación de las extensiones

En [postgres/Dockerfile](postgres/Dockerfile), sobre `postgres:16-trixie` (Debian 13):

| Extensión | Cómo se instala | Detalles |
|---|---|---|
| `tds_fdw` | Paquete `postgresql-16-tds-fdw` del repositorio oficial de PostgreSQL | Usa FreeTDS. Se configura `client charset = UTF-8` (para los acentos) y la fecha en formato ISO en `locales.conf` |
| `mongo_fdw` | Se compila la versión estable `REL-5_5_3` | Primero se compila el driver de MongoDB `libmongoc` **1.30.2**. La librería `json-c` se compila dentro de la extensión y permite enviar columnas `JSON` como subdocumentos |

La imagen resultante se publica automáticamente en GitHub Container Registry mediante GitHub Actions ([.github/workflows/publicar-imagen.yml](.github/workflows/publicar-imagen.yml)), para que la instalación no tenga que compilar nada.

### 10.3 Canal PostgreSQL ↔ SQL Server (`tds_fdw`)

Script: [04_fdw_sqlserver.sql](postgres/scripts/04_fdw_sqlserver.sql). La conexión se define en tres pasos:

```sql
CREATE EXTENSION tds_fdw;

-- 1) Dónde está el servidor remoto
CREATE SERVER srv_mssql_integracion FOREIGN DATA WRAPPER tds_fdw
    OPTIONS (servername 'sqlserver', port '1433',
             database 'IntegracionMedica', tds_version '7.4');

-- 2) Con qué usuario se entra
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
-- 1. tabla foránea temporal cuya "consulta" es el procedimiento
CREATE FOREIGN TABLE mssql.tmp_exec_123 (resultado VARCHAR(500))
    SERVER srv_mssql_integracion
    OPTIONS (query 'EXEC dbo.sp_registrar_factura @id_estudio = 13, ...',
             use_remote_estimate 'false');
-- 2. al leerla, SQL Server ejecuta el procedimiento y devuelve 'OK: ...'
SELECT resultado FROM mssql.tmp_exec_123;
-- 3. se borra
DROP FOREIGN TABLE mssql.tmp_exec_123;
```

Así, la escritura en SQL Server queda **limitada a dos procedimientos**: el usuario remoto no puede hacer `INSERT`, `UPDATE` ni `DELETE` directo.

### 10.4 Canal PostgreSQL → MongoDB (`mongo_fdw`)

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

## 11. Roles y seguridad

### 11.1 Perfiles internos (comunicación entre motores)

| Perfil | Dónde existe | Autenticación | Permisos |
|---|---|---|---|
| `usr_fdw_pg_mssql` | PostgreSQL (rol `NOLOGIN`) y SQL Server (login) | SQL Server: contraseña con `CHECK_POLICY = ON`. PostgreSQL: `reject` en `pg_hba.conf` | **SQL Server**, rol `rol_fdw_integracion`: `SELECT` en las 6 tablas y vistas de integración, `EXECUTE` en `sp_registrar_paciente_integracion` y `sp_registrar_factura`, y `DENY INSERT/UPDATE/DELETE` sobre el esquema `dbo`. **PostgreSQL:** dueño de las tablas foráneas `mssql.*` y `SELECT` en algunas tablas locales |
| `usr_fdw_pg_mongo` | PostgreSQL (rol `NOLOGIN`) y MongoDB (usuario) | MongoDB: SCRAM-SHA-256. PostgreSQL: `reject` | **MongoDB**, rol propio `rol_fdw_escritura`: `find`, `insert`, `update` y `remove` **solo** en las 3 colecciones (no puede borrar colecciones ni crear usuarios). **PostgreSQL:** dueño de las tablas foráneas `mongo.*` y `SELECT` en las tablas locales que exporta |

**¿Cómo se usan si no pueden iniciar sesión?**
- Las funciones que tocan otro motor son `SECURITY DEFINER` y su dueño es el rol interno. Quien las ejecute se conecta al motor remoto **como el rol interno**, con sus permisos mínimos.
- En SQL Server, los procedimientos pueden insertar aunque el rol tenga `DENY INSERT` gracias al **encadenamiento de propiedad**: el procedimiento y las tablas tienen el mismo dueño (`dbo`), así que SQL Server no revisa los permisos sobre las tablas.
- `tds_fdw` usa el `USER MAPPING` del usuario que hace la consulta. Por eso `usr_api_web`, `usr_api_mobile` y el administrador `postgres` también tienen uno, pero todos apuntan al **mismo login remoto** `usr_fdw_pg_mssql`: nunca tienen en SQL Server más permisos que el perfil interno.

### 11.2 Perfiles externos (aplicaciones)

| Política | `usr_api_web` | `usr_api_mobile` |
|---|---|---|
| Qué puede ver en PostgreSQL | Esquema `api_web`: 4 vistas completas | Esquema `api_movil`: 3 vistas simplificadas (sin cédula, correo ni JSON) |
| Tablas base | Sin acceso | Sin acceso |
| Solo lectura | `default_transaction_read_only = on` | `default_transaction_read_only = on` |
| Tiempo máximo por consulta | 30 s | 5 s |
| Conexiones simultáneas | 50 | 20 |
| Vencimiento de la contraseña | 2027-12-31 | 2027-12-31 |
| Autenticación | `scram-sha-256`, solo a `clinica_db` | `scram-sha-256`, solo a `clinica_db` |
| MongoDB | Rol `read` en `reportes_medicos` | Rol `rol_movil_lectura`: `find` solo en `resumen_paciente` e `indicadores_mensuales` |

Vistas disponibles ([07_vistas_api.sql](postgres/scripts/07_vistas_api.sql)):

| Vista | Datos | Origen |
|---|---|---|
| `api_web.v_pacientes_facturacion` | Paciente, sucursal, aseguradora, estado y saldos de facturación | PostgreSQL + SQL Server |
| `api_web.v_estudios` | Estudios con resultado completo y diagnóstico | PostgreSQL |
| `api_web.v_citas` | Citas con médico y sucursal | PostgreSQL |
| `api_web.v_cobertura_ordenes` | Costo de cada orden, cobertura del convenio y monto a pagar por el paciente | PostgreSQL + SQL Server |
| `api_movil.v_mis_citas` | Fecha, médico, sucursal y estado | PostgreSQL |
| `api_movil.v_mis_resultados` | Estudio, fecha y diagnóstico | PostgreSQL |
| `api_movil.v_estado_cuenta` | Estado de facturación y saldo pendiente | SQL Server |

---

## 12. Flujos de datos

![Flujo de la transacción distribuida](docs/diagramas/03_flujo_transaccion.png)

Todas las operaciones que escriben en más de un motor siguen el mismo patrón:

1. Se guarda el dato en **PostgreSQL**, que es la fuente principal.
2. Se ejecuta **`COMMIT`**: el dato queda confirmado.
3. Después se **propaga** a MongoDB y/o SQL Server.
4. Si un motor remoto falla, el dato de PostgreSQL no se pierde: se muestra un `WARNING` con la función para reintentar. Las funciones de propagación son **idempotentes**: reintentarlas no duplica datos.

Se eligió este patrón en lugar de una confirmación en dos fases (2PC) porque `tds_fdw` y `mongo_fdw` no participan en transacciones distribuidas, y porque permite que la operación clínica no se detenga si un sistema secundario no está disponible.

### Flujo A — Carga inicial (al instalar)

```sql
SELECT mongo.fn_exportar_resultados();             -- 12 estudios + 12 resúmenes  -> MongoDB
SELECT mongo.fn_exportar_indicadores_mensuales();  -- 10 indicadores              -> MongoDB
SELECT mssql.fn_sincronizar_convenios();           -- 15 convenios de SQL Server  -> convenios_cache
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

`api_web.v_pacientes_facturacion` une `pacientes` (local) con `mssql.paciente_integracion` y `mssql.resumen_facturacion` (remotas). Cada vez que se consulta la vista, los datos de SQL Server se leen en ese momento, así que un cambio hecho en SQL Server se ve de inmediato en PostgreSQL.

### Flujo E — Reportes (MongoDB)

Los reportes se calculan en MongoDB con *aggregation pipelines* sobre los documentos desnormalizados, sin cargar la base transaccional ([03_consultas_analiticas.js](mongodb/03_consultas_analiticas.js)).

---

## 13. Operaciones requeridas

| # | Operación pedida | Solución | Dónde |
|---|---|---|---|
| 1 | Consulta en PostgreSQL con la información del paciente y su estado de facturación desde SQL Server | `JOIN` entre `pacientes` y `mssql.paciente_integracion` / `mssql.aseguradoras`, más `mssql.resumen_facturacion` | [08_consultas_prueba.sql](postgres/scripts/08_consultas_prueba.sql), bloque 4 de [09_pruebas_pgadmin.sql](postgres/scripts/09_pruebas_pgadmin.sql) |
| 2 | Inserción en PostgreSQL que, tras confirmarse, actualiza un documento resumen en MongoDB | `sp_registrar_resultado`: `INSERT` → `COMMIT` → `fn_publicar_estudio` actualiza `resumen_paciente`. Además crea la factura en SQL Server | [06_operaciones_distribuidas.sql](postgres/scripts/06_operaciones_distribuidas.sql) |
| 3 | Vista en PostgreSQL que combina datos locales y remotos (SQL Server) para la web | `api_web.v_pacientes_facturacion` y `api_web.v_cobertura_ordenes` | [07_vistas_api.sql](postgres/scripts/07_vistas_api.sql) |
| 4 | Exportación de datos hacia MongoDB para reportes agregados | `mongo.fn_exportar_resultados()` y `mongo.fn_exportar_indicadores_mensuales()` | [06_operaciones_distribuidas.sql](postgres/scripts/06_operaciones_distribuidas.sql) |
| 5 | Consulta analítica en MongoDB con agregaciones por médico y tipo de estudio | `$group` por `{medico, tipo}` con cantidad, ingreso y promedio; ranking de médicos; rendimiento por sucursal | [03_consultas_analiticas.js](mongodb/03_consultas_analiticas.js) |
| Extra | Escritura PostgreSQL → SQL Server | `sp_registrar_paciente` y la factura de `sp_registrar_resultado`, mediante procedimientos remotos | [06_operaciones_distribuidas.sql](postgres/scripts/06_operaciones_distribuidas.sql) |

---

## 14. Solución de problemas

| Síntoma | Causa | Solución |
|---|---|---|
| `Docker Desktop is unable to start` o el instalador no avanza | Docker apagado o disco lleno | Encender Docker Desktop y liberar espacio en disco (unos 10 GB) |
| `failed to solve ... read-only file system` | Disco lleno durante la descarga o construcción | Liberar espacio y volver a ejecutar `instalar.ps1` |
| `no se puede cargar el archivo ... la ejecución de scripts está deshabilitada` | Política de ejecución de PowerShell | Ejecutar con `powershell -ExecutionPolicy Bypass -File .\instalar.ps1` |
| Un puerto ya está en uso | Otra instalación local de PostgreSQL, SQL Server o MongoDB | Cambiar el puerto del lado izquierdo en `docker-compose.yml` (ej. `"5434:5432"`) |
| pgAdmin no conecta | Se usó el puerto 5432 en lugar del 5433, o se reinstaló el sistema | Usar el puerto **5433**; si se reinstaló, desconectarse y volver a conectar |
| `La orden 13 no existe o no esta pendiente` | Las pruebas que registran datos ya se ejecutaron | Reinstalar con `.\instalar.ps1 -Reiniciar` |
| `WARNING: MongoDB no se actualizo` / `SQL Server no se actualizo` | El motor remoto no respondió | Revisar `docker ps` y reintentar con la función que indica el mensaje |
| `user mapping not found for "..."` | Se consultó una tabla foránea con un usuario sin mapeo | Consultar a través de las vistas o con `SET ROLE usr_fdw_pg_mssql` / `usr_fdw_pg_mongo` |
| La terminal se queda "pegada" mostrando resultados | `psql` abrió el paginador | Presionar `q`, o agregar `-P pager=off` al comando |

---

## 15. Referencias

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
