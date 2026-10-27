/* =====================================================================
   POSTGRESQL - Script 03: creacion de roles (perfiles)

   PERFILES INTERNOS DEL CLUSTER (comunicacion entre bases)
     usr_fdw_pg_mssql : identidad con la que PostgreSQL habla con SQL Server.
     usr_fdw_pg_mongo : identidad con la que PostgreSQL habla con MongoDB.
     -> NOLOGIN: nadie puede iniciar sesion con ellos desde afuera
        (ademas pg_hba.conf los rechaza). Solo los usan las vistas y
        funciones que son "propiedad" de estos roles.

   PERFILES EXTERNOS (aplicaciones)
     usr_api_web    : aplicacion web  -> vistas completas (schema api_web)
     usr_api_mobile : aplicacion movil -> vistas simplificadas (schema api_movil)
     -> LOGIN con contrasena SCRAM-SHA-256 (ver pg_hba.conf).
   ===================================================================== */

-- Quitar permisos por defecto: nadie crea objetos en public sin permiso
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
REVOKE ALL ON DATABASE clinica_db FROM PUBLIC;

-- ---------- Perfiles internos ----------
CREATE ROLE usr_fdw_pg_mssql NOLOGIN;
CREATE ROLE usr_fdw_pg_mongo NOLOGIN;

-- ---------- Perfiles externos ----------
CREATE ROLE usr_api_web LOGIN
    PASSWORD 'Api_Web2026'
    CONNECTION LIMIT 50                     -- la web tiene mas usuarios concurrentes
    VALID UNTIL '2027-12-31';

CREATE ROLE usr_api_mobile LOGIN
    PASSWORD 'Api_Mobile2026'
    CONNECTION LIMIT 20
    VALID UNTIL '2027-12-31';

-- Politicas diferenciadas a nivel de sesion
ALTER ROLE usr_api_web    SET default_transaction_read_only = on;  -- solo lectura
ALTER ROLE usr_api_web    SET statement_timeout = '30s';
ALTER ROLE usr_api_mobile SET default_transaction_read_only = on;
ALTER ROLE usr_api_mobile SET statement_timeout = '5s';            -- consultas cortas en movil

-- Permiso para conectarse a la base
GRANT CONNECT ON DATABASE clinica_db TO usr_api_web, usr_api_mobile;
GRANT USAGE ON SCHEMA public TO usr_fdw_pg_mssql, usr_fdw_pg_mongo;

-- Los roles internos necesitan leer algunas tablas locales para armar
-- las vistas combinadas (mssql) y los documentos que se exportan (mongo).
GRANT SELECT ON pacientes, sucursales, ordenes_medicas, tipos_estudio,
                resultados_estudios
             TO usr_fdw_pg_mssql;
GRANT SELECT, INSERT, DELETE ON convenios_cache TO usr_fdw_pg_mssql;

GRANT SELECT ON pacientes, sucursales, medicos, tipos_estudio,
                ordenes_medicas, resultados_estudios
             TO usr_fdw_pg_mongo;
