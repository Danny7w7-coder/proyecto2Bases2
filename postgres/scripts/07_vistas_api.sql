/* =====================================================================
   POSTGRESQL - Script 07: vistas para las aplicaciones y permisos

   Las aplicaciones NUNCA ven las tablas directamente, solo vistas:
     schema api_web   -> usr_api_web    (datos completos)
     schema api_movil -> usr_api_mobile (datos simplificados, sin
                                         cedula, correo ni JSON)
   Las vistas que combinan datos LOCALES + REMOTOS (SQL Server) tienen
   como dueno a usr_fdw_pg_mssql, para que la conexion remota se haga
   con ese usuario interno y no con el de la aplicacion.
   ===================================================================== */

CREATE SCHEMA api_web;
CREATE SCHEMA api_movil;

-- =====================================================================
-- Vistas WEB
-- =====================================================================

-- Operacion #3: vista que combina datos locales + remotos (SQL Server)
CREATE VIEW api_web.v_pacientes_facturacion AS
SELECT p.id_paciente,
       p.cedula,
       p.nombre || ' ' || p.apellidos  AS paciente,
       s.nombre                        AS sucursal,
       pi.codigo_externo,
       rf.aseguradora,
       pi.estado_facturacion,
       rf.cantidad_facturas,
       rf.total_facturado,
       rf.total_pagado,
       rf.total_pendiente,
       rf.ultima_factura
FROM pacientes p
JOIN sucursales s                    ON s.id_sucursal  = p.id_sucursal
LEFT JOIN mssql.paciente_integracion pi ON pi.id_paciente = p.id_paciente
LEFT JOIN mssql.resumen_facturacion  rf ON rf.id_paciente = p.id_paciente;
ALTER VIEW api_web.v_pacientes_facturacion OWNER TO usr_fdw_pg_mssql;

-- Estudios con resultado completo (JSON) y diagnostico (solo local)
CREATE VIEW api_web.v_estudios AS
SELECT r.id_estudio,
       p.id_paciente,
       p.nombre || ' ' || p.apellidos  AS paciente,
       t.nombre                        AS estudio,
       t.categoria,
       m.nombre                        AS medico,
       s.nombre                        AS sucursal,
       r.fecha_resultado,
       r.resultado,
       r.diagnostico
FROM resultados_estudios r
JOIN ordenes_medicas o ON o.id_orden = r.id_orden AND o.id_sucursal = r.id_sucursal
JOIN pacientes p       ON p.id_paciente = o.id_paciente AND p.id_sucursal = o.id_sucursal
JOIN tipos_estudio t   ON t.codigo_estudio = o.codigo_estudio
JOIN medicos m         ON m.id_medico = r.id_medico_informa
JOIN sucursales s      ON s.id_sucursal = r.id_sucursal;

-- Citas
CREATE VIEW api_web.v_citas AS
SELECT c.id_cita, p.id_paciente, p.nombre || ' ' || p.apellidos AS paciente,
       m.nombre AS medico, s.nombre AS sucursal, c.fecha_hora, c.motivo, c.estado
FROM citas c
JOIN pacientes p  ON p.id_paciente = c.id_paciente AND p.id_sucursal = c.id_sucursal
JOIN medicos m    ON m.id_medico = c.id_medico
JOIN sucursales s ON s.id_sucursal = c.id_sucursal;

-- Costo para el paciente segun el convenio (copia sincronizada de SQL Server)
CREATE VIEW api_web.v_cobertura_ordenes AS
SELECT o.id_orden, o.id_paciente, t.nombre AS estudio, t.costo_base,
       COALESCE(cc.porcentaje_cobertura, 0) AS porcentaje_cobertura,
       round(t.costo_base * (1 - COALESCE(cc.porcentaje_cobertura, 0) / 100), 2) AS monto_paciente,
       o.estado
FROM ordenes_medicas o
JOIN tipos_estudio t ON t.codigo_estudio = o.codigo_estudio
LEFT JOIN mssql.paciente_integracion pi ON pi.id_paciente = o.id_paciente
LEFT JOIN convenios_cache cc ON cc.id_aseguradora = pi.id_aseguradora
                            AND cc.codigo_estudio = o.codigo_estudio;
ALTER VIEW api_web.v_cobertura_ordenes OWNER TO usr_fdw_pg_mssql;
GRANT SELECT ON ordenes_medicas, tipos_estudio TO usr_fdw_pg_mssql;
GRANT SELECT ON convenios_cache TO usr_fdw_pg_mssql;

-- =====================================================================
-- Vistas MOVIL (simplificadas)
-- =====================================================================
CREATE VIEW api_movil.v_mis_citas AS
SELECT c.id_paciente, c.fecha_hora, m.nombre AS medico, s.nombre AS sucursal, c.estado
FROM citas c
JOIN medicos m    ON m.id_medico = c.id_medico
JOIN sucursales s ON s.id_sucursal = c.id_sucursal;

CREATE VIEW api_movil.v_mis_resultados AS
SELECT o.id_paciente, t.nombre AS estudio, r.fecha_resultado::date AS fecha, r.diagnostico
FROM resultados_estudios r
JOIN ordenes_medicas o ON o.id_orden = r.id_orden AND o.id_sucursal = r.id_sucursal
JOIN tipos_estudio t   ON t.codigo_estudio = o.codigo_estudio;

CREATE VIEW api_movil.v_estado_cuenta AS
SELECT pi.id_paciente, pi.estado_facturacion, rf.total_pendiente
FROM mssql.paciente_integracion pi
LEFT JOIN mssql.resumen_facturacion rf ON rf.id_paciente = pi.id_paciente;
ALTER VIEW api_movil.v_estado_cuenta OWNER TO usr_fdw_pg_mssql;

-- =====================================================================
-- Permisos de las aplicaciones (solo SELECT sobre SUS vistas)
-- =====================================================================
GRANT USAGE  ON SCHEMA api_web TO usr_api_web;
GRANT SELECT ON ALL TABLES IN SCHEMA api_web TO usr_api_web;

GRANT USAGE  ON SCHEMA api_movil TO usr_api_mobile;
GRANT SELECT ON ALL TABLES IN SCHEMA api_movil TO usr_api_mobile;

-- Las vistas de api_web/api_movil cuyo dueno es usr_fdw_pg_mssql
-- necesitan que ese rol pueda entrar a los esquemas
GRANT USAGE ON SCHEMA api_web, api_movil TO usr_fdw_pg_mssql;
