/* =====================================================================
   POSTGRESQL - Script 02: datos de prueba
   Pacientes 1-4 San Jose, 5-8 Alajuela, 9-12 Cartago.
   Ordenes 1-12 ya tienen resultado; 13-15 quedan PENDIENTES para
   demostrar la insercion distribuida (PostgreSQL -> MongoDB).
   ===================================================================== */

INSERT INTO sucursales VALUES
 (1, 'SJ', 'Clinica San Jose', 'San Jose'),
 (2, 'AL', 'Clinica Alajuela', 'Alajuela'),
 (3, 'CA', 'Clinica Cartago',  'Cartago');

INSERT INTO medicos (id_medico, nombre, especialidad, codigo_colegio, id_sucursal) VALUES
 (1, 'Dra. Ana Rojas Solís',      'Patología Clínica', 'MED-1101', 1),
 (2, 'Dr. Carlos Méndez Vargas',  'Radiología',        'MED-1102', 1),
 (3, 'Dra. Laura Jiménez Mora',   'Radiología',        'MED-2201', 2),
 (4, 'Dr. Andrés Castro Quesada', 'Medicina Interna',  'MED-2202', 2),
 (5, 'Dra. Sofía Araya Brenes',   'Ginecología',       'MED-3301', 3),
 (6, 'Dr. Diego Vargas Pérez',    'Patología Clínica', 'MED-3302', 3);
SELECT setval('medicos_id_medico_seq', 6);

INSERT INTO tipos_estudio VALUES
 ('LAB-HEM', 'Hemograma completo',       'Laboratorio', 12000),
 ('LAB-GLU', 'Glicemia en ayunas',       'Laboratorio',  5000),
 ('LAB-LIP', 'Perfil lipídico',          'Laboratorio', 15000),
 ('RX-TOR',  'Radiografía de tórax',     'Radiografia', 25000),
 ('US-ABD',  'Ultrasonido abdominal',    'Ultrasonido', 45000),
 ('US-OBS',  'Ultrasonido obstétrico',   'Ultrasonido', 50000);

INSERT INTO usuarios_admin (nombre, usuario, puesto, id_sucursal) VALUES
 ('María Fernández', 'mfernandez', 'RECEPCION',     1),
 ('Jorge Salas',     'jsalas',     'FACTURACION',   2),
 ('Paola Chaves',    'pchaves',    'ADMINISTRADOR', 3);

-- Se insertan en la tabla PADRE; PostgreSQL decide la particion.
INSERT INTO pacientes (id_paciente, id_sucursal, cedula, nombre, apellidos, fecha_nacimiento, sexo, telefono, correo) VALUES
 ( 1, 1, '1-1111-0001', 'José',      'Pérez Rodríguez',  '1985-03-12', 'M', '8888-0001', 'jose.perez@correo.com'),
 ( 2, 1, '1-1111-0002', 'María',     'Gómez Solano',     '1990-07-25', 'F', '8888-0002', 'maria.gomez@correo.com'),
 ( 3, 1, '1-1111-0003', 'Luis',      'Herrera Campos',   '1978-11-02', 'M', '8888-0003', 'luis.herrera@correo.com'),
 ( 4, 1, '1-1111-0004', 'Carmen',    'Ureña Alfaro',     '1965-01-30', 'F', '8888-0004', 'carmen.urena@correo.com'),
 ( 5, 2, '2-2222-0005', 'Pedro',     'Alvarado Ruiz',    '1992-05-14', 'M', '8888-0005', 'pedro.alvarado@correo.com'),
 ( 6, 2, '2-2222-0006', 'Daniela',   'Montero Sibaja',   '1988-09-09', 'F', '8888-0006', 'daniela.montero@correo.com'),
 ( 7, 2, '2-2222-0007', 'Ricardo',   'Navarro León',     '1970-12-19', 'M', '8888-0007', 'ricardo.navarro@correo.com'),
 ( 8, 2, '2-2222-0008', 'Valeria',   'Quirós Mena',      '2001-04-03', 'F', '8888-0008', 'valeria.quiros@correo.com'),
 ( 9, 3, '3-3333-0009', 'Fernanda',  'Brenes Coto',      '1995-06-21', 'F', '8888-0009', 'fernanda.brenes@correo.com'),
 (10, 3, '3-3333-0010', 'Esteban',   'Calderón Ramírez', '1983-08-17', 'M', '8888-0010', 'esteban.calderon@correo.com'),
 (11, 3, '3-3333-0011', 'Gabriela',  'Soto Fallas',      '1975-02-11', 'F', '8888-0011', 'gabriela.soto@correo.com'),
 (12, 3, '3-3333-0012', 'Andrea',    'Monge Pacheco',    '1998-10-28', 'F', '8888-0012', 'andrea.monge@correo.com');
SELECT setval('pacientes_id_paciente_seq', 12);

INSERT INTO citas (id_sucursal, id_paciente, id_medico, fecha_hora, motivo, estado) VALUES
 (1,  1, 1, '2026-09-01 08:00', 'Chequeo general',        'ATENDIDA'),
 (1,  2, 2, '2026-09-03 09:30', 'Tos persistente',        'ATENDIDA'),
 (1,  3, 2, '2026-09-05 10:00', 'Dolor abdominal',        'ATENDIDA'),
 (1,  4, 1, '2026-09-08 07:30', 'Control de colesterol',  'ATENDIDA'),
 (2,  5, 4, '2026-09-10 08:15', 'Control de glicemia',    'ATENDIDA'),
 (2,  6, 3, '2026-09-12 11:00', 'Golpe en el pecho',      'ATENDIDA'),
 (2,  7, 3, '2026-09-15 13:00', 'Dolor abdominal',        'ATENDIDA'),
 (2,  8, 4, '2026-09-18 08:45', 'Cansancio',              'ATENDIDA'),
 (3,  9, 5, '2026-09-20 09:00', 'Control prenatal',       'ATENDIDA'),
 (3, 10, 6, '2026-10-01 07:00', 'Control de colesterol',  'ATENDIDA'),
 (3, 11, 6, '2026-10-04 10:30', 'Dificultad respiratoria','ATENDIDA'),
 (3, 12, 5, '2026-10-06 14:00', 'Control prenatal',       'ATENDIDA'),
 (1,  1, 1, '2026-10-28 08:00', 'Control anual',          'PROGRAMADA'),
 (2,  5, 4, '2026-10-29 09:00', 'Seguimiento glicemia',   'PROGRAMADA'),
 (3,  9, 5, '2026-10-30 10:00', 'Control prenatal',       'PROGRAMADA');

INSERT INTO ordenes_medicas (id_orden, id_sucursal, id_paciente, id_medico, codigo_estudio, fecha_orden, estado) VALUES
 ( 1, 1,  1, 1, 'LAB-HEM', '2026-09-01', 'COMPLETADA'),
 ( 2, 1,  2, 2, 'RX-TOR',  '2026-09-03', 'COMPLETADA'),
 ( 3, 1,  3, 2, 'US-ABD',  '2026-09-05', 'COMPLETADA'),
 ( 4, 1,  4, 1, 'LAB-LIP', '2026-09-08', 'COMPLETADA'),
 ( 5, 2,  5, 4, 'LAB-GLU', '2026-09-10', 'COMPLETADA'),
 ( 6, 2,  6, 3, 'RX-TOR',  '2026-09-12', 'COMPLETADA'),
 ( 7, 2,  7, 3, 'US-ABD',  '2026-09-15', 'COMPLETADA'),
 ( 8, 2,  8, 4, 'LAB-HEM', '2026-09-18', 'COMPLETADA'),
 ( 9, 3,  9, 5, 'US-OBS',  '2026-09-20', 'COMPLETADA'),
 (10, 3, 10, 6, 'LAB-LIP', '2026-10-01', 'COMPLETADA'),
 (11, 3, 11, 6, 'RX-TOR',  '2026-10-04', 'COMPLETADA'),
 (12, 3, 12, 5, 'US-OBS',  '2026-10-06', 'COMPLETADA'),
 (13, 1,  1, 1, 'LAB-GLU', '2026-10-20', 'PENDIENTE'),
 (14, 2,  5, 3, 'US-ABD',  '2026-10-21', 'PENDIENTE'),
 (15, 3,  9, 5, 'US-OBS',  '2026-10-22', 'PENDIENTE');
SELECT setval('ordenes_medicas_id_orden_seq', 15);

INSERT INTO resultados_estudios (id_sucursal, id_orden, id_medico_informa, fecha_resultado, resultado, diagnostico) VALUES
 (1,  1, 1, '2026-09-02 10:00', '{"hemoglobina": 14.2, "leucocitos": 7200, "plaquetas": 250000, "unidad_hb": "g/dL"}', 'Hemograma dentro de rangos normales'),
 (1,  2, 2, '2026-09-03 12:00', '{"hallazgo": "Infiltrado leve en base derecha", "proyeccion": "PA y lateral"}',      'Posible bronquitis'),
 (1,  3, 2, '2026-09-05 12:30', '{"hallazgo": "Vesícula con litiasis", "organo": "vesícula biliar"}',                 'Colelitiasis'),
 (1,  4, 1, '2026-09-08 11:00', '{"colesterol_total": 245, "hdl": 38, "ldl": 170, "trigliceridos": 210}',             'Dislipidemia'),
 (2,  5, 4, '2026-09-10 10:00', '{"glicemia": 128, "unidad": "mg/dL"}',                                                'Glicemia alterada en ayunas'),
 (2,  6, 3, '2026-09-12 13:00', '{"hallazgo": "Sin fracturas costales", "proyeccion": "PA"}',                         'Estudio normal'),
 (2,  7, 3, '2026-09-15 15:00', '{"hallazgo": "Hígado graso grado I", "organo": "hígado"}',                           'Esteatosis hepática leve'),
 (2,  8, 4, '2026-09-18 10:30', '{"hemoglobina": 10.8, "leucocitos": 6100, "plaquetas": 210000, "unidad_hb": "g/dL"}', 'Anemia leve'),
 (3,  9, 5, '2026-09-20 11:00', '{"hallazgo": "Feto único vivo, 20 semanas", "frecuencia_cardiaca_fetal": 145}',      'Embarazo normoevolutivo'),
 (3, 10, 6, '2026-10-01 09:00', '{"colesterol_total": 190, "hdl": 55, "ldl": 110, "trigliceridos": 140}',             'Perfil lipídico normal'),
 (3, 11, 6, '2026-10-04 12:00', '{"hallazgo": "Campos pulmonares limpios", "proyeccion": "PA"}',                     'Estudio normal'),
 (3, 12, 5, '2026-10-06 16:00', '{"hallazgo": "Feto único vivo, 12 semanas", "frecuencia_cardiaca_fetal": 160}',     'Embarazo normoevolutivo');

-- Comprobacion: cuantas filas quedaron en cada fragmento horizontal
SELECT tableoid::regclass AS fragmento, count(*) AS filas
FROM pacientes GROUP BY 1 ORDER BY 1;
