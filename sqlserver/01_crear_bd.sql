/* =====================================================================
   SQL SERVER - INTEGRACION EXTERNA
   Script 01: creacion de la base de datos y tablas.

   SEGMENTACION VERTICAL:
   El paciente "completo" vive en PostgreSQL (nombre, cedula, telefono,
   correo, fecha de nacimiento...). Aqui SOLO se guardan las columnas
   que necesitan las aseguradoras, el ministerio y facturacion:
       paciente_integracion(id_paciente, id_aseguradora,
                            codigo_externo, estado_facturacion)
   Lo mismo con los estudios: facturas_externas solo guarda
   id_paciente, codigo_estudio, costo, fecha y codigo_institucion.
   El "id_paciente" y el "codigo_estudio" son las llaves comunes que
   permiten unir (JOIN) los fragmentos desde PostgreSQL.
   ===================================================================== */
SET QUOTED_IDENTIFIER ON;   -- opciones estandar de SQL Server
SET ANSI_NULLS ON;
GO

IF DB_ID('IntegracionMedica') IS NULL
    CREATE DATABASE IntegracionMedica;
GO

USE IntegracionMedica;
GO

/* ---------- Aseguradoras / instituciones externas ---------- */
CREATE TABLE dbo.aseguradoras (
    id_aseguradora      INT          NOT NULL PRIMARY KEY,
    nombre              VARCHAR(100) NOT NULL,
    codigo_institucion  VARCHAR(10)  NOT NULL UNIQUE,
    tipo                VARCHAR(20)  NOT NULL
        CHECK (tipo IN ('PRIVADA', 'PUBLICA'))
);
GO

/* ---------- Fragmento vertical del paciente ---------- */
CREATE TABLE dbo.paciente_integracion (
    id_paciente         INT          NOT NULL PRIMARY KEY,  -- mismo id que en PostgreSQL
    id_aseguradora      INT          NOT NULL
        REFERENCES dbo.aseguradoras(id_aseguradora),
    codigo_externo      VARCHAR(20)  NOT NULL UNIQUE,       -- id del paciente en la aseguradora
    estado_facturacion  VARCHAR(15)  NOT NULL
        CHECK (estado_facturacion IN ('AL_DIA', 'PENDIENTE', 'MOROSO'))
);
GO

/* ---------- Convenios: cuanto cubre cada aseguradora por estudio ---------- */
CREATE TABLE dbo.convenios (
    id_convenio          INT IDENTITY(1,1) PRIMARY KEY,
    id_aseguradora       INT          NOT NULL
        REFERENCES dbo.aseguradoras(id_aseguradora),
    codigo_estudio       VARCHAR(10)  NOT NULL,             -- mismo codigo que en PostgreSQL
    porcentaje_cobertura DECIMAL(5,2) NOT NULL
        CHECK (porcentaje_cobertura BETWEEN 0 AND 100),
    estado               VARCHAR(10)  NOT NULL DEFAULT 'ACTIVO'
        CHECK (estado IN ('ACTIVO', 'INACTIVO')),
    CONSTRAINT uq_convenio UNIQUE (id_aseguradora, codigo_estudio)
);
GO

/* ---------- Fragmento vertical de los estudios: solo datos de cobro ---------- */
CREATE TABLE dbo.facturas_externas (
    id_factura          INT IDENTITY(1,1) PRIMARY KEY,
    id_estudio          INT           NULL,                 -- estudio de origen en PostgreSQL
    id_paciente         INT           NOT NULL
        REFERENCES dbo.paciente_integracion(id_paciente),
    codigo_estudio      VARCHAR(10)   NOT NULL,
    costo               DECIMAL(12,2) NOT NULL CHECK (costo >= 0),
    fecha               DATE          NOT NULL,
    codigo_institucion  VARCHAR(10)   NOT NULL,
    estado              VARCHAR(12)   NOT NULL
        CHECK (estado IN ('PAGADA', 'PENDIENTE', 'RECHAZADA'))
);
GO

/* Un estudio solo se factura una vez: lo controla sp_registrar_factura.
   (No se usa un indice filtrado UNIQUE porque exige opciones ANSI que la
   conexion de tds_fdw/FreeTDS no activa, y el INSERT fallaria.) */
CREATE INDEX ix_factura_estudio ON dbo.facturas_externas(id_estudio);
GO

/* ---------- Tabla de resumen que llena el procedimiento almacenado ---------- */
/*  PostgreSQL la consulta por FDW (tds_fdw es de solo lectura, por eso
    el procedimiento deja el resultado "listo" en una tabla).          */
CREATE TABLE dbo.resumen_facturacion (
    id_paciente         INT           NOT NULL PRIMARY KEY,
    aseguradora         VARCHAR(100)  NOT NULL,
    cantidad_facturas   INT           NOT NULL,
    total_facturado     DECIMAL(14,2) NOT NULL,
    total_pagado        DECIMAL(14,2) NOT NULL,
    total_pendiente     DECIMAL(14,2) NOT NULL,
    ultima_factura      DATE          NULL,
    fecha_generacion    DATETIME2     NOT NULL DEFAULT SYSDATETIME()
);
GO
