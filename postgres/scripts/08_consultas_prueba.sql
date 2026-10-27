/* =====================================================================
   POSTGRESQL - Script 08: CONSULTAS DE PRUEBA / DEMOSTRACION
   Se recomienda ejecutarlo por bloques durante el video.
   ===================================================================== */
\echo '================================================================'
\echo ' 0) Segmentacion horizontal: filas por fragmento'
\echo '================================================================'
SELECT tableoid::regclass AS fragmento, count(*) AS pacientes
FROM pacientes GROUP BY 1 ORDER BY 1;

-- Al filtrar por sucursal, PostgreSQL solo lee UN fragmento (partition pruning)
EXPLAIN (COSTS OFF) SELECT * FROM pacientes WHERE id_sucursal = 3;


\echo '================================================================'
\echo ' Canales FDW configurados'
\echo '================================================================'
SELECT srvname AS servidor, fdwname AS wrapper, srvoptions AS opciones
FROM pg_foreign_server s JOIN pg_foreign_data_wrapper w ON w.oid = s.srvfdw;

SELECT srvname AS servidor, usename AS rol_local
FROM pg_user_mappings;


\echo '================================================================'
\echo ' OPERACION 1: paciente (PostgreSQL) + estado de facturacion (SQL Server)'
\echo '================================================================'
SET ROLE usr_fdw_pg_mssql;          -- se usa la identidad interna del FDW

SELECT p.id_paciente,
       p.nombre || ' ' || p.apellidos AS paciente,
       p.id_sucursal,
       pi.codigo_externo,
       pi.estado_facturacion,
       a.nombre AS aseguradora
FROM pacientes p
JOIN mssql.paciente_integracion pi ON pi.id_paciente = p.id_paciente
JOIN mssql.aseguradoras a          ON a.id_aseguradora = pi.id_aseguradora
ORDER BY p.id_paciente;

-- Resumen generado por el procedimiento almacenado de SQL Server
SELECT * FROM mssql.resumen_facturacion ORDER BY id_paciente;

-- Sincronizacion de convenios SQL Server -> tabla local
SELECT mssql.fn_sincronizar_convenios() AS convenios_sincronizados;

RESET ROLE;


\echo '================================================================'
\echo ' OPERACION 4: exportacion masiva hacia MongoDB (reportes agregados)'
\echo '================================================================'
SELECT mongo.fn_exportar_resultados()            AS estudios_exportados;
SELECT mongo.fn_exportar_indicadores_mensuales() AS indicadores_exportados;

SET ROLE usr_fdw_pg_mongo;
SELECT mes, sucursal, tipo, cantidad_estudios, ingreso_total
FROM mongo.indicadores_mensuales ORDER BY mes, sucursal, tipo;
RESET ROLE;


\echo '================================================================'
\echo ' OPERACION 2: insercion en PostgreSQL que, tras confirmarse,'
\echo '              actualiza el documento resumen en MongoDB'
\echo '================================================================'
-- Antes: resumen del paciente 1 en MongoDB
SET ROLE usr_fdw_pg_mongo;
SELECT id_paciente, paciente, total_estudios, ultimo_estudio, ultima_fecha
FROM mongo.resumen_paciente WHERE id_paciente = 1;
RESET ROLE;

-- Registrar el resultado de la orden 13 (Glicemia del paciente 1, San Jose)
CALL sp_registrar_resultado(13, 1, 1,
     '{"glicemia": 92, "unidad": "mg/dL"}',
     'Glicemia normal');

-- Despues: el documento en MongoDB ya cambio (total_estudios = 2)
SET ROLE usr_fdw_pg_mongo;
SELECT id_paciente, paciente, total_estudios, ultimo_estudio, ultima_fecha
FROM mongo.resumen_paciente WHERE id_paciente = 1;
RESET ROLE;

-- ...y en SQL Server se creo la factura del estudio nuevo (3 motores)
SET ROLE usr_fdw_pg_mssql;
SELECT id_factura, id_estudio, id_paciente, codigo_estudio, costo, fecha, codigo_institucion, estado
FROM mssql.facturas_externas WHERE id_paciente = 1 ORDER BY id_factura;
RESET ROLE;


\echo '================================================================'
\echo ' OPERACION EXTRA: registrar un paciente en PostgreSQL y enviarlo'
\echo '                  a SQL Server (escritura PostgreSQL -> SQL Server)'
\echo '================================================================'
CALL sp_registrar_paciente(2, '2-2222-0013', 'Sebastián', 'Rojas Umaña', '2000-02-14',
                           'M', '8888-0013', 'sebastian.rojas@correo.com', 2);

-- El paciente quedo en el fragmento de Alajuela...
SELECT tableoid::regclass AS fragmento, id_paciente, nombre, apellidos
FROM pacientes WHERE cedula = '2-2222-0013';

-- ...y su fragmento vertical ya existe en SQL Server
SET ROLE usr_fdw_pg_mssql;
SELECT * FROM mssql.paciente_integracion WHERE id_paciente = 13;
RESET ROLE;


\echo '================================================================'
\echo ' OPERACION 3: vista local + remota para la aplicacion WEB'
\echo '================================================================'
SET ROLE usr_api_web;
SELECT paciente, sucursal, aseguradora, estado_facturacion, total_facturado, total_pendiente
FROM api_web.v_pacientes_facturacion ORDER BY id_paciente;

SELECT * FROM api_web.v_cobertura_ordenes WHERE estado = 'PENDIENTE';
RESET ROLE;


\echo '================================================================'
\echo ' SEGURIDAD: politicas diferenciadas'
\echo '================================================================'
SET ROLE usr_api_mobile;
SELECT * FROM api_movil.v_estado_cuenta WHERE id_paciente = 4;   -- permitido
SELECT * FROM api_movil.v_mis_resultados WHERE id_paciente = 1;  -- permitido
\echo '--- Lo siguiente DEBE fallar (permiso denegado) ---'
SELECT * FROM pacientes LIMIT 1;
SELECT * FROM api_web.v_pacientes_facturacion LIMIT 1;
RESET ROLE;

SELECT rolname, rolcanlogin, rolconnlimit, rolvaliduntil, rolconfig
FROM pg_roles WHERE rolname LIKE 'usr_%' ORDER BY rolname;
