# Guion sugerido para el video (5 a 8 minutos)

Partes repartidas entre los 3 integrantes (1: Danny, 2: Dylan, 3: Francisco; pueden cambiar el orden). **Cada integrante narra su parte.**

**Antes de grabar:** instalar desde cero para que los datos estén limpios:

```powershell
powershell -ExecutionPolicy Bypass -File .\instalar.ps1 -Reiniciar
```

| Tiempo | Integrante | Qué mostrar en pantalla | Qué decir (idea) |
|---|---|---|---|
| 0:00 – 1:00 | 1 | `docs/diagramas/01_arquitectura.png` y `docker ps` con los 3 contenedores | Presentar el proyecto y el rol de cada motor: PostgreSQL es transaccional, SQL Server es de integración y MongoDB es de reportes. Los 3 están en una red Docker y PostgreSQL es el centro: lee y ejecuta procedimientos en SQL Server con tds_fdw, y escribe en MongoDB con mongo_fdw |
| 1:00 – 2:00 | 1 | `docs/diagramas/02_modelo_segmentacion.png` + bloque 0 de `08_consultas_prueba.sql` (conteo por fragmento + `EXPLAIN`) | Segmentación horizontal con pacientes_san_jose, _alajuela y _cartago; el EXPLAIN muestra que solo se lee Cartago. Segmentación vertical: paciente_integracion solo guarda 4 columnas |
| 2:00 – 3:00 | 2 | `pg_hba.conf`, `04_fdw_sqlserver.sql`, bloque "Canales FDW" + **Operación 1** | Explicar CREATE SERVER, USER MAPPING y FOREIGN TABLE. Ejecutar el JOIN entre el paciente y su estado de facturación |
| 3:00 – 4:30 | 3 | `docs/diagramas/03_flujo_transaccion.png` + **Operaciones 4 y 2** + operación extra | Exportar a MongoDB. Registrar el resultado de la orden 13: el resumen del paciente pasa de 1 a 2 estudios en MongoDB y aparece la factura en SQL Server, así que una sola operación toca los 3 motores. El COMMIT ocurre antes de propagar. Registrar el paciente 13 y mostrar que llega a SQL Server |
| 4:30 – 5:15 | 2 | SQL Server: ejecutar `05_consultas_prueba.sql` | Mostrar el procedimiento de resumen, los datos que llegaron desde PostgreSQL (paciente 13 y factura del estudio 13) y que usr_fdw_pg_mssql no puede borrar (error 229): solo escribe por medio de procedimientos |
| 5:15 – 6:30 | 3 | MongoDB: `03_consultas_analiticas.js` | **Operación 5**: agregación por médico y tipo de estudio, ranking de médicos y rendimiento por sucursal |
| 6:30 – 7:30 | 2 | **Operación 3** + bloque de seguridad de `08_consultas_prueba.sql` + `04_prueba_permisos.js` | Vista web que mezcla datos locales y de SQL Server. usr_api_mobile solo ve sus vistas y recibe "permiso denegado" en lo demás. Mostrar la tabla de roles (pg_roles) |
| 7:30 – 8:00 | 1 | README / documento Word | Cierre: resumen de lo logrado |

**Lo más fácil para grabar:** ejecutar `powershell -ExecutionPolicy Bypass -File .\reporte.ps1` (se ve unos segundos en la terminal que corre de verdad) y recorrer la página web que se abre, tarjeta por tarjeta. También se puede mostrar en pgAdmin con `postgres/scripts/09_pruebas_pgadmin.sql`, ejecutando bloque por bloque.

Comandos detallados (también están en el README, sección 10):

```powershell
docker exec -it pg_clinica psql -U postgres -d clinica_db -f /scripts/08_consultas_prueba.sql
docker exec -it mssql_integra /opt/mssql-tools18/bin/sqlcmd -C -S localhost -U sa -P "Admin_Sql2026!" -i /scripts/05_consultas_prueba.sql
docker exec -it mongo_reportes mongosh -u admin -p Admin_Mongo2026 /scripts/03_consultas_analiticas.js
docker exec -it mongo_reportes mongosh -u usr_api_mobile -p Api_Mobile2026 --authenticationDatabase reportes_medicos /scripts/04_prueba_permisos.js
```

**Consejo:** el script de PostgreSQL es largo. Para el video se puede abrir en pgAdmin o DBeaver (`localhost:5433`) y ejecutar bloque por bloque mientras se explica.
