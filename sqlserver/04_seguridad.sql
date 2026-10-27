/* =====================================================================
   SQL SERVER - Script 04: usuarios y permisos
   Perfil interno usr_fdw_pg_mssql: es el usuario con el que
   PostgreSQL (tds_fdw) inicia sesion en SQL Server.
   Permisos MINIMOS:
     - LECTURA (SELECT) de las tablas de integracion.
     - ESCRITURA LIMITADA: solo puede ejecutar 2 procedimientos
       (registrar paciente y registrar factura). No puede hacer
       INSERT / UPDATE / DELETE directo sobre ninguna tabla.
   ===================================================================== */
SET QUOTED_IDENTIFIER ON;   -- opciones estandar de SQL Server
SET ANSI_NULLS ON;
GO
USE master;
GO

IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = 'usr_fdw_pg_mssql')
    CREATE LOGIN usr_fdw_pg_mssql
        WITH PASSWORD = 'Fdw_Mssql2026!',
             DEFAULT_DATABASE = IntegracionMedica,
             CHECK_POLICY = ON;          -- aplica la politica de contrasenas
GO

USE IntegracionMedica;
GO

IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'usr_fdw_pg_mssql')
    CREATE USER usr_fdw_pg_mssql FOR LOGIN usr_fdw_pg_mssql;
GO

/* Rol de base de datos con los permisos del FDW */
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'rol_fdw_integracion' AND type = 'R')
    CREATE ROLE rol_fdw_integracion;
GO

/* Lectura */
GRANT SELECT ON dbo.aseguradoras              TO rol_fdw_integracion;
GRANT SELECT ON dbo.paciente_integracion      TO rol_fdw_integracion;
GRANT SELECT ON dbo.convenios                 TO rol_fdw_integracion;
GRANT SELECT ON dbo.facturas_externas         TO rol_fdw_integracion;
GRANT SELECT ON dbo.resumen_facturacion       TO rol_fdw_integracion;
GRANT SELECT ON dbo.v_facturacion_aseguradora TO rol_fdw_integracion;

/* Escritura limitada: solo por medio de procedimientos */
GRANT EXECUTE ON dbo.sp_registrar_paciente_integracion TO rol_fdw_integracion;
GRANT EXECUTE ON dbo.sp_registrar_factura              TO rol_fdw_integracion;

/* Prohibido modificar tablas directamente.
   (Los procedimientos si pueden insertar gracias al "encadenamiento
   de propiedad": el procedimiento y las tablas tienen el mismo dueno,
   dbo, entonces SQL Server no revisa los permisos de las tablas.) */
DENY INSERT, UPDATE, DELETE ON SCHEMA::dbo TO rol_fdw_integracion;
GO

ALTER ROLE rol_fdw_integracion ADD MEMBER usr_fdw_pg_mssql;
GO

/* Verificacion: permisos efectivos del rol */
SELECT dp.name AS rol, p.permission_name, p.state_desc, o.name AS objeto
FROM sys.database_permissions p
JOIN sys.database_principals dp ON dp.principal_id = p.grantee_principal_id
LEFT JOIN sys.objects o ON o.object_id = p.major_id
WHERE dp.name = 'rol_fdw_integracion';
GO
