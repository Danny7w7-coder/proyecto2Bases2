# =====================================================================
#  demo.ps1 - Demostracion guiada, paso a paso, de todo el proyecto.
#  Cada paso explica que se va a probar, lo ejecuta y dice que se
#  deberia ver. Presione Enter para avanzar.
#
#       powershell -ExecutionPolicy Bypass -File .\demo.ps1
#       powershell -ExecutionPolicy Bypass -File .\demo.ps1 -SinPausa
#
#  Requisito: haber ejecutado antes instalar.ps1
# =====================================================================
param([switch]$SinPausa)

$ErrorActionPreference = "Continue"
[Console]::OutputEncoding = [Text.Encoding]::UTF8   # para ver bien los acentos
$OutputEncoding = New-Object Text.UTF8Encoding $false   # UTF-8 sin marca BOM al enviar SQL

$total = 9
function Paso($n, $titulo, $explicacion) {
    Write-Host ""
    Write-Host ("=" * 75) -ForegroundColor DarkCyan
    Write-Host " PASO $n de $total : $titulo" -ForegroundColor Cyan
    Write-Host ("=" * 75) -ForegroundColor DarkCyan
    Write-Host " Que se prueba: $explicacion" -ForegroundColor White
    Write-Host ""
}
function Esperado($texto) {
    Write-Host ""
    Write-Host " Resultado esperado: $texto" -ForegroundColor Green
    if (-not $SinPausa) { Read-Host " Presione Enter para continuar" | Out-Null }
}
function Subtitulo($texto) { Write-Host " -- $texto" -ForegroundColor Yellow }

# Muestra la salida de un comando: quita mensajes de relleno y colorea
function Mostrar {
    process {
        $l = "$_"
        if ($l -match "tds_fdw:|Table definition mismatch|Column will") { return }
        if ($l -match "^(ERROR|FATAL|psql: error|Msg \d+)|permission was denied|Error esperado") { Write-Host "   $l" -ForegroundColor Red }
        elseif ($l -match "^NOTICE") { Write-Host "   $l" -ForegroundColor Green }
        else { Write-Host "   $l" }
    }
}

# Ejecuta SQL en PostgreSQL (como administrador o como otro usuario con contrasena)
function PG($sql, $usuario = $null, $clave = $null) {
    if ($usuario) {
        $sql | docker exec -i -e PGPASSWORD=$clave pg_clinica psql -h localhost -U $usuario -d clinica_db -X -q -P pager=off -P footer=off 2>&1 | Mostrar
    } else {
        $sql | docker exec -i pg_clinica psql -U postgres -d clinica_db -X -q -P pager=off -P footer=off 2>&1 | Mostrar
    }
}
function MSSQL($sql, $usuario = "sa", $clave = "Admin_Sql2026!") {
    docker exec mssql_integra /opt/mssql-tools18/bin/sqlcmd -C -S localhost -U $usuario -P $clave -d IntegracionMedica -W -s " | " -Q "SET NOCOUNT ON; $sql" 2>&1 | Mostrar
}

# --- Verificacion previa ------------------------------------------------
docker exec pg_clinica pg_isready -U postgres *> $null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Los servidores no estan encendidos. Ejecute primero:" -ForegroundColor Red
    Write-Host "  powershell -ExecutionPolicy Bypass -File .\instalar.ps1"
    exit 1
}
$pendiente = docker exec pg_clinica psql -U postgres -d clinica_db -tAc "SELECT count(*) FROM ordenes_medicas WHERE id_orden = 13 AND estado = 'PENDIENTE'"
if ("$pendiente".Trim() -ne "1") {
    Write-Host "La demostracion ya se ejecuto antes (la orden 13 ya tiene resultado)." -ForegroundColor Yellow
    Write-Host "Para dejar los datos limpios y repetirla ejecute:"
    Write-Host "  powershell -ExecutionPolicy Bypass -File .\instalar.ps1 -Reiniciar"
    exit 1
}

# --- 1 ------------------------------------------------------------------
Paso 1 "Los tres servidores" "PostgreSQL, SQL Server y MongoDB estan encendidos, cada uno en su contenedor."
docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}" | Mostrar
Esperado "aparecen pg_clinica, mssql_integra y mongo_reportes con estado 'Up'."

# --- 2 ------------------------------------------------------------------
Paso 2 "Segmentacion horizontal (PostgreSQL)" "La tabla pacientes esta dividida en 3 fragmentos, uno por sucursal."
Subtitulo "Cuantos pacientes hay en cada fragmento:"
PG "SELECT tableoid::regclass AS fragmento, count(*) AS pacientes FROM pacientes GROUP BY 1 ORDER BY 1;"
Subtitulo "Al buscar pacientes de Cartago (sucursal 3), PostgreSQL solo lee ese fragmento:"
PG "EXPLAIN (COSTS OFF) SELECT * FROM pacientes WHERE id_sucursal = 3;"
Esperado "4 pacientes por fragmento; el plan dice 'Seq Scan on pacientes_cartago' (no lee los otros dos)."

# --- 3 ------------------------------------------------------------------
Paso 3 "Operacion 1: PostgreSQL lee de SQL Server" "Se unen los pacientes (PostgreSQL) con su estado de facturacion, que vive en SQL Server."
PG @"
SET ROLE usr_fdw_pg_mssql;
SELECT p.nombre || ' ' || p.apellidos AS paciente,
       pi.estado_facturacion          AS estado_en_sql_server,
       a.nombre                       AS aseguradora
FROM pacientes p
JOIN mssql.paciente_integracion pi ON pi.id_paciente = p.id_paciente
JOIN mssql.aseguradoras a          ON a.id_aseguradora = pi.id_aseguradora
ORDER BY p.id_paciente;
"@
Esperado "12 pacientes. Las columnas 'estado_en_sql_server' y 'aseguradora' vienen de SQL Server en ese momento."

# --- 4 ------------------------------------------------------------------
Paso 4 "Operacion 4: PostgreSQL envia datos a MongoDB" "Se exportan los estudios y los indicadores mensuales a MongoDB para los reportes."
PG "SELECT mongo.fn_exportar_resultados() AS estudios_enviados, mongo.fn_exportar_indicadores_mensuales() AS indicadores_enviados;"
Subtitulo "Indicadores que quedaron guardados en MongoDB:"
PG "SET ROLE usr_fdw_pg_mongo; SELECT mes, sucursal, tipo, cantidad_estudios FROM mongo.indicadores_mensuales ORDER BY mes, sucursal, tipo;"
Esperado "12 estudios y 10 indicadores enviados; la tabla se esta leyendo directamente de MongoDB."

# --- 5 ------------------------------------------------------------------
Paso 5 "Operacion 2: una operacion que toca los 3 motores" "Se registra el resultado de un estudio. Primero se confirma en PostgreSQL y despues se actualiza MongoDB y se crea la factura en SQL Server."
Subtitulo "ANTES - resumen del paciente 1 en MongoDB:"
PG "SET ROLE usr_fdw_pg_mongo; SELECT paciente, total_estudios, ultimo_estudio FROM mongo.resumen_paciente WHERE id_paciente = 1;"
Subtitulo "Registrando el resultado (glicemia del paciente 1)..."
PG "CALL sp_registrar_resultado(13, 1, 1, '{""glicemia"": 92, ""unidad"": ""mg/dL""}', 'Glicemia normal');"
Subtitulo "DESPUES - resumen del paciente 1 en MongoDB:"
PG "SET ROLE usr_fdw_pg_mongo; SELECT paciente, total_estudios, ultimo_estudio FROM mongo.resumen_paciente WHERE id_paciente = 1;"
Subtitulo "Facturas del paciente 1 en SQL Server:"
MSSQL "SELECT id_factura, id_estudio, codigo_estudio, costo, estado FROM dbo.facturas_externas WHERE id_paciente = 1;"
Esperado "3 mensajes verdes (PostgreSQL, MongoDB, SQL Server); total_estudios pasa de 1 a 2; aparece una factura nueva PENDIENTE."

# --- 6 ------------------------------------------------------------------
Paso 6 "PostgreSQL escribe en SQL Server" "Se registra un paciente nuevo en Alajuela; su informacion para aseguradoras se envia a SQL Server."
PG "CALL sp_registrar_paciente(2, '2-2222-0013', 'Sebastián', 'Rojas Umaña', '2000-02-14', 'M', '8888-0013', 'sebastian.rojas@correo.com', 2);"
Subtitulo "En PostgreSQL quedo en el fragmento de Alajuela:"
PG "SELECT tableoid::regclass AS fragmento, nombre, apellidos FROM pacientes WHERE cedula = '2-2222-0013';"
Subtitulo "En SQL Server existe su fragmento vertical (solo 4 columnas):"
MSSQL "SELECT * FROM dbo.paciente_integracion WHERE id_paciente = 13;"
Esperado "el paciente esta en pacientes_alajuela y en SQL Server con el codigo AVP-000013."

# --- 7 ------------------------------------------------------------------
Paso 7 "Operacion 3: la vista para la aplicacion web" "Se inicia sesion como usr_api_web (con su contrasena) y se consulta la vista que mezcla PostgreSQL y SQL Server."
PG "SELECT paciente, sucursal, estado_facturacion, total_pendiente FROM api_web.v_pacientes_facturacion ORDER BY id_paciente;" "usr_api_web" "Api_Web2026"
Esperado "13 pacientes con datos de facturacion, aunque usr_api_web no tiene permiso sobre ninguna tabla."

# --- 8 ------------------------------------------------------------------
Paso 8 "Operacion 5: reporte en MongoDB" "MongoDB agrupa los estudios por medico y tipo de estudio (aggregate + group)."
docker exec mongo_reportes mongosh --quiet -u admin -p Admin_Mongo2026 /scripts/05_demo_reporte.js 2>&1 | Mostrar
Esperado "una fila por medico y tipo de estudio, con la cantidad de estudios y los ingresos."

# --- 9 ------------------------------------------------------------------
Paso 9 "Seguridad: cada usuario solo puede lo que le corresponde" "Se prueban accesos que DEBEN ser rechazados. Los errores en rojo son la prueba de que la seguridad funciona."
Subtitulo "usr_api_mobile: puede ver su vista, pero no las tablas ni las vistas de la web, ni modificar:"
PG @"
SELECT estudio, fecha, diagnostico FROM api_movil.v_mis_resultados WHERE id_paciente = 1;
SELECT * FROM pacientes LIMIT 1;
SELECT * FROM api_web.v_pacientes_facturacion LIMIT 1;
INSERT INTO citas (id_sucursal, id_paciente, id_medico, fecha_hora) VALUES (1, 1, 1, now());
"@ "usr_api_mobile" "Api_Mobile2026"
Subtitulo "usr_fdw_pg_mssql (usuario interno) intenta conectarse desde afuera a PostgreSQL:"
docker exec -e PGPASSWORD=x pg_clinica psql -h localhost -U usr_fdw_pg_mssql -d clinica_db -c "SELECT 1" 2>&1 | Mostrar
Subtitulo "usr_fdw_pg_mssql intenta BORRAR una factura en SQL Server:"
MSSQL "DELETE FROM dbo.facturas_externas WHERE id_factura = 1;" "usr_fdw_pg_mssql" "Fdw_Mssql2026!"
Subtitulo "usr_api_mobile en MongoDB:"
docker exec mongo_reportes mongosh --quiet -u usr_api_mobile -p Api_Mobile2026 --authenticationDatabase reportes_medicos /scripts/04_prueba_permisos.js 2>&1 | Mostrar
Esperado "permission denied / read-only / pg_hba.conf rejects / error 229 / Unauthorized: todos los accesos indebidos fueron bloqueados."

Write-Host ""
Write-Host " Demostracion terminada. Para repetirla con datos limpios:" -ForegroundColor Cyan
Write-Host "   powershell -ExecutionPolicy Bypass -File .\instalar.ps1 -Reiniciar"
Write-Host "   powershell -ExecutionPolicy Bypass -File .\demo.ps1"
