/* =====================================================================
   POSTGRESQL - Script 06: operaciones distribuidas

   Las funciones que tocan otro servidor se crean con SECURITY DEFINER
   y su dueno es el rol interno correspondiente. Asi, cuando las ejecuta
   el administrador o una aplicacion, la conexion remota SIEMPRE se hace
   con el usuario interno (usr_fdw_pg_mssql / usr_fdw_pg_mongo) y sus
   permisos minimos.
   ===================================================================== */

-- =====================================================================
-- A) PostgreSQL <-> SQL Server
-- =====================================================================

-- Sincroniza los convenios activos de SQL Server a la copia local
CREATE OR REPLACE FUNCTION mssql.fn_sincronizar_convenios()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, mssql
AS $$
DECLARE
    v_filas INTEGER;
BEGIN
    DELETE FROM convenios_cache;

    INSERT INTO convenios_cache (id_aseguradora, codigo_estudio, porcentaje_cobertura)
    SELECT id_aseguradora, codigo_estudio, porcentaje_cobertura
    FROM mssql.convenios
    WHERE estado = 'ACTIVO';

    GET DIAGNOSTICS v_filas = ROW_COUNT;
    RETURN v_filas;
END;
$$;
ALTER FUNCTION mssql.fn_sincronizar_convenios() OWNER TO usr_fdw_pg_mssql;


-- ---------------------------------------------------------------------
-- Escritura PostgreSQL -> SQL Server
-- tds_fdw no permite INSERT, pero una tabla foranea puede definirse con
-- la opcion "query", y esa consulta se ejecuta en SQL Server al hacer
-- SELECT. Se usa para ejecutar un PROCEDIMIENTO ALMACENADO remoto:
--   1. se crea una tabla foranea temporal con query = 'EXEC dbo.sp_...'
--   2. se hace SELECT (SQL Server ejecuta el procedimiento)
--   3. se borra la tabla foranea temporal
-- Esta funcion es privada: solo la usan las dos funciones de abajo.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION mssql.fn_ejecutar_procedimiento(p_llamada TEXT)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, mssql
AS $$
DECLARE
    v_tabla     TEXT := 'tmp_exec_' || pg_backend_pid() || '_' || floor(random() * 1000000)::int;
    v_resultado TEXT;
BEGIN
    EXECUTE format(
        'CREATE FOREIGN TABLE mssql.%I (resultado VARCHAR(500))
         SERVER srv_mssql_integracion
         OPTIONS (query %L, use_remote_estimate %L)',
        v_tabla, p_llamada, 'false');

    EXECUTE format('SELECT resultado FROM mssql.%I', v_tabla) INTO v_resultado;

    EXECUTE format('DROP FOREIGN TABLE mssql.%I', v_tabla);

    IF v_resultado IS NULL OR v_resultado LIKE 'ERROR%' THEN
        RAISE EXCEPTION 'SQL Server respondio: %', coalesce(v_resultado, 'sin respuesta');
    END IF;
    RETURN v_resultado;
END;
$$;
ALTER FUNCTION mssql.fn_ejecutar_procedimiento(TEXT) OWNER TO usr_fdw_pg_mssql;
REVOKE EXECUTE ON FUNCTION mssql.fn_ejecutar_procedimiento(TEXT) FROM PUBLIC;


-- Envia el fragmento vertical de un paciente a SQL Server
CREATE OR REPLACE FUNCTION mssql.fn_registrar_paciente_integracion(
    p_id_paciente INT, p_id_aseguradora INT)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, mssql
AS $$
BEGIN
    RETURN mssql.fn_ejecutar_procedimiento(format(
        'EXEC dbo.sp_registrar_paciente_integracion @id_paciente = %s, @id_aseguradora = %s',
        p_id_paciente, p_id_aseguradora));
END;
$$;
ALTER FUNCTION mssql.fn_registrar_paciente_integracion(INT, INT) OWNER TO usr_fdw_pg_mssql;


-- Envia la factura de un estudio realizado a SQL Server
CREATE OR REPLACE FUNCTION mssql.fn_registrar_factura(p_id_estudio INT)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, mssql
AS $$
DECLARE
    v RECORD;
BEGIN
    SELECT r.id_estudio, o.id_paciente, o.codigo_estudio, t.costo_base,
           r.fecha_resultado::date AS fecha
    INTO v
    FROM resultados_estudios r
    JOIN ordenes_medicas o ON o.id_orden = r.id_orden AND o.id_sucursal = r.id_sucursal
    JOIN tipos_estudio t   ON t.codigo_estudio = o.codigo_estudio
    WHERE r.id_estudio = p_id_estudio;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'El estudio % no existe', p_id_estudio;
    END IF;

    -- %L agrega comillas simples y las escapa (evita inyeccion SQL)
    RETURN mssql.fn_ejecutar_procedimiento(format(
        'EXEC dbo.sp_registrar_factura @id_estudio = %s, @id_paciente = %s, @codigo_estudio = %L, @costo = %s, @fecha = %L',
        v.id_estudio, v.id_paciente, v.codigo_estudio, v.costo_base, v.fecha));
END;
$$;
ALTER FUNCTION mssql.fn_registrar_factura(INT) OWNER TO usr_fdw_pg_mssql;


-- =====================================================================
-- B) PostgreSQL -> MongoDB
-- =====================================================================

-- Vista local que arma el documento DESNORMALIZADO de cada estudio
-- (une 5 tablas para que MongoDB reciba todo ya "armado").
CREATE OR REPLACE VIEW mongo.v_documento_estudio AS
SELECT r.id_estudio,
       p.id_paciente,
       p.nombre || ' ' || p.apellidos  AS paciente,
       m.nombre                        AS medico,
       m.especialidad,
       t.codigo_estudio,
       t.categoria                     AS tipo,
       t.nombre                        AS estudio,
       r.resultado::json               AS resultado,
       r.diagnostico,
       r.fecha_resultado               AS fecha,
       s.provincia                     AS sucursal,
       t.costo_base::float8            AS costo
FROM resultados_estudios r
JOIN ordenes_medicas o ON o.id_orden = r.id_orden AND o.id_sucursal = r.id_sucursal
JOIN pacientes p       ON p.id_paciente = o.id_paciente AND p.id_sucursal = o.id_sucursal
JOIN medicos m         ON m.id_medico = r.id_medico_informa
JOIN tipos_estudio t   ON t.codigo_estudio = o.codigo_estudio
JOIN sucursales s      ON s.id_sucursal = r.id_sucursal;
ALTER VIEW mongo.v_documento_estudio OWNER TO usr_fdw_pg_mongo;


-- B.1) Actualiza (o crea) el documento resumen_paciente de UN paciente
CREATE OR REPLACE FUNCTION mongo.fn_actualizar_resumen_paciente(p_id_paciente INT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, mongo
AS $$
DECLARE
    v RECORD;
BEGIN
    SELECT d.id_paciente,
           max(d.paciente)  AS paciente,
           max(d.sucursal)  AS sucursal,
           count(*)::int    AS total_estudios,
           sum(d.costo)     AS gasto_total,
           max(d.fecha)     AS ultima_fecha
    INTO v
    FROM mongo.v_documento_estudio d
    WHERE d.id_paciente = p_id_paciente
    GROUP BY d.id_paciente;

    IF v.id_paciente IS NULL THEN
        RETURN;                                   -- paciente sin estudios
    END IF;

    -- Primero intenta ACTUALIZAR el documento existente en MongoDB...
    UPDATE mongo.resumen_paciente
    SET total_estudios     = v.total_estudios,
        gasto_total        = v.gasto_total,
        ultimo_estudio     = (SELECT estudio     FROM mongo.v_documento_estudio
                              WHERE id_paciente = p_id_paciente ORDER BY fecha DESC LIMIT 1),
        ultimo_diagnostico = (SELECT diagnostico FROM mongo.v_documento_estudio
                              WHERE id_paciente = p_id_paciente ORDER BY fecha DESC LIMIT 1),
        ultima_fecha       = v.ultima_fecha,
        actualizado        = now()
    WHERE id_paciente = p_id_paciente;

    -- ...y si no existia, lo INSERTA.
    IF NOT FOUND THEN
        INSERT INTO mongo.resumen_paciente
              (id_paciente, paciente, sucursal, total_estudios, gasto_total,
               ultimo_estudio, ultimo_diagnostico, ultima_fecha, actualizado)
        SELECT v.id_paciente, v.paciente, v.sucursal, v.total_estudios, v.gasto_total,
               d.estudio, d.diagnostico, v.ultima_fecha, now()
        FROM mongo.v_documento_estudio d
        WHERE d.id_paciente = p_id_paciente
        ORDER BY d.fecha DESC
        LIMIT 1;
    END IF;
END;
$$;
ALTER FUNCTION mongo.fn_actualizar_resumen_paciente(INT) OWNER TO usr_fdw_pg_mongo;


-- B.2) Publica UN estudio en MongoDB y actualiza el resumen del paciente
CREATE OR REPLACE FUNCTION mongo.fn_publicar_estudio(p_id_estudio INT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, mongo
AS $$
DECLARE
    v_id_paciente INT;
BEGIN
    DELETE FROM mongo.resultados_estudios WHERE id_estudio = p_id_estudio;

    INSERT INTO mongo.resultados_estudios
          (id_estudio, id_paciente, paciente, medico, especialidad, codigo_estudio,
           tipo, estudio, resultado, diagnostico, fecha, sucursal, costo)
    SELECT id_estudio, id_paciente, paciente, medico, especialidad, codigo_estudio,
           tipo, estudio, resultado, diagnostico, fecha, sucursal, costo
    FROM mongo.v_documento_estudio
    WHERE id_estudio = p_id_estudio;

    SELECT id_paciente INTO v_id_paciente
    FROM mongo.v_documento_estudio
    WHERE id_estudio = p_id_estudio;

    PERFORM mongo.fn_actualizar_resumen_paciente(v_id_paciente);
END;
$$;
ALTER FUNCTION mongo.fn_publicar_estudio(INT) OWNER TO usr_fdw_pg_mongo;


-- B.3) Exportacion MASIVA de todos los estudios y resumenes (carga inicial)
CREATE OR REPLACE FUNCTION mongo.fn_exportar_resultados()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, mongo
AS $$
DECLARE
    v_total INTEGER;
    v_pac   INTEGER;
BEGIN
    DELETE FROM mongo.resultados_estudios;

    INSERT INTO mongo.resultados_estudios
          (id_estudio, id_paciente, paciente, medico, especialidad, codigo_estudio,
           tipo, estudio, resultado, diagnostico, fecha, sucursal, costo)
    SELECT id_estudio, id_paciente, paciente, medico, especialidad, codigo_estudio,
           tipo, estudio, resultado, diagnostico, fecha, sucursal, costo
    FROM mongo.v_documento_estudio;
    GET DIAGNOSTICS v_total = ROW_COUNT;

    DELETE FROM mongo.resumen_paciente;
    FOR v_pac IN SELECT DISTINCT id_paciente FROM mongo.v_documento_estudio LOOP
        PERFORM mongo.fn_actualizar_resumen_paciente(v_pac);
    END LOOP;

    RETURN v_total;
END;
$$;
ALTER FUNCTION mongo.fn_exportar_resultados() OWNER TO usr_fdw_pg_mongo;


-- B.4) Exportacion de REPORTES AGREGADOS (indicadores por mes/sucursal/tipo)
CREATE OR REPLACE FUNCTION mongo.fn_exportar_indicadores_mensuales()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, mongo
AS $$
DECLARE
    v_total INTEGER;
BEGIN
    DELETE FROM mongo.indicadores_mensuales;

    INSERT INTO mongo.indicadores_mensuales
          (mes, sucursal, tipo, cantidad_estudios, pacientes_atendidos, ingreso_total, generado)
    SELECT to_char(fecha, 'YYYY-MM'),
           sucursal,
           tipo,
           count(*),
           count(DISTINCT id_paciente),
           sum(costo),
           now()
    FROM mongo.v_documento_estudio
    GROUP BY 1, 2, 3;

    GET DIAGNOSTICS v_total = ROW_COUNT;
    RETURN v_total;
END;
$$;
ALTER FUNCTION mongo.fn_exportar_indicadores_mensuales() OWNER TO usr_fdw_pg_mongo;


-- =====================================================================
-- C) Transacciones distribuidas
--    Patron usado en los dos procedimientos:
--    1. Se guarda el dato en PostgreSQL (fuente de verdad).
--    2. COMMIT  -> el dato queda CONFIRMADO en PostgreSQL.
--    3. Recien despues se propaga a los otros motores.
--    Si un motor remoto no responde, el dato en PostgreSQL NO se pierde;
--    se muestra una advertencia con la funcion para reintentar.
-- =====================================================================

-- C.1) Registrar un paciente: PostgreSQL -> SQL Server
CREATE OR REPLACE PROCEDURE public.sp_registrar_paciente(
    p_id_sucursal      INT,
    p_cedula           TEXT,
    p_nombre           TEXT,
    p_apellidos        TEXT,
    p_fecha_nacimiento DATE,
    p_sexo             TEXT,
    p_telefono         TEXT,
    p_correo           TEXT,
    p_id_aseguradora   INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_id_paciente INT;
BEGIN
    -- La fila se guarda automaticamente en el fragmento de su sucursal
    INSERT INTO pacientes (id_sucursal, cedula, nombre, apellidos, fecha_nacimiento, sexo, telefono, correo)
    VALUES (p_id_sucursal, p_cedula, p_nombre, p_apellidos, p_fecha_nacimiento, p_sexo, p_telefono, p_correo)
    RETURNING id_paciente INTO v_id_paciente;

    COMMIT;   -- <<< confirmacion en PostgreSQL
    RAISE NOTICE 'PostgreSQL: paciente % confirmado', v_id_paciente;

    BEGIN
        RAISE NOTICE 'SQL Server: %', mssql.fn_registrar_paciente_integracion(v_id_paciente, p_id_aseguradora);
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'SQL Server no se actualizo (%). Reintentar con SELECT mssql.fn_registrar_paciente_integracion(%, %);',
                      SQLERRM, v_id_paciente, p_id_aseguradora;
    END;
END;
$$;


-- C.2) Registrar un resultado: PostgreSQL -> MongoDB y SQL Server
--      - MongoDB: documento del estudio + resumen_paciente actualizado
--      - SQL Server: factura del estudio para la aseguradora
--      Es la transaccion que involucra a los TRES motores.
CREATE OR REPLACE PROCEDURE public.sp_registrar_resultado(
    p_id_orden     INT,
    p_id_sucursal  INT,
    p_id_medico    INT,
    p_resultado    JSONB,
    p_diagnostico  TEXT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_id_estudio INT;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM ordenes_medicas
                   WHERE id_orden = p_id_orden
                     AND id_sucursal = p_id_sucursal
                     AND estado = 'PENDIENTE') THEN
        RAISE EXCEPTION 'La orden % no existe o no esta pendiente', p_id_orden;
    END IF;

    INSERT INTO resultados_estudios (id_sucursal, id_orden, id_medico_informa, resultado, diagnostico)
    VALUES (p_id_sucursal, p_id_orden, p_id_medico, p_resultado, p_diagnostico)
    RETURNING id_estudio INTO v_id_estudio;

    UPDATE ordenes_medicas SET estado = 'COMPLETADA'
    WHERE id_orden = p_id_orden AND id_sucursal = p_id_sucursal;

    COMMIT;   -- <<< confirmacion en PostgreSQL
    RAISE NOTICE 'PostgreSQL: estudio % confirmado', v_id_estudio;

    BEGIN
        PERFORM mongo.fn_publicar_estudio(v_id_estudio);
        RAISE NOTICE 'MongoDB: estudio % publicado y resumen_paciente actualizado', v_id_estudio;
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'MongoDB no se actualizo (%). Reintentar con SELECT mongo.fn_publicar_estudio(%);',
                      SQLERRM, v_id_estudio;
    END;

    BEGIN
        RAISE NOTICE 'SQL Server: %', mssql.fn_registrar_factura(v_id_estudio);
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'SQL Server no se actualizo (%). Reintentar con SELECT mssql.fn_registrar_factura(%);',
                      SQLERRM, v_id_estudio;
    END;
END;
$$;
