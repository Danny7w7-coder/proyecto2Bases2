/* =====================================================================
   SQL SERVER - Script 03: procedimientos almacenados
   Generan resumenes que luego PostgreSQL consulta via tds_fdw.
   ===================================================================== */
SET QUOTED_IDENTIFIER ON;   -- opciones estandar de SQL Server
SET ANSI_NULLS ON;
GO
USE IntegracionMedica;
GO

/* ---------------------------------------------------------------------
   sp_generar_resumen_facturacion
   Recalcula, por paciente, cuanto se ha facturado, pagado y queda
   pendiente. Deja el resultado en dbo.resumen_facturacion.
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.sp_generar_resumen_facturacion
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRANSACTION;

        DELETE FROM dbo.resumen_facturacion;

        INSERT INTO dbo.resumen_facturacion
              (id_paciente, aseguradora, cantidad_facturas,
               total_facturado, total_pagado, total_pendiente, ultima_factura)
        SELECT pi.id_paciente,
               a.nombre,
               COUNT(f.id_factura),
               ISNULL(SUM(f.costo), 0),
               ISNULL(SUM(CASE WHEN f.estado = 'PAGADA'    THEN f.costo END), 0),
               ISNULL(SUM(CASE WHEN f.estado = 'PENDIENTE' THEN f.costo END), 0),
               MAX(f.fecha)
        FROM dbo.paciente_integracion pi
        JOIN dbo.aseguradoras a        ON a.id_aseguradora = pi.id_aseguradora
        LEFT JOIN dbo.facturas_externas f ON f.id_paciente = pi.id_paciente
        GROUP BY pi.id_paciente, a.nombre;

    COMMIT TRANSACTION;
END;
GO

/* ---------------------------------------------------------------------
   sp_actualizar_estado_facturacion
   Regla de negocio: si un paciente tiene facturas RECHAZADAS queda
   MOROSO, si tiene PENDIENTES queda PENDIENTE, si no AL_DIA.
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.sp_actualizar_estado_facturacion
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE pi
    SET estado_facturacion =
        CASE
            WHEN EXISTS (SELECT 1 FROM dbo.facturas_externas f
                         WHERE f.id_paciente = pi.id_paciente AND f.estado = 'RECHAZADA') THEN 'MOROSO'
            WHEN EXISTS (SELECT 1 FROM dbo.facturas_externas f
                         WHERE f.id_paciente = pi.id_paciente AND f.estado = 'PENDIENTE') THEN 'PENDIENTE'
            ELSE 'AL_DIA'
        END
    FROM dbo.paciente_integracion pi;
END;
GO

/* Vista con la facturacion por aseguradora (tambien la lee PostgreSQL) */
CREATE OR ALTER VIEW dbo.v_facturacion_aseguradora
AS
SELECT a.codigo_institucion,
       a.nombre                 AS aseguradora,
       COUNT(f.id_factura)      AS cantidad_facturas,
       ISNULL(SUM(f.costo), 0)  AS total_facturado
FROM dbo.aseguradoras a
LEFT JOIN dbo.facturas_externas f ON f.codigo_institucion = a.codigo_institucion
GROUP BY a.codigo_institucion, a.nombre;
GO

/* =====================================================================
   PROCEDIMIENTOS DE ENTRADA (PostgreSQL -> SQL Server)
   tds_fdw no permite INSERT directo. PostgreSQL ejecuta estos
   procedimientos a traves del FDW (opcion "query"), y ellos son la
   UNICA forma en que usr_fdw_pg_mssql puede escribir ("escritura
   limitada"). Cada uno devuelve una fila con el resultado.
   Son idempotentes: si se ejecutan dos veces no duplican datos.
   ===================================================================== */

/* Registra (o actualiza) el fragmento vertical de un paciente nuevo */
CREATE OR ALTER PROCEDURE dbo.sp_registrar_paciente_integracion
    @id_paciente    INT,
    @id_aseguradora INT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @codigo VARCHAR(20);

    SELECT @codigo = CONCAT(LEFT(codigo_institucion, 3), '-', RIGHT(CONCAT('000000', @id_paciente), 6))
    FROM dbo.aseguradoras WHERE id_aseguradora = @id_aseguradora;

    IF @codigo IS NULL
    BEGIN
        SELECT CONCAT('ERROR: aseguradora ', @id_aseguradora, ' no existe') AS resultado;
        RETURN;
    END;

    IF EXISTS (SELECT 1 FROM dbo.paciente_integracion WHERE id_paciente = @id_paciente)
        UPDATE dbo.paciente_integracion
        SET id_aseguradora = @id_aseguradora, codigo_externo = @codigo
        WHERE id_paciente = @id_paciente;
    ELSE
        INSERT INTO dbo.paciente_integracion (id_paciente, id_aseguradora, codigo_externo, estado_facturacion)
        VALUES (@id_paciente, @id_aseguradora, @codigo, 'AL_DIA');

    SELECT CONCAT('OK: paciente ', @id_paciente, ' registrado con codigo ', @codigo) AS resultado;
END;
GO

/* Crea la factura de un estudio realizado y recalcula los resumenes */
CREATE OR ALTER PROCEDURE dbo.sp_registrar_factura
    @id_estudio     INT,
    @id_paciente    INT,
    @codigo_estudio VARCHAR(10),
    @costo          DECIMAL(12,2),
    @fecha          DATE
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @institucion VARCHAR(10);

    SELECT @institucion = a.codigo_institucion
    FROM dbo.paciente_integracion pi
    JOIN dbo.aseguradoras a ON a.id_aseguradora = pi.id_aseguradora
    WHERE pi.id_paciente = @id_paciente;

    IF @institucion IS NULL
    BEGIN
        SELECT CONCAT('ERROR: paciente ', @id_paciente, ' no esta en paciente_integracion') AS resultado;
        RETURN;
    END;

    IF NOT EXISTS (SELECT 1 FROM dbo.facturas_externas WHERE id_estudio = @id_estudio)
        INSERT INTO dbo.facturas_externas (id_estudio, id_paciente, codigo_estudio, costo, fecha, codigo_institucion, estado)
        VALUES (@id_estudio, @id_paciente, @codigo_estudio, @costo, @fecha, @institucion, 'PENDIENTE');

    EXEC dbo.sp_actualizar_estado_facturacion;
    EXEC dbo.sp_generar_resumen_facturacion;

    SELECT CONCAT('OK: factura del estudio ', @id_estudio, ' enviada a ', @institucion) AS resultado;
END;
GO

/* Ejecucion inicial */
EXEC dbo.sp_actualizar_estado_facturacion;
EXEC dbo.sp_generar_resumen_facturacion;
GO
