/* =====================================================================
   POSTGRESQL - Script 04: canal FDW PostgreSQL -> SQL Server (tds_fdw)

   Pasos de un FDW:
     1. CREATE EXTENSION      -> instala el "conector".
     2. CREATE SERVER         -> donde esta el servidor remoto.
     3. CREATE USER MAPPING   -> con que usuario/contrasena se entra.
     4. CREATE FOREIGN TABLE  -> tablas locales que "apuntan" a las remotas.

   Nota: las tablas foraneas de tds_fdw son de SOLO LECTURA (no soporta
   INSERT/UPDATE). Para ESCRIBIR en SQL Server, PostgreSQL ejecuta
   procedimientos almacenados remotos (ver script 06).
   ===================================================================== */

CREATE EXTENSION IF NOT EXISTS tds_fdw;

-- 2) Servidor remoto. "sqlserver" es el nombre del contenedor en la red Docker.
CREATE SERVER srv_mssql_integracion
    FOREIGN DATA WRAPPER tds_fdw
    OPTIONS (servername 'sqlserver',
             port '1433',
             database 'IntegracionMedica',
             tds_version '7.4');

-- Solo el rol interno puede usar este servidor
GRANT USAGE ON FOREIGN SERVER srv_mssql_integracion TO usr_fdw_pg_mssql;

-- 3) Mapeo de usuario: rol local usr_fdw_pg_mssql -> login de SQL Server
CREATE USER MAPPING FOR usr_fdw_pg_mssql
    SERVER srv_mssql_integracion
    OPTIONS (username 'usr_fdw_pg_mssql', password 'Fdw_Mssql2026!');

-- tds_fdw busca el mapeo del usuario que ejecuta la consulta (no del
-- dueno de la vista). Por eso las aplicaciones tambien tienen mapeo,
-- pero apuntan al MISMO login remoto de solo lectura: en SQL Server
-- nunca tienen mas permisos que usr_fdw_pg_mssql. Ademas no tienen
-- permiso sobre las tablas foraneas, solo sobre sus vistas.
CREATE USER MAPPING FOR usr_api_web
    SERVER srv_mssql_integracion
    OPTIONS (username 'usr_fdw_pg_mssql', password 'Fdw_Mssql2026!');

CREATE USER MAPPING FOR usr_api_mobile
    SERVER srv_mssql_integracion
    OPTIONS (username 'usr_fdw_pg_mssql', password 'Fdw_Mssql2026!');

-- 4) Tablas foraneas en un esquema aparte para distinguirlas facilmente
CREATE SCHEMA mssql AUTHORIZATION usr_fdw_pg_mssql;

CREATE FOREIGN TABLE mssql.aseguradoras (
    id_aseguradora     INT,
    nombre             VARCHAR(100),
    codigo_institucion VARCHAR(10),
    tipo               VARCHAR(20)
) SERVER srv_mssql_integracion
  OPTIONS (schema_name 'dbo', table_name 'aseguradoras');

CREATE FOREIGN TABLE mssql.paciente_integracion (
    id_paciente        INT,
    id_aseguradora     INT,
    codigo_externo     VARCHAR(20),
    estado_facturacion VARCHAR(15)
) SERVER srv_mssql_integracion
  OPTIONS (schema_name 'dbo', table_name 'paciente_integracion');

CREATE FOREIGN TABLE mssql.convenios (
    id_convenio          INT,
    id_aseguradora       INT,
    codigo_estudio       VARCHAR(10),
    porcentaje_cobertura NUMERIC(5,2),
    estado               VARCHAR(10)
) SERVER srv_mssql_integracion
  OPTIONS (schema_name 'dbo', table_name 'convenios');

CREATE FOREIGN TABLE mssql.facturas_externas (
    id_factura         INT,
    id_estudio         INT,
    id_paciente        INT,
    codigo_estudio     VARCHAR(10),
    costo              NUMERIC(12,2),
    fecha              DATE,
    codigo_institucion VARCHAR(10),
    estado             VARCHAR(12)
) SERVER srv_mssql_integracion
  OPTIONS (schema_name 'dbo', table_name 'facturas_externas');

-- Tabla que llena el procedimiento almacenado dbo.sp_generar_resumen_facturacion
CREATE FOREIGN TABLE mssql.resumen_facturacion (
    id_paciente       INT,
    aseguradora       VARCHAR(100),
    cantidad_facturas INT,
    total_facturado   NUMERIC(14,2),
    total_pagado      NUMERIC(14,2),
    total_pendiente   NUMERIC(14,2),
    ultima_factura    DATE,
    fecha_generacion  TIMESTAMP
) SERVER srv_mssql_integracion
  OPTIONS (schema_name 'dbo', table_name 'resumen_facturacion');

-- Vista remota de SQL Server
CREATE FOREIGN TABLE mssql.v_facturacion_aseguradora (
    codigo_institucion VARCHAR(10),
    aseguradora        VARCHAR(100),
    cantidad_facturas  INT,
    total_facturado    NUMERIC(14,2)
) SERVER srv_mssql_integracion
  OPTIONS (schema_name 'dbo', table_name 'v_facturacion_aseguradora');

-- Las tablas foraneas pertenecen al rol interno
ALTER FOREIGN TABLE mssql.aseguradoras              OWNER TO usr_fdw_pg_mssql;
ALTER FOREIGN TABLE mssql.paciente_integracion      OWNER TO usr_fdw_pg_mssql;
ALTER FOREIGN TABLE mssql.convenios                 OWNER TO usr_fdw_pg_mssql;
ALTER FOREIGN TABLE mssql.facturas_externas         OWNER TO usr_fdw_pg_mssql;
ALTER FOREIGN TABLE mssql.resumen_facturacion       OWNER TO usr_fdw_pg_mssql;
ALTER FOREIGN TABLE mssql.v_facturacion_aseguradora OWNER TO usr_fdw_pg_mssql;
