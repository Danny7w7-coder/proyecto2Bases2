/* =====================================================================
   POSTGRESQL - Script 05: canal FDW PostgreSQL -> MongoDB (mongo_fdw)

   mongo_fdw SI permite INSERT / UPDATE / DELETE, por eso se usa para
   EXPORTAR datos desde PostgreSQL hacia la capa de reportes.
   Regla de mongo_fdw: la primera columna debe llamarse _id (tipo NAME);
   al insertar se deja vacia y MongoDB genera el ObjectId.
   ===================================================================== */

CREATE EXTENSION IF NOT EXISTS mongo_fdw;

-- "mongodb" es el nombre del contenedor en la red Docker
CREATE SERVER srv_mongo_reportes
    FOREIGN DATA WRAPPER mongo_fdw
    OPTIONS (address 'mongodb',
             port '27017',
             authentication_database 'reportes_medicos');

GRANT USAGE ON FOREIGN SERVER srv_mongo_reportes TO usr_fdw_pg_mongo;

CREATE USER MAPPING FOR usr_fdw_pg_mongo
    SERVER srv_mongo_reportes
    OPTIONS (username 'usr_fdw_pg_mongo', password 'Fdw_Mongo2026');

CREATE SCHEMA mongo AUTHORIZATION usr_fdw_pg_mongo;

-- Coleccion: resultados_estudios (documento desnormalizado por estudio)
CREATE FOREIGN TABLE mongo.resultados_estudios (
    _id            NAME,
    id_estudio     INT,
    id_paciente    INT,
    paciente       TEXT,
    medico         TEXT,
    especialidad   TEXT,
    codigo_estudio TEXT,
    tipo           TEXT,
    estudio        TEXT,
    resultado      JSON,          -- se guarda como subdocumento en MongoDB
    diagnostico    TEXT,
    fecha          TIMESTAMP,
    sucursal       TEXT,
    costo          FLOAT8
) SERVER srv_mongo_reportes
  OPTIONS (database 'reportes_medicos', collection 'resultados_estudios');

-- Coleccion: resumen_paciente (se actualiza tras cada resultado nuevo)
CREATE FOREIGN TABLE mongo.resumen_paciente (
    _id                NAME,
    id_paciente        INT,
    paciente           TEXT,
    sucursal           TEXT,
    total_estudios     INT,
    gasto_total        FLOAT8,
    ultimo_estudio     TEXT,
    ultimo_diagnostico TEXT,
    ultima_fecha       TIMESTAMP,
    actualizado        TIMESTAMP
) SERVER srv_mongo_reportes
  OPTIONS (database 'reportes_medicos', collection 'resumen_paciente');

-- Coleccion: indicadores_mensuales (reporte agregado)
CREATE FOREIGN TABLE mongo.indicadores_mensuales (
    _id                  NAME,
    mes                  TEXT,
    sucursal             TEXT,
    tipo                 TEXT,
    cantidad_estudios    INT,
    pacientes_atendidos  INT,
    ingreso_total        FLOAT8,
    generado             TIMESTAMP
) SERVER srv_mongo_reportes
  OPTIONS (database 'reportes_medicos', collection 'indicadores_mensuales');

ALTER FOREIGN TABLE mongo.resultados_estudios   OWNER TO usr_fdw_pg_mongo;
ALTER FOREIGN TABLE mongo.resumen_paciente      OWNER TO usr_fdw_pg_mongo;
ALTER FOREIGN TABLE mongo.indicadores_mensuales OWNER TO usr_fdw_pg_mongo;
