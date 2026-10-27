/* =====================================================================
   POSTGRESQL - NUCLEO TRANSACCIONAL
   Script 01: modelo de datos con SEGMENTACION HORIZONTAL.

   Idea: los datos de pacientes, citas, ordenes y resultados se dividen
   por FILAS segun la sucursal (region) a la que pertenecen:
       id_sucursal = 1  -> San Jose   -> pacientes_san_jose
       id_sucursal = 2  -> Alajuela   -> pacientes_alajuela
       id_sucursal = 3  -> Cartago    -> pacientes_cartago
   Se usa el particionamiento declarativo de PostgreSQL (PARTITION BY
   LIST). La aplicacion consulta la tabla "padre" (pacientes) y
   PostgreSQL envia cada fila al fragmento correcto automaticamente.

   Tablas de catalogo (sucursales, medicos, tipos_estudio,
   usuarios_admin) NO se segmentan porque son pequenas y todas las
   sucursales las necesitan.
   ===================================================================== */

-- ---------------------------------------------------------------------
-- Catalogos (no segmentados)
-- ---------------------------------------------------------------------
CREATE TABLE sucursales (
    id_sucursal  SMALLINT    PRIMARY KEY,
    codigo       VARCHAR(5)  NOT NULL UNIQUE,
    nombre       VARCHAR(50) NOT NULL,
    provincia    VARCHAR(30) NOT NULL
);

CREATE TABLE medicos (
    id_medico     SERIAL       PRIMARY KEY,
    nombre        VARCHAR(100) NOT NULL,
    especialidad  VARCHAR(60)  NOT NULL,
    codigo_colegio VARCHAR(15) NOT NULL UNIQUE,
    id_sucursal   SMALLINT     NOT NULL REFERENCES sucursales(id_sucursal)
);

CREATE TABLE tipos_estudio (
    codigo_estudio VARCHAR(10)   PRIMARY KEY,         -- mismo codigo usado en SQL Server
    nombre         VARCHAR(80)   NOT NULL,
    categoria      VARCHAR(20)   NOT NULL
        CHECK (categoria IN ('Laboratorio', 'Radiografia', 'Ultrasonido')),
    costo_base     NUMERIC(12,2) NOT NULL CHECK (costo_base >= 0)
);

CREATE TABLE usuarios_admin (
    id_usuario   SERIAL      PRIMARY KEY,
    nombre       VARCHAR(100) NOT NULL,
    usuario      VARCHAR(30)  NOT NULL UNIQUE,
    puesto       VARCHAR(30)  NOT NULL
        CHECK (puesto IN ('RECEPCION', 'FACTURACION', 'ADMINISTRADOR')),
    id_sucursal  SMALLINT     NOT NULL REFERENCES sucursales(id_sucursal)
);

-- ---------------------------------------------------------------------
-- PACIENTES (segmentado horizontalmente por sucursal)
-- En una tabla particionada la llave primaria debe incluir la columna
-- de particion, por eso la PK es (id_paciente, id_sucursal).
-- ---------------------------------------------------------------------
CREATE TABLE pacientes (
    id_paciente      SERIAL,
    id_sucursal      SMALLINT     NOT NULL REFERENCES sucursales(id_sucursal),
    cedula           VARCHAR(15)  NOT NULL,
    nombre           VARCHAR(60)  NOT NULL,
    apellidos        VARCHAR(80)  NOT NULL,
    fecha_nacimiento DATE         NOT NULL,
    sexo             CHAR(1)      NOT NULL CHECK (sexo IN ('F', 'M')),
    telefono         VARCHAR(15),
    correo           VARCHAR(100),
    PRIMARY KEY (id_paciente, id_sucursal),
    UNIQUE (cedula, id_sucursal)
) PARTITION BY LIST (id_sucursal);

CREATE TABLE pacientes_san_jose PARTITION OF pacientes FOR VALUES IN (1);
CREATE TABLE pacientes_alajuela PARTITION OF pacientes FOR VALUES IN (2);
CREATE TABLE pacientes_cartago  PARTITION OF pacientes FOR VALUES IN (3);

-- ---------------------------------------------------------------------
-- CITAS (segmentado horizontalmente por sucursal)
-- ---------------------------------------------------------------------
CREATE TABLE citas (
    id_cita      SERIAL,
    id_sucursal  SMALLINT    NOT NULL,
    id_paciente  INT         NOT NULL,
    id_medico    INT         NOT NULL REFERENCES medicos(id_medico),
    fecha_hora   TIMESTAMP   NOT NULL,
    motivo       VARCHAR(150),
    estado       VARCHAR(12) NOT NULL DEFAULT 'PROGRAMADA'
        CHECK (estado IN ('PROGRAMADA', 'ATENDIDA', 'CANCELADA')),
    PRIMARY KEY (id_cita, id_sucursal),
    FOREIGN KEY (id_paciente, id_sucursal) REFERENCES pacientes(id_paciente, id_sucursal)
) PARTITION BY LIST (id_sucursal);

CREATE TABLE citas_san_jose PARTITION OF citas FOR VALUES IN (1);
CREATE TABLE citas_alajuela PARTITION OF citas FOR VALUES IN (2);
CREATE TABLE citas_cartago  PARTITION OF citas FOR VALUES IN (3);

-- ---------------------------------------------------------------------
-- ORDENES MEDICAS (segmentado horizontalmente por sucursal)
-- ---------------------------------------------------------------------
CREATE TABLE ordenes_medicas (
    id_orden       SERIAL,
    id_sucursal    SMALLINT    NOT NULL,
    id_paciente    INT         NOT NULL,
    id_medico      INT         NOT NULL REFERENCES medicos(id_medico),   -- medico que ordena
    codigo_estudio VARCHAR(10) NOT NULL REFERENCES tipos_estudio(codigo_estudio),
    fecha_orden    DATE        NOT NULL DEFAULT CURRENT_DATE,
    estado         VARCHAR(12) NOT NULL DEFAULT 'PENDIENTE'
        CHECK (estado IN ('PENDIENTE', 'COMPLETADA', 'ANULADA')),
    PRIMARY KEY (id_orden, id_sucursal),
    FOREIGN KEY (id_paciente, id_sucursal) REFERENCES pacientes(id_paciente, id_sucursal)
) PARTITION BY LIST (id_sucursal);

CREATE TABLE ordenes_medicas_san_jose PARTITION OF ordenes_medicas FOR VALUES IN (1);
CREATE TABLE ordenes_medicas_alajuela PARTITION OF ordenes_medicas FOR VALUES IN (2);
CREATE TABLE ordenes_medicas_cartago  PARTITION OF ordenes_medicas FOR VALUES IN (3);

-- ---------------------------------------------------------------------
-- RESULTADOS DE ESTUDIOS + DIAGNOSTICO (segmentado por sucursal)
-- El resultado se guarda en JSONB porque cada tipo de estudio tiene
-- campos distintos (hemograma != ultrasonido).
-- ---------------------------------------------------------------------
CREATE TABLE resultados_estudios (
    id_estudio        SERIAL,
    id_sucursal       SMALLINT  NOT NULL,
    id_orden          INT       NOT NULL,
    id_medico_informa INT       NOT NULL REFERENCES medicos(id_medico),  -- medico que realiza/informa
    fecha_resultado   TIMESTAMP NOT NULL DEFAULT now(),
    resultado         JSONB     NOT NULL,
    diagnostico       TEXT,
    PRIMARY KEY (id_estudio, id_sucursal),
    UNIQUE (id_orden, id_sucursal),                       -- un resultado por orden
    FOREIGN KEY (id_orden, id_sucursal) REFERENCES ordenes_medicas(id_orden, id_sucursal)
) PARTITION BY LIST (id_sucursal);

CREATE TABLE resultados_estudios_san_jose PARTITION OF resultados_estudios FOR VALUES IN (1);
CREATE TABLE resultados_estudios_alajuela PARTITION OF resultados_estudios FOR VALUES IN (2);
CREATE TABLE resultados_estudios_cartago  PARTITION OF resultados_estudios FOR VALUES IN (3);

-- ---------------------------------------------------------------------
-- Copia local de convenios (se sincroniza desde SQL Server por FDW)
-- ---------------------------------------------------------------------
CREATE TABLE convenios_cache (
    id_aseguradora       INT,
    codigo_estudio       VARCHAR(10),
    porcentaje_cobertura NUMERIC(5,2),
    fecha_sincronizacion TIMESTAMP NOT NULL DEFAULT now(),
    PRIMARY KEY (id_aseguradora, codigo_estudio)
);

-- Indices de apoyo
CREATE INDEX idx_citas_paciente      ON citas (id_paciente);
CREATE INDEX idx_ordenes_paciente    ON ordenes_medicas (id_paciente);
CREATE INDEX idx_resultados_medico   ON resultados_estudios (id_medico_informa);
