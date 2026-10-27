/* =====================================================================
   SQL SERVER - Script 02: datos de prueba
   Los id_paciente (1..12) y codigo_estudio coinciden con PostgreSQL.
   ===================================================================== */
SET QUOTED_IDENTIFIER ON;   -- opciones estandar de SQL Server
SET ANSI_NULLS ON;
GO
USE IntegracionMedica;
GO

INSERT INTO dbo.aseguradoras (id_aseguradora, nombre, codigo_institucion, tipo) VALUES
 (1, 'Seguro Social Publico',  'SSP-01', 'PUBLICA'),
 (2, 'Aseguradora Vida Plena', 'AVP-02', 'PRIVADA'),
 (3, 'MediSeguro Central',     'MSC-03', 'PRIVADA');
GO

INSERT INTO dbo.paciente_integracion (id_paciente, id_aseguradora, codigo_externo, estado_facturacion) VALUES
 ( 1, 1, 'SSP-000101', 'AL_DIA'),
 ( 2, 2, 'AVP-000102', 'PENDIENTE'),
 ( 3, 1, 'SSP-000103', 'AL_DIA'),
 ( 4, 3, 'MSC-000104', 'MOROSO'),
 ( 5, 1, 'SSP-000105', 'AL_DIA'),
 ( 6, 2, 'AVP-000106', 'AL_DIA'),
 ( 7, 3, 'MSC-000107', 'PENDIENTE'),
 ( 8, 1, 'SSP-000108', 'AL_DIA'),
 ( 9, 2, 'AVP-000109', 'MOROSO'),
 (10, 1, 'SSP-000110', 'AL_DIA'),
 (11, 3, 'MSC-000111', 'AL_DIA'),
 (12, 1, 'SSP-000112', 'PENDIENTE');
GO

INSERT INTO dbo.convenios (id_aseguradora, codigo_estudio, porcentaje_cobertura) VALUES
 (1, 'LAB-HEM', 100), (1, 'LAB-GLU', 100), (1, 'LAB-LIP', 100),
 (1, 'RX-TOR',   80), (1, 'US-ABD',   70), (1, 'US-OBS',  100),
 (2, 'LAB-HEM',  90), (2, 'LAB-GLU',  90), (2, 'LAB-LIP',  80),
 (2, 'RX-TOR',   75), (2, 'US-ABD',   60), (2, 'US-OBS',   80),
 (3, 'LAB-HEM',  70), (3, 'RX-TOR',   50), (3, 'US-ABD',   50);
GO

/* Una factura por cada estudio ya realizado en PostgreSQL (estudios 1..12) */
INSERT INTO dbo.facturas_externas (id_estudio, id_paciente, codigo_estudio, costo, fecha, codigo_institucion, estado) VALUES
 ( 1,  1, 'LAB-HEM', 12000, '2026-09-02', 'SSP-01', 'PAGADA'),
 ( 2,  2, 'RX-TOR',  25000, '2026-09-03', 'AVP-02', 'PENDIENTE'),
 ( 3,  3, 'US-ABD',  45000, '2026-09-05', 'SSP-01', 'PAGADA'),
 ( 4,  4, 'LAB-LIP', 15000, '2026-09-08', 'MSC-03', 'RECHAZADA'),
 ( 5,  5, 'LAB-GLU',  5000, '2026-09-10', 'SSP-01', 'PAGADA'),
 ( 6,  6, 'RX-TOR',  25000, '2026-09-12', 'AVP-02', 'PAGADA'),
 ( 7,  7, 'US-ABD',  45000, '2026-09-15', 'MSC-03', 'PENDIENTE'),
 ( 8,  8, 'LAB-HEM', 12000, '2026-09-18', 'SSP-01', 'PAGADA'),
 ( 9,  9, 'US-OBS',  50000, '2026-09-20', 'AVP-02', 'RECHAZADA'),
 (10, 10, 'LAB-LIP', 15000, '2026-10-01', 'SSP-01', 'PAGADA'),
 (11, 11, 'RX-TOR',  25000, '2026-10-04', 'MSC-03', 'PAGADA'),
 (12, 12, 'US-OBS',  50000, '2026-10-06', 'SSP-01', 'PENDIENTE');
GO
