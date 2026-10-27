/* =====================================================================
   SQL SERVER - Script 06: demostracion en vivo con los tres motores
   ---------------------------------------------------------------------
   Se usa junto con pgAdmin (postgres/scripts/09_pruebas_pgadmin.sql)
   y MongoDB Compass. COMO USARLO: seleccione UN bloque y presione F5
   (SSMS) o Ctrl+Shift+E (extension mssql de VS Code).
   ===================================================================== */
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
USE IntegracionMedica;
GO


-- A) SEGMENTACION VERTICAL: el paciente aqui solo tiene 4 columnas
--    (sin nombre, cedula ni telefono: esos datos viven en PostgreSQL)
SELECT * FROM dbo.paciente_integracion ORDER BY id_paciente;


-- B) ANTES / DESPUES de registrar el resultado en PostgreSQL:
--    facturas del paciente 1. Antes: 1 factura. Despues: aparece la
--    factura del estudio 13, creada desde PostgreSQL.
SELECT id_factura, id_estudio, id_paciente, codigo_estudio, costo, fecha, codigo_institucion, estado
FROM dbo.facturas_externas
WHERE id_paciente = 1
ORDER BY id_factura;


-- C) Resumen generado por el procedimiento almacenado (PostgreSQL lo lee)
SELECT * FROM dbo.resumen_facturacion WHERE id_paciente = 1;


-- D) ANTES / DESPUES de registrar el paciente nuevo en PostgreSQL:
--    antes no hay filas; despues aparece el paciente 13 (AVP-000013)
SELECT * FROM dbo.paciente_integracion WHERE id_paciente = 13;


-- E) SQL SERVER -> POSTGRESQL: la aseguradora paga la factura del
--    estudio 13. Despues de ejecutar este bloque, en pgAdmin la vista
--    api_web.v_pacientes_facturacion muestra al paciente 1 AL_DIA y
--    con 0 pendiente (PostgreSQL lee el cambio en ese momento).
UPDATE dbo.facturas_externas SET estado = 'PAGADA' WHERE id_estudio = 13;
EXEC dbo.sp_actualizar_estado_facturacion;
EXEC dbo.sp_generar_resumen_facturacion;
SELECT id_paciente, aseguradora, total_facturado, total_pagado, total_pendiente
FROM dbo.resumen_facturacion WHERE id_paciente = 1;


-- F) SEGURIDAD: el usuario del FDW puede leer, pero NO borrar (error 229)
EXECUTE AS USER = 'usr_fdw_pg_mssql';
    SELECT TOP 3 * FROM dbo.paciente_integracion;
    DELETE FROM dbo.facturas_externas WHERE id_factura = 1;
REVERT;
