# =====================================================================
#  reporte.ps1 - Ejecuta la demostracion completa en los 3 servidores y
#  muestra los resultados en una pagina web (se abre en el navegador).
#  Son las mismas pruebas de demo.ps1, pero con tablas y colores.
#
#       powershell -ExecutionPolicy Bypass -File .\reporte.ps1
#
#  Requisito: haber ejecutado antes instalar.ps1 (con datos limpios).
# =====================================================================
param([switch]$NoAbrir)   # -NoAbrir: genera la pagina sin abrir el navegador

$ErrorActionPreference = "Continue"
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$OutputEncoding = New-Object Text.UTF8Encoding $false   # UTF-8 sin BOM al enviar SQL

$archivo = Join-Path $PSScriptRoot "reporte_demo.html"
$sb = New-Object System.Text.StringBuilder
function Add($s) { [void]$sb.AppendLine($s) }
function Esc($s) { [System.Net.WebUtility]::HtmlEncode("$s") }

# --- Verificacion previa ------------------------------------------------
docker exec pg_clinica pg_isready -U postgres *> $null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Los servidores no estan encendidos. Ejecute primero instalar.ps1" -ForegroundColor Red; exit 1
}
$pendiente = docker exec pg_clinica psql -U postgres -d clinica_db -tAc "SELECT count(*) FROM ordenes_medicas WHERE id_orden = 13 AND estado = 'PENDIENTE'"
if ("$pendiente".Trim() -ne "1") {
    Write-Host "La demostracion ya se ejecuto antes. Para repetirla con datos limpios:" -ForegroundColor Yellow
    Write-Host "  powershell -ExecutionPolicy Bypass -File .\instalar.ps1 -Reiniciar"; exit 1
}

# --- Bloques de la pagina -------------------------------------------------
function Paso($n, $titulo, $explicacion) {
    Write-Host "Paso $n : $titulo"
    Add "<section class='paso'><div class='num'>$n</div><div class='cuerpo'><h2>$(Esc $titulo)</h2><p class='que'>$(Esc $explicacion)</p>"
}
function FinPaso($esperado) { Add "<div class='esperado'><b>Resultado esperado:</b> $(Esc $esperado)</div></div></section>" }

function Mensajes($lineas) {
    foreach ($l in $lineas) {
        if ($l -match "tds_fdw:|Table definition mismatch|Column will be ignored" -or "$l".Trim() -eq "") { continue }
        if ($l -match "^NOTICE:\s*(.*)") { Add "<div class='msg ok'>&#10004; $(Esc $Matches[1])</div>" }
        elseif ($l -match "^(ERROR|FATAL|psql: error|Msg \d+)|permission was denied|Error esperado") { Add "<div class='msg err'>&#10006; $(Esc $l)</div>" }
        elseif ($l -match "^(LINE \d+:|\s+\^)") { continue }
        else { Add "<div class='msg'>$(Esc $l)</div>" }
    }
}

# Consulta en PostgreSQL: psql devuelve la tabla en HTML (-H)
function PG($titulo, $sql, $usuario = $null, $clave = $null) {
    $quien = if ($usuario) { $usuario } else { "postgres" }
    if ($usuario) {
        $salida = $sql | docker exec -i -e PGPASSWORD=$clave pg_clinica psql -h localhost -U $usuario -d clinica_db -X -q -H -P footer=off 2>&1
    } else {
        $salida = $sql | docker exec -i pg_clinica psql -U postgres -d clinica_db -X -q -H -P footer=off 2>&1
    }
    $tablas = New-Object System.Text.StringBuilder; $msgs = @()
    foreach ($o in $salida) {
        if ($o -is [System.Management.Automation.ErrorRecord]) { $msgs += "$o" } else { [void]$tablas.AppendLine("$o") }
    }
    Add "<div class='bloque pg'><div class='cab'><span class='motor'>PostgreSQL</span><span class='usr'>usuario: $quien</span><span class='tit'>$(Esc $titulo)</span></div>"
    Add "<pre class='sql'>$(Esc $sql.Trim())</pre>"
    Mensajes $msgs
    Add ($tablas.ToString() -replace "<table border=`"1`">", "<table>")
    Add "</div>"
}

# Consulta en SQL Server: se convierte la salida de sqlcmd en tabla
function MSSQL($titulo, $sql, $usuario = "sa", $clave = "Admin_Sql2026!") {
    $lineas = docker exec mssql_integra /opt/mssql-tools18/bin/sqlcmd -C -S localhost -U $usuario -P $clave -d IntegracionMedica -W -s "|" -Q "SET NOCOUNT ON; $sql" 2>&1 | ForEach-Object { "$_" }
    Add "<div class='bloque ms'><div class='cab'><span class='motor'>SQL Server</span><span class='usr'>usuario: $usuario</span><span class='tit'>$(Esc $titulo)</span></div>"
    Add "<pre class='sql'>$(Esc $sql.Trim())</pre>"
    $errores = @($lineas | Where-Object { $_ -match "^Msg \d+|permission was denied" })
    if ($errores.Count) { Mensajes $errores }
    else {
        $datos = @($lineas | Where-Object { $_.Trim() -ne "" -and $_ -notmatch "^-+(\|-+)*$" })
        if ($datos.Count -gt 0) {
            Add "<table><tr>$(($datos[0] -split '\|' | ForEach-Object { "<th>$(Esc $_)</th>" }) -join '')</tr>"
            foreach ($f in $datos | Select-Object -Skip 1) { Add "<tr>$(($f -split '\|' | ForEach-Object { "<td>$(Esc $_)</td>" }) -join '')</tr>" }
            Add "</table>"
        }
    }
    Add "</div>"
}

# --- Encabezado ---------------------------------------------------------
Add @"
<!doctype html><html lang='es'><head><meta charset='utf-8'><title>Demostración - Estudios Médicos Distribuidos</title>
<style>
:root{--pg:#336791;--ms:#cc2927;--mg:#13834a;--txt:#1f2937;--suave:#6b7280}
*{box-sizing:border-box} body{margin:0;font-family:'Segoe UI',Arial,sans-serif;background:#f3f4f6;color:var(--txt)}
header{background:linear-gradient(135deg,#1f3a5f,#336791);color:#fff;padding:28px 40px}
header h1{margin:0 0 6px;font-size:26px} header p{margin:0;opacity:.85}
.leyenda{display:flex;gap:10px;margin-top:14px;flex-wrap:wrap}
.leyenda span{padding:4px 12px;border-radius:999px;font-size:13px;font-weight:600;background:#fff}
main{max-width:1100px;margin:28px auto;padding:0 16px}
.paso{display:flex;gap:18px;background:#fff;border-radius:14px;box-shadow:0 2px 10px rgba(0,0,0,.06);padding:22px 24px;margin-bottom:22px}
.num{flex:0 0 44px;height:44px;border-radius:50%;background:#1f3a5f;color:#fff;font-weight:700;font-size:20px;display:flex;align-items:center;justify-content:center}
.cuerpo{flex:1;min-width:0} h2{margin:4px 0 6px;font-size:20px} .que{margin:0 0 14px;color:var(--suave)}
.bloque{border:1px solid #e5e7eb;border-left:6px solid;border-radius:10px;margin:12px 0;padding:12px 14px;overflow-x:auto}
.bloque.pg{border-left-color:var(--pg)} .bloque.ms{border-left-color:var(--ms)} .bloque.mg{border-left-color:var(--mg)} .bloque.dk{border-left-color:#6b7280}
.cab{display:flex;align-items:center;gap:10px;flex-wrap:wrap;margin-bottom:8px}
.motor{color:#fff;font-size:12px;font-weight:700;padding:3px 10px;border-radius:6px}
.pg .motor{background:var(--pg)} .ms .motor{background:var(--ms)} .mg .motor{background:var(--mg)} .dk .motor{background:#6b7280}
.usr{font-size:12px;color:var(--suave);background:#f3f4f6;padding:2px 8px;border-radius:6px} .tit{font-weight:600}
pre.sql{background:#0f172a;color:#7dd3fc;font:13px/1.45 Consolas,monospace;padding:10px 12px;border-radius:8px;margin:6px 0 10px;white-space:pre-wrap}
table{border-collapse:collapse;font-size:14px;margin:6px 0}
th{background:#eef2f7;text-align:left;padding:7px 12px;border-bottom:2px solid #d1d5db;white-space:nowrap}
td{padding:6px 12px;border-bottom:1px solid #eef0f3;white-space:nowrap} tr:hover td{background:#f9fafb}
.msg{padding:7px 12px;border-radius:8px;margin:5px 0;font-size:14px;background:#f3f4f6}
.msg.ok{background:#e8f7ee;color:#0e5530} .msg.err{background:#fdecec;color:#9b1c1c}
.esperado{margin-top:14px;padding:10px 14px;background:#fff8e6;border:1px solid #fde3a7;border-radius:8px;font-size:14px}
footer{text-align:center;color:var(--suave);font-size:13px;padding:10px 0 30px}
</style></head><body>
<header><h1>Sistema de Gestión de Estudios Médicos Distribuido</h1>
<p>Demostración ejecutada el $(Get-Date -Format 'dd/MM/yyyy HH:mm') · resultados reales de los tres servidores</p>
<div class='leyenda'><span style='color:#336791'>&#9632; PostgreSQL · transaccional</span><span style='color:#cc2927'>&#9632; SQL Server · integración</span><span style='color:#13834a'>&#9632; MongoDB · reportes</span></div></header><main>
"@

# --- 1 ------------------------------------------------------------------
Paso 1 "Los tres servidores" "PostgreSQL, SQL Server y MongoDB están encendidos, cada uno en su propio contenedor dentro de la misma red."
Add "<div class='bloque dk'><div class='cab'><span class='motor'>Docker</span><span class='tit'>docker ps</span></div><table><tr><th>Contenedor</th><th>Imagen</th><th>Estado</th></tr>"
docker ps --format "{{.Names}}|{{.Image}}|{{.Status}}" | ForEach-Object { $c = $_ -split '\|'; Add "<tr><td>$(Esc $c[0])</td><td>$(Esc $c[1])</td><td>$(Esc $c[2])</td></tr>" }
Add "</table></div>"
FinPaso "aparecen pg_clinica, mssql_integra y mongo_reportes con estado 'Up'."

# --- 2 ------------------------------------------------------------------
Paso 2 "Segmentación horizontal" "La tabla pacientes está dividida en 3 fragmentos, uno por sucursal. Al buscar por sucursal, PostgreSQL lee solo el fragmento necesario."
PG "Pacientes por fragmento" "SELECT tableoid::regclass AS fragmento, count(*) AS pacientes FROM pacientes GROUP BY 1 ORDER BY 1;"
PG "Plan de ejecución al buscar en Cartago (sucursal 3)" "EXPLAIN (COSTS OFF) SELECT * FROM pacientes WHERE id_sucursal = 3;"
FinPaso "4 pacientes por fragmento; el plan solo lee pacientes_cartago."

# --- 3 ------------------------------------------------------------------
Paso 3 "Operación 1: PostgreSQL lee de SQL Server" "Los pacientes (PostgreSQL) se unen con su estado de facturación y aseguradora, que viven en SQL Server."
PG "Paciente + estado de facturación remoto" @"
SET ROLE usr_fdw_pg_mssql;
SELECT p.nombre || ' ' || p.apellidos AS paciente,
       pi.estado_facturacion          AS estado_en_sql_server,
       a.nombre                       AS aseguradora
FROM pacientes p
JOIN mssql.paciente_integracion pi ON pi.id_paciente = p.id_paciente
JOIN mssql.aseguradoras a          ON a.id_aseguradora = pi.id_aseguradora
ORDER BY p.id_paciente;
"@
FinPaso "12 pacientes; las dos últimas columnas se leen de SQL Server en ese momento."

# --- 4 ------------------------------------------------------------------
Paso 4 "Operación 4: exportación a MongoDB" "PostgreSQL envía los estudios y los indicadores mensuales a MongoDB para los reportes."
PG "Exportar estudios e indicadores" "SELECT mongo.fn_exportar_resultados() AS estudios_enviados, mongo.fn_exportar_indicadores_mensuales() AS indicadores_enviados;"
PG "Indicadores guardados en MongoDB (leídos con mongo_fdw)" "SET ROLE usr_fdw_pg_mongo;`nSELECT mes, sucursal, tipo, cantidad_estudios, ingreso_total FROM mongo.indicadores_mensuales ORDER BY mes, sucursal, tipo;"
FinPaso "12 estudios y 10 indicadores enviados a MongoDB."

# --- 5 ------------------------------------------------------------------
Paso 5 "Operación 2: una operación que toca los tres motores" "Se registra el resultado de un estudio. Se confirma primero en PostgreSQL; después se actualiza el resumen en MongoDB y se crea la factura en SQL Server."
PG "ANTES: resumen del paciente 1 en MongoDB" "SET ROLE usr_fdw_pg_mongo;`nSELECT paciente, total_estudios, ultimo_estudio FROM mongo.resumen_paciente WHERE id_paciente = 1;"
PG "Registrar el resultado de la glicemia" "CALL sp_registrar_resultado(13, 1, 1, '{""glicemia"": 92, ""unidad"": ""mg/dL""}', 'Glicemia normal');"
PG "DESPUÉS: resumen del paciente 1 en MongoDB" "SET ROLE usr_fdw_pg_mongo;`nSELECT paciente, total_estudios, ultimo_estudio FROM mongo.resumen_paciente WHERE id_paciente = 1;"
MSSQL "Facturas del paciente 1" "SELECT id_factura, id_estudio, codigo_estudio, costo, estado FROM dbo.facturas_externas WHERE id_paciente = 1;"
FinPaso "tres confirmaciones (PostgreSQL, MongoDB y SQL Server); total_estudios pasa de 1 a 2 y aparece una factura PENDIENTE."

# --- 6 ------------------------------------------------------------------
Paso 6 "PostgreSQL escribe en SQL Server" "Se registra un paciente nuevo en Alajuela; su información para las aseguradoras se envía a SQL Server."
PG "Registrar paciente" "CALL sp_registrar_paciente(2, '2-2222-0013', 'Sebastián', 'Rojas Umaña', '2000-02-14', 'M', '8888-0013', 'sebastian.rojas@correo.com', 2);"
PG "Fragmento donde quedó en PostgreSQL" "SELECT tableoid::regclass AS fragmento, nombre, apellidos FROM pacientes WHERE cedula = '2-2222-0013';"
MSSQL "Fragmento vertical en SQL Server (solo 4 columnas)" "SELECT * FROM dbo.paciente_integracion WHERE id_paciente = 13;"
FinPaso "el paciente está en pacientes_alajuela y en SQL Server con el código AVP-000013."

# --- 7 ------------------------------------------------------------------
Paso 7 "Operación 3: vista para la aplicación web" "Se inicia sesión como usr_api_web, con su contraseña, y se consulta la vista que mezcla datos de PostgreSQL y SQL Server."
PG "Vista api_web.v_pacientes_facturacion" "SELECT paciente, sucursal, aseguradora, estado_facturacion, total_facturado, total_pendiente FROM api_web.v_pacientes_facturacion ORDER BY id_paciente;" "usr_api_web" "Api_Web2026"
FinPaso "13 pacientes con datos de facturación, aunque usr_api_web no tiene permiso sobre ninguna tabla."

# --- 8 ------------------------------------------------------------------
Paso 8 "Operación 5: reporte en MongoDB" "MongoDB agrupa los estudios por médico y tipo de estudio (aggregate con `$group)."
$json = docker exec mongo_reportes mongosh --quiet -u admin -p Admin_Mongo2026 /scripts/06_reporte_json.js | Out-String
$filas = $json | ConvertFrom-Json
Add "<div class='bloque mg'><div class='cab'><span class='motor'>MongoDB</span><span class='usr'>usuario: admin</span><span class='tit'>Estudios e ingresos por médico y tipo</span></div>"
Add "<pre class='sql'>db.resultados_estudios.aggregate([`n  { `$group: { _id: { medico: '`$medico', tipo: '`$tipo' },`n              cantidad: { `$sum: 1 }, ingresos: { `$sum: '`$costo' } } },`n  { `$sort: { medico: 1, tipo: 1 } }`n])</pre>"
Add "<table><tr><th>Médico</th><th>Tipo de estudio</th><th>Cantidad</th><th>Ingresos (₡)</th></tr>"
foreach ($f in $filas) { Add "<tr><td>$(Esc $f.medico)</td><td>$(Esc $f.tipo_de_estudio)</td><td style='text-align:right'>$($f.cantidad)</td><td style='text-align:right'>$('{0:N0}' -f $f.ingresos)</td></tr>" }
Add "</table></div>"
FinPaso "una fila por médico y tipo de estudio, con la cantidad y los ingresos."

# --- 9 ------------------------------------------------------------------
Paso 9 "Seguridad: cada usuario solo puede lo que le corresponde" "Se prueban accesos que DEBEN ser rechazados. Los mensajes en rojo demuestran que la seguridad funciona."
PG "usr_api_mobile: su vista sí; tablas, vistas web y escritura no" @"
SELECT estudio, fecha, diagnostico FROM api_movil.v_mis_resultados WHERE id_paciente = 1;
SELECT * FROM pacientes LIMIT 1;
SELECT * FROM api_web.v_pacientes_facturacion LIMIT 1;
INSERT INTO citas (id_sucursal, id_paciente, id_medico, fecha_hora) VALUES (1, 1, 1, now());
"@ "usr_api_mobile" "Api_Mobile2026"
$rechazo = docker exec -e PGPASSWORD=x pg_clinica psql -h localhost -U usr_fdw_pg_mssql -d clinica_db -c "SELECT 1" 2>&1 | ForEach-Object { "$_" }
Add "<div class='bloque pg'><div class='cab'><span class='motor'>PostgreSQL</span><span class='usr'>usuario: usr_fdw_pg_mssql</span><span class='tit'>El usuario interno intenta conectarse desde afuera</span></div>"
Mensajes $rechazo; Add "</div>"
MSSQL "usr_fdw_pg_mssql intenta borrar una factura" "DELETE FROM dbo.facturas_externas WHERE id_factura = 1;" "usr_fdw_pg_mssql" "Fdw_Mssql2026!"
$perm = docker exec mongo_reportes mongosh --quiet -u usr_api_mobile -p Api_Mobile2026 --authenticationDatabase reportes_medicos /scripts/04_prueba_permisos.js 2>&1 | ForEach-Object { "$_" }
Add "<div class='bloque mg'><div class='cab'><span class='motor'>MongoDB</span><span class='usr'>usuario: usr_api_mobile</span><span class='tit'>Lectura permitida y accesos rechazados</span></div>"
Add "<div class='msg ok'>&#10004; Puede leer resumen_paciente (permitido)</div>"
$rechazos = @($perm | Where-Object { $_ -match "Unauthorized" })
if ($rechazos.Count -ge 1) { Add "<div class='msg err'>&#10006; Leer la coleccion resultados_estudios: rechazado (Unauthorized)</div>" }
if ($rechazos.Count -ge 2) { Add "<div class='msg err'>&#10006; Insertar en resumen_paciente: rechazado (Unauthorized)</div>" }
Add "</div>"
FinPaso "permission denied, solo lectura, pg_hba.conf rechaza, error 229 y Unauthorized: todos los accesos indebidos fueron bloqueados."

Add "</main><footer>Proyecto 2 · Bases de Datos II · Instituto Tecnológico de Costa Rica</footer></body></html>"
[IO.File]::WriteAllText($archivo, $sb.ToString(), (New-Object Text.UTF8Encoding $false))
Write-Host "`nReporte generado: $archivo" -ForegroundColor Green
if (-not $NoAbrir) { Start-Process $archivo }
