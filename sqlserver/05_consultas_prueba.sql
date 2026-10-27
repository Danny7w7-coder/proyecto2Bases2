/* =====================================================================
   SQL SERVER - Script 05: consultas de prueba (para el video)
   ===================================================================== */
SET QUOTED_IDENTIFIER ON;   -- opciones estandar de SQL Server
SET ANSI_NULLS ON;
GO
USE IntegracionMedica;
GO

-- 1) Fragmento vertical del paciente (solo columnas de interoperabilidad)
SELECT * FROM dbo.paciente_integracion;

-- 2) Facturas externas con su aseguradora
SELECT f.id_factura, f.id_paciente, f.codigo_estudio, f.costo, f.fecha, a.nombre AS aseguradora, f.estado
FROM dbo.facturas_externas f
JOIN dbo.aseguradoras a ON a.codigo_institucion = f.codigo_institucion;

-- 3) Simular que la aseguradora paga una factura y regenerar resumenes
UPDATE dbo.facturas_externas SET estado = 'PAGADA' WHERE id_paciente = 2;
EXEC dbo.sp_actualizar_estado_facturacion;
EXEC dbo.sp_generar_resumen_facturacion;
SELECT * FROM dbo.resumen_facturacion ORDER BY id_paciente;

-- 4) Datos que llegaron DESDE PostgreSQL (paciente 13 y facturas nuevas)
SELECT * FROM dbo.paciente_integracion WHERE id_paciente > 12;
SELECT * FROM dbo.facturas_externas WHERE id_estudio > 12;

-- 5) Probar los permisos de usr_fdw_pg_mssql
EXECUTE AS USER = 'usr_fdw_pg_mssql';
    SELECT TOP 3 * FROM dbo.paciente_integracion;      -- lectura: funciona
    BEGIN TRY
        DELETE FROM dbo.facturas_externas WHERE id_factura = 1;   -- escritura directa: falla (error 229)
    END TRY
    BEGIN CATCH
        SELECT ERROR_NUMBER() AS error, ERROR_MESSAGE() AS mensaje;
    END CATCH
REVERT;
GO
