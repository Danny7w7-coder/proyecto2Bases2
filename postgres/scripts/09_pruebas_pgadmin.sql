/* =====================================================================
   PRUEBAS PARA PGADMIN (o DBeaver)
   ---------------------------------------------------------------------
   Desde PostgreSQL se ven los TRES motores:
     - tablas normales      -> datos de PostgreSQL
     - esquema  mssql.*     -> datos que viven en SQL Server
     - esquema  mongo.*     -> datos que viven en MongoDB

   COMO USARLO: seleccione con el mouse UN bloque (desde su comentario
   hasta el punto y coma) y presione F5. El resultado aparece abajo,
   en la pestana "Data Output".
   Los bloques 6 y 9 MODIFICAN datos: solo funcionan una vez.
   Para repetir: powershell -ExecutionPolicy Bypass -File .\instalar.ps1 -Reiniciar
   ===================================================================== */


-- 1) SEGMENTACION HORIZONTAL: cuantos pacientes hay en cada fragmento
SELECT tableoid::regclass AS fragmento, count(*) AS pacientes
FROM pacientes
GROUP BY 1
ORDER BY 1;


-- 2) Al buscar por sucursal, PostgreSQL lee SOLO un fragmento
--    (el resultado dice "Seq Scan on pacientes_cartago")
EXPLAIN SELECT * FROM pacientes WHERE id_sucursal = 3;


-- 3) DATOS DE SQL SERVER vistos desde PostgreSQL (segmentacion vertical:
--    solo 4 columnas, sin nombre ni cedula)
SELECT * FROM mssql.paciente_integracion ORDER BY id_paciente;


-- 4) OPERACION 1: paciente (PostgreSQL) + facturacion (SQL Server)
SELECT p.nombre || ' ' || p.apellidos AS paciente,
       s.nombre                       AS sucursal,
       pi.estado_facturacion          AS estado_en_sql_server,
       a.nombre                       AS aseguradora_en_sql_server
FROM pacientes p
JOIN sucursales s                  ON s.id_sucursal   = p.id_sucursal
JOIN mssql.paciente_integracion pi ON pi.id_paciente  = p.id_paciente
JOIN mssql.aseguradoras a          ON a.id_aseguradora = pi.id_aseguradora
ORDER BY p.id_paciente;


-- 5) DATOS DE MONGODB vistos desde PostgreSQL: resumen de cada paciente
SELECT id_paciente, paciente, sucursal, total_estudios, ultimo_estudio
FROM mongo.resumen_paciente
ORDER BY id_paciente;


-- 6) OPERACION 2 (modifica datos): registrar un resultado.
--    Se guarda en PostgreSQL, se confirma, y despues se actualiza
--    MongoDB y se crea la factura en SQL Server.
--    Los mensajes salen en la pestana "Messages".
CALL sp_registrar_resultado(13, 1, 1, '{"glicemia": 92, "unidad": "mg/dL"}', 'Glicemia normal');


-- 7) Comprobar el bloque 6: el paciente 1 ahora tiene 2 estudios en
--    MongoDB y una factura nueva (id_estudio 13) en SQL Server
SELECT 'MongoDB'    AS motor, paciente AS detalle, total_estudios::text AS valor
FROM mongo.resumen_paciente WHERE id_paciente = 1
UNION ALL
SELECT 'SQL Server', 'factura del estudio ' || id_estudio || ' (' || codigo_estudio || ')', estado
FROM mssql.facturas_externas WHERE id_paciente = 1;


-- 8) OPERACION 3: la vista que usa la aplicacion web (mezcla PostgreSQL
--    y SQL Server)
SELECT * FROM api_web.v_pacientes_facturacion ORDER BY id_paciente;


-- 9) PostgreSQL escribe en SQL Server (modifica datos): paciente nuevo
CALL sp_registrar_paciente(2, '2-2222-0013', 'Sebastián', 'Rojas Umaña', '2000-02-14',
                           'M', '8888-0013', 'sebastian.rojas@correo.com', 2);


-- 10) Comprobar el bloque 9: el paciente quedo en el fragmento de
--     Alajuela y su informacion llego a SQL Server
SELECT p.tableoid::regclass AS fragmento_postgresql, p.nombre, p.apellidos,
       pi.codigo_externo     AS codigo_en_sql_server
FROM pacientes p
JOIN mssql.paciente_integracion pi ON pi.id_paciente = p.id_paciente
WHERE p.cedula = '2-2222-0013';


-- 11) OPERACION 4: indicadores mensuales guardados en MongoDB
SELECT mes, sucursal, tipo, cantidad_estudios, ingreso_total
FROM mongo.indicadores_mensuales
ORDER BY mes, sucursal, tipo;
