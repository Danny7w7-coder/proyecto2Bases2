# =====================================================================
#  reporte.ps1 - Ejecuta la demostracion completa en los 3 servidores y
#  muestra los resultados en una pagina web (se abre en el navegador).
#  Cada prueba explica que demuestra, revisa sola si el resultado es el
#  esperado y marca con un sello "Correcto" o "Revisar".
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

# =====================================================================
#  Consultas: cada funcion devuelve un objeto con columnas, filas,
#  avisos (mensajes de exito) y errores, para poder dibujarlo y revisarlo
# =====================================================================
function Resultado { [pscustomobject]@{ Cols = @(); Rows = @(); Avisos = @(); Errores = @() } }

# Valor de una celda: V $r <fila> <columna>
function V($r, $i, $col) {
    $idx = [array]::IndexOf($r.Cols, $col)
    if ($idx -lt 0 -or $i -ge $r.Rows.Count) { return $null }
    $r.Rows[$i][$idx]
}

# PostgreSQL (una consulta por llamada; psql en formato simple separado por |)
function PGQ($sql, $usuario = $null, $clave = $null, $bd = "clinica_db") {
    if ($usuario) {
        $salida = $sql | docker exec -i -e PGPASSWORD=$clave pg_clinica psql -h localhost -U $usuario -d $bd -X -q -A -F "|" -P footer=off 2>&1
    } else {
        $salida = $sql | docker exec -i pg_clinica psql -U postgres -d $bd -X -q -A -F "|" -P footer=off 2>&1
    }
    $r = Resultado
    foreach ($o in $salida) {
        $l = "$o".TrimEnd()
        if ($o -is [System.Management.Automation.ErrorRecord]) {
            if ($l -match '^NOTICE:\s*(.*)$') { if ($Matches[1] -notmatch '^tds_fdw:') { $r.Avisos += $Matches[1] } }
            elseif ($l -match '^(ERROR|FATAL|WARNING):\s*(.*)$') {
                if ($Matches[2] -notmatch 'Table definition mismatch|Column will be ignored') { $r.Errores += $Matches[2] }
            }
            elseif ($l -match 'psql: error: .*FATAL:\s*(.*)$') { $r.Errores += $Matches[1] }
        }
        elseif ($l -ne '') {
            if ($r.Cols.Count -eq 0) { $r.Cols = @($l -split '\|') } else { $r.Rows += , @($l -split '\|') }
        }
    }
    $r
}

# SQL Server (sqlcmd separado por |)
function MSQ($sql, $usuario = "sa", $clave = "Admin_Sql2026!") {
    $lineas = docker exec mssql_integra /opt/mssql-tools18/bin/sqlcmd -C -S localhost -U $usuario -P $clave -d IntegracionMedica -W -s "|" -Q "SET NOCOUNT ON; $sql" 2>&1 | ForEach-Object { "$_".TrimEnd() }
    $r = Resultado
    if ($lineas | Where-Object { $_ -match '^Msg \d+' }) {
        $texto = ($lineas | Where-Object { $_ -ne '' }) -join ' '
        $r.Errores += ($texto -replace 'Msg (\d+), Level \d+, State \d+, Server [^,]+, Line \d+\s*', 'Error $1: ')
        return $r
    }
    foreach ($l in $lineas) {
        if ($l -eq '' -or $l -match '^-+(\|-+)*$' -or $l -match '^Warning:') { continue }
        if ($r.Cols.Count -eq 0) { $r.Cols = @($l -split '\|') } else { $r.Rows += , @($l -split '\|') }
    }
    $r
}

# MongoDB (devuelve el texto de la respuesta en una sola linea)
function MGQ($js, $usuario = "admin", $clave = "Admin_Mongo2026", $authdb = "admin") {
    $out = docker exec mongo_reportes mongosh --quiet -u $usuario -p $clave --authenticationDatabase $authdb --eval $js 2>&1 | ForEach-Object { "$_" }
    $texto = (($out | Where-Object { $_.Trim() -ne '' }) -join ' ').Trim()
    if ($texto -match 'not authorized on (\S+) to execute command \{\s*(\w+)') {
        return "Unauthorized: no autorizado en $($Matches[1]) para '$($Matches[2])'"
    }
    $texto
}

# =====================================================================
#  Piezas de la pagina
# =====================================================================
function Flujo($tokens) {
    ($tokens | ForEach-Object {
        switch ($_) {
            'pg'  { "<span class='chip pg'>PostgreSQL</span>" }
            'ms'  { "<span class='chip ms'>SQL Server</span>" }
            'mg'  { "<span class='chip mg'>MongoDB</span>" }
            'dk'  { "<span class='chip dk'>Docker</span>" }
            'app' { "<span class='chip app'>Aplicación</span>" }
            default { "<span class='sep'>$_</span>" }
        }
    }) -join ''
}

# Tabla HTML; $dest = columnas a resaltar; $filaDest = scriptblock que decide si una fila es "nueva"
function TablaHtml($r, $dest = @(), $filaDest = $null) {
    $h = "<div class='tabla'><table><tr>"
    foreach ($c in $r.Cols) { $cls = if ($dest -contains $c) { " class='dest'" } else { "" }; $h += "<th$cls>$(Esc $c)</th>" }
    $h += "</tr>"
    if ($r.Rows.Count -eq 0) { $h += "<tr><td class='vacio' colspan='$($r.Cols.Count)'>Sin filas</td></tr>" }
    foreach ($f in $r.Rows) {
        $nueva = $filaDest -and (& $filaDest $f)
        $h += if ($nueva) { "<tr class='nueva'>" } else { "<tr>" }
        for ($i = 0; $i -lt $r.Cols.Count; $i++) {
            $cls = if ($dest -contains $r.Cols[$i]) { " class='dest'" } else { "" }
            $h += "<td$cls>$(Esc $f[$i])</td>"
        }
        $h += "</tr>"
    }
    $h + "</table></div>"
}

# Tarjeta de evidencia: motor, titulo, usuario, mensajes, tabla y la consulta (oculta)
function Ev($motor, $titulo, $usuario, $r, $consulta, $dest = @(), $filaDest = $null) {
    $nombre = @{ pg = 'PostgreSQL'; ms = 'SQL Server'; mg = 'MongoDB'; dk = 'Docker' }[$motor]
    $h = "<div class='ev $motor'><div class='ev-cab'><span class='motor'>$nombre</span><span class='tit'>$(Esc $titulo)</span>"
    if ($usuario) { $h += "<span class='usr'>$(Esc $usuario)</span>" }
    $h += "</div>"
    foreach ($a in $r.Avisos)  { $h += "<div class='msg ok'>&#10004; $(Esc $a)</div>" }
    foreach ($e in $r.Errores) { $h += "<div class='msg err'>&#10006; $(Esc $e)</div>" }
    if ($r.Cols.Count) { $h += TablaHtml $r $dest $filaDest }
    if ($consulta) { $h += "<details><summary>Ver la consulta</summary><pre>$(Esc $consulta.Trim())</pre></details>" }
    $h + "</div>"
}

function AntesDespues($antes, $despues) {
    "<div class='ad'><div class='col'><div class='etq antes'>ANTES</div>$antes</div><div class='flecha'>&#10140;</div><div class='col'><div class='etq despues'>DESPUÉS</div>$despues</div></div>"
}

function Sub($texto) { "<h3>$(Esc $texto)</h3>" }

# --- Control de los pasos ------------------------------------------------
$pasos = New-Object System.Collections.ArrayList
function Paso($titulo, $motores, $que) {
    $script:actual = [ordered]@{ n = $pasos.Count + 1; titulo = $titulo; motores = $motores; que = $que; cuerpo = (New-Object System.Text.StringBuilder) }
    Write-Host -NoNewline ("Paso {0}: {1} ... " -f $script:actual.n, $titulo)
}
function Add($html) { [void]$script:actual.cuerpo.Append($html) }
function FinPaso($mirar, [bool]$ok) {
    $script:actual.mirar = $mirar; $script:actual.ok = $ok
    [void]$pasos.Add($script:actual)
    if ($ok) { Write-Host "correcto" -ForegroundColor Green } else { Write-Host "REVISAR" -ForegroundColor Yellow }
}

# =====================================================================
#  1. Servidores
# =====================================================================
Paso "Los tres servidores están encendidos" @('pg', 'ms', 'mg') "Cada motor corre en su propio contenedor Docker, dentro de la misma red privada (red_medica). Dentro de esa red se encuentran por nombre: postgres, sqlserver y mongodb."
$roles = @{
    pg_clinica     = @('PostgreSQL', 'Núcleo transaccional', '5433')
    mssql_integra  = @('SQL Server', 'Integración y facturación', '1434')
    mongo_reportes = @('MongoDB', 'Reportes y estadísticas', '27018')
}
$r = Resultado; $r.Cols = @('Contenedor', 'Motor', 'Función', 'Puerto en Windows', 'Estado')
docker ps --format "{{.Names}}|{{.Status}}" | ForEach-Object {
    $c = $_ -split '\|'
    if ($roles.ContainsKey($c[0])) { $x = $roles[$c[0]]; $r.Rows += , @($c[0], $x[0], $x[1], $x[2], $c[1]) }
}
Add (Ev 'dk' 'Contenedores en ejecución' $null $r 'docker ps')
$ok = $r.Rows.Count -eq 3 -and -not ($r.Rows | Where-Object { $_[4] -notmatch '^Up' })
FinPaso "Los 3 contenedores aparecen con estado <b>Up</b> (encendido)." $ok

# =====================================================================
#  2. Segmentacion
# =====================================================================
Paso "Segmentación horizontal y vertical" @('pg', '·', 'ms') "PostgreSQL divide la tabla pacientes por FILAS: un fragmento por sucursal. SQL Server guarda al paciente por COLUMNAS: solo los 4 datos que necesitan las aseguradoras."
$q1 = "SELECT tableoid::regclass AS fragmento, count(*) AS pacientes FROM pacientes GROUP BY 1 ORDER BY 1;"
$r1 = PGQ $q1
$q2 = "EXPLAIN (COSTS OFF) SELECT * FROM pacientes WHERE id_sucursal = 3;"
$r2 = PGQ $q2
$q3 = "SELECT TOP 5 * FROM dbo.paciente_integracion ORDER BY id_paciente;"
$r3 = MSQ $q3
Add (Sub "Horizontal (PostgreSQL)")
Add ("<div class='grid2'>" + (Ev 'pg' 'Pacientes en cada fragmento' 'postgres' $r1 $q1) + (Ev 'pg' 'Buscar los pacientes de Cartago' 'postgres' $r2 $q2) + "</div>")
Add (Sub "Vertical (SQL Server)")
Add (Ev 'ms' 'El paciente en SQL Server: solo 4 columnas' 'sa' $r3 $q3)
$plan = ($r2.Rows | ForEach-Object { $_[0] }) -join ' '
$ok = $r1.Rows.Count -eq 3 -and -not ($r1.Rows | Where-Object { $_[1] -ne '4' }) -and
      $plan -match 'pacientes_cartago' -and $plan -notmatch 'san_jose|alajuela' -and $r3.Cols.Count -eq 4
FinPaso "Hay <b>4 pacientes en cada fragmento</b>. El plan dice <b>Seq Scan on pacientes_cartago</b>: solo revisa el fragmento de Cartago. En SQL Server el paciente <b>no tiene nombre ni cédula</b>, solo 4 columnas." $ok

# =====================================================================
#  3. Operacion 1
# =====================================================================
Paso "Operación 1 · PostgreSQL consulta a SQL Server" @('pg', '&#8592;', 'ms') "Una sola consulta en PostgreSQL une los datos del paciente (locales) con su estado de facturación y su aseguradora, que están en SQL Server. Se leen en ese momento a través de tds_fdw."
$q = @"
SELECT p.id_paciente, p.nombre || ' ' || p.apellidos AS paciente, s.nombre AS sucursal,
       pi.estado_facturacion, a.nombre AS aseguradora
FROM pacientes p
JOIN sucursales s                  ON s.id_sucursal    = p.id_sucursal
JOIN mssql.paciente_integracion pi ON pi.id_paciente   = p.id_paciente
JOIN mssql.aseguradoras a          ON a.id_aseguradora = pi.id_aseguradora
ORDER BY p.id_paciente;
"@
$r = PGQ $q
Add (Ev 'pg' 'Paciente (PostgreSQL) + facturación (SQL Server)' 'postgres' $r $q @('estado_facturacion', 'aseguradora'))
FinPaso "12 pacientes. Las <span class='marca'>columnas resaltadas</span> vienen de SQL Server; el resto, de PostgreSQL." ($r.Rows.Count -eq 12 -and $r.Errores.Count -eq 0)

# =====================================================================
#  4. Operacion 4
# =====================================================================
Paso "Operación 4 · Exportación a MongoDB" @('pg', '&#8594;', 'mg') "PostgreSQL envía a MongoDB los estudios (como documentos JSON) y los indicadores mensuales por sucursal y tipo de estudio, usando mongo_fdw."
$q1 = "SELECT mongo.fn_exportar_resultados() AS estudios_enviados, mongo.fn_exportar_indicadores_mensuales() AS indicadores_enviados;"
$r1 = PGQ $q1
$js = "EJSON.stringify(db.getSiblingDB('reportes_medicos').resultados_estudios.findOne({id_estudio: 1}, {_id: 0}), null, 2)"
$doc = docker exec mongo_reportes mongosh --quiet -u admin -p Admin_Mongo2026 --eval $js 2>&1 | ForEach-Object { "$_" }
$q2 = "SELECT mes, sucursal, tipo, cantidad_estudios, ingreso_total FROM mongo.indicadores_mensuales ORDER BY mes, sucursal, tipo;"
$r2 = PGQ $q2
Add (Ev 'pg' 'Enviar estudios e indicadores' 'postgres' $r1 $q1)
Add "<div class='ev mg'><div class='ev-cab'><span class='motor'>MongoDB</span><span class='tit'>Así quedó un estudio en MongoDB (documento JSON)</span></div><pre class='doc'>$(Esc ($doc -join "`n"))</pre></div>"
Add (Ev 'mg' 'Indicadores mensuales guardados en MongoDB' 'leídos con mongo_fdw' $r2 $q2)
$ok = (V $r1 0 'estudios_enviados') -eq '12' -and (V $r1 0 'indicadores_enviados') -eq '10' -and $r2.Rows.Count -eq 10
FinPaso "Se enviaron <b>12 estudios</b> y <b>10 indicadores</b>. Cada estudio es un documento con el resultado del examen dentro (subdocumento)." $ok

# =====================================================================
#  5. Operacion 2 (los tres motores)
# =====================================================================
Paso "Operación 2 · Una operación que toca los tres motores" @('pg', '&#8594;', 'mg', '+', 'ms') "Se registra el resultado de un examen de glicemia (orden 13 del paciente 1). PostgreSQL lo guarda y lo confirma (COMMIT); después actualiza el resumen del paciente en MongoDB y crea la factura en SQL Server."
$qa = "SELECT paciente, total_estudios, ultimo_estudio FROM mongo.resumen_paciente WHERE id_paciente = 1;"
$qf = "SELECT id_estudio, codigo_estudio, costo, estado FROM dbo.facturas_externas WHERE id_paciente = 1 ORDER BY id_factura;"
$ma = PGQ $qa; $fa = MSQ $qf
$qc = "CALL sp_registrar_resultado(13, 1, 1, '{""glicemia"": 92, ""unidad"": ""mg/dL""}', 'Glicemia normal');"
$rc = PGQ $qc
$md = PGQ $qa; $fd = MSQ $qf
$nueva13 = { param($f) $f[0] -eq '13' }
Add (Sub "1. La acción, en PostgreSQL")
Add (Ev 'pg' 'Registrar el resultado de la orden 13' 'postgres' $rc $qc)
Add (Sub "2. Lo que cambió en MongoDB")
Add (AntesDespues (Ev 'mg' 'Resumen del paciente 1' 'leído con mongo_fdw' $ma $qa) (Ev 'mg' 'Resumen del paciente 1' 'leído con mongo_fdw' $md $qa @() { $true }))
Add (Sub "3. Lo que cambió en SQL Server")
Add (AntesDespues (Ev 'ms' 'Facturas del paciente 1' 'sa' $fa $qf) (Ev 'ms' 'Facturas del paciente 1' 'sa' $fd $qf @() $nueva13))
$fac13 = $fd.Rows | Where-Object { $_[0] -eq '13' -and $_[3] -eq 'PENDIENTE' }
$ok = $rc.Avisos.Count -ge 3 -and $rc.Errores.Count -eq 0 -and (V $ma 0 'total_estudios') -eq '1' -and (V $md 0 'total_estudios') -eq '2' -and $fac13
FinPaso "Tres mensajes verdes (uno por motor). En MongoDB <b>total_estudios pasa de 1 a 2</b>. En SQL Server aparece la <span class='marca nueva'>factura del estudio 13</span>, PENDIENTE." $ok

# =====================================================================
#  6. PostgreSQL escribe en SQL Server
# =====================================================================
Paso "PostgreSQL escribe en SQL Server" @('pg', '&#8594;', 'ms') "Se registra un paciente nuevo en la sucursal de Alajuela. PostgreSQL lo guarda en su fragmento y envía a SQL Server solo los datos que necesitan las aseguradoras, ejecutando un procedimiento almacenado."
$qs = "SELECT * FROM dbo.paciente_integracion WHERE id_paciente = 13;"
$sa = MSQ $qs
$qc = "CALL sp_registrar_paciente(2, '2-2222-0013', 'Sebastián', 'Rojas Umaña', '2000-02-14', 'M', '8888-0013', 'sebastian.rojas@correo.com', 2);"
$rc = PGQ $qc
$qp = "SELECT tableoid::regclass AS fragmento, id_paciente, nombre, apellidos, cedula FROM pacientes WHERE cedula = '2-2222-0013';"
$rp = PGQ $qp
$sd = MSQ $qs
Add (Sub "1. La acción, en PostgreSQL")
Add (Ev 'pg' 'Registrar paciente en Alajuela' 'postgres' $rc $qc)
Add (Ev 'pg' 'Fragmento donde quedó guardado' 'postgres' $rp $qp @() { $true })
Add (Sub "2. Lo que cambió en SQL Server")
Add (AntesDespues (Ev 'ms' 'Paciente 13 en SQL Server' 'sa' $sa $qs) (Ev 'ms' 'Paciente 13 en SQL Server' 'sa' $sd $qs @() { $true }))
$ok = $rc.Errores.Count -eq 0 -and (V $rp 0 'fragmento') -eq 'pacientes_alajuela' -and (V $sd 0 'codigo_externo') -eq 'AVP-000013' -and $sa.Rows.Count -eq 0
FinPaso "El paciente quedó en <b>pacientes_alajuela</b>. En SQL Server antes no existía y ahora aparece con el código <b>AVP-000013</b>, sin nombre ni cédula." $ok

# =====================================================================
#  7. Operacion 3
# =====================================================================
Paso "Operación 3 · Vista para la aplicación web" @('app', '&#8594;', 'pg', '&#8592;', 'ms') "Se inicia sesión como la aplicación web (usr_api_web, con su contraseña). Este usuario no tiene permiso sobre ninguna tabla, solo sobre sus vistas. La vista mezcla datos de PostgreSQL y de SQL Server."
$q = "SELECT paciente, sucursal, aseguradora, estado_facturacion, total_facturado, total_pendiente FROM api_web.v_pacientes_facturacion ORDER BY id_paciente;"
$r = PGQ $q "usr_api_web" "Api_Web2026"
Add (Ev 'pg' 'Vista api_web.v_pacientes_facturacion' 'usr_api_web' $r $q @('aseguradora', 'estado_facturacion', 'total_facturado', 'total_pendiente') { param($f) $f[0] -like 'José Pérez*' })
FinPaso "13 pacientes (incluye al nuevo de Alajuela). Las <span class='marca'>columnas resaltadas</span> vienen de SQL Server. <span class='marca nueva'>José Pérez</span> ahora debe ₡5 000 por la factura del paso 5." ($r.Rows.Count -eq 13 -and $r.Errores.Count -eq 0)

# =====================================================================
#  8. Operacion 5
# =====================================================================
Paso "Operación 5 · Reporte analítico en MongoDB" @('mg') "MongoDB agrupa los estudios por médico y por tipo de estudio, y calcula la cantidad y los ingresos. Es un indicador de productividad médica que se calcula sin cargar la base transaccional."
$json = docker exec mongo_reportes mongosh --quiet -u admin -p Admin_Mongo2026 /scripts/06_reporte_json.js | Out-String
$r = Resultado; $r.Cols = @('Médico', 'Tipo de estudio', 'Cantidad', 'Ingresos (₡)')
foreach ($f in ($json | ConvertFrom-Json)) { $r.Rows += , @($f.medico, $f.tipo_de_estudio, "$($f.cantidad)", ('{0:N0}' -f $f.ingresos)) }
$pipeline = @'
db.resultados_estudios.aggregate([
  { $group: { _id: { medico: "$medico", tipo: "$tipo" },
              cantidad: { $sum: 1 }, ingresos: { $sum: "$costo" } } },
  { $project: { _id: 0, medico: "$_id.medico", tipo_de_estudio: "$_id.tipo",
                cantidad: 1, ingresos: 1 } },
  { $sort: { medico: 1, tipo_de_estudio: 1 } }
])
'@
Add (Ev 'mg' 'Estudios e ingresos por médico y tipo' 'admin' $r $pipeline)
FinPaso "Una fila por cada combinación de médico y tipo de estudio, con cuántos estudios hizo y cuánto ingresó." ($r.Rows.Count -gt 0)

# =====================================================================
#  9. Seguridad
# =====================================================================
Paso "Seguridad · Cada usuario solo puede lo que le corresponde" @('pg', '·', 'ms', '·', 'mg') "Se prueban accesos permitidos y accesos que NO deberían estar permitidos. Que el servidor rechace estos últimos (mensaje en rojo) es el resultado correcto."
$intentos = New-Object System.Collections.ArrayList
function Intento($motor, $usuario, $accion, [bool]$permitido, $respuesta, [bool]$cumple) {
    [void]$intentos.Add([pscustomobject]@{ Motor = $motor; Usuario = $usuario; Accion = $accion; Permitido = $permitido; Respuesta = $respuesta; Cumple = $cumple })
}
function Primero($r) { if ($r.Errores.Count) { $r.Errores[0] } else { "Permitido: $($r.Rows.Count) fila(s)" } }

$r = PGQ "SELECT * FROM api_movil.v_mis_citas WHERE id_paciente = 1;" "usr_api_mobile" "Api_Mobile2026"
Intento 'pg' 'usr_api_mobile' 'Leer su propia vista (api_movil.v_mis_citas)' $true (Primero $r) ($r.Errores.Count -eq 0)
$r = PGQ "SELECT * FROM pacientes LIMIT 1;" "usr_api_mobile" "Api_Mobile2026"
Intento 'pg' 'usr_api_mobile' 'Leer la tabla pacientes' $false (Primero $r) ("$($r.Errores)" -match 'permission denied')
$r = PGQ "SELECT * FROM api_web.v_pacientes_facturacion LIMIT 1;" "usr_api_mobile" "Api_Mobile2026"
Intento 'pg' 'usr_api_mobile' 'Leer las vistas de la aplicación web' $false (Primero $r) ("$($r.Errores)" -match 'permission denied')
$r = PGQ "INSERT INTO citas (id_sucursal, id_paciente, id_medico, fecha_hora) VALUES (1, 1, 1, now());" "usr_api_mobile" "Api_Mobile2026"
Intento 'pg' 'usr_api_mobile' 'Insertar una cita' $false (Primero $r) ("$($r.Errores)" -match 'read-only|permission denied')
$r = PGQ "SELECT 1;" "usr_api_web" "Api_Web2026" "postgres"
Intento 'pg' 'usr_api_web' 'Conectarse a otra base de datos (postgres)' $false (Primero $r) ("$($r.Errores)" -match 'pg_hba.conf rejects')
$r = PGQ "SELECT 1;" "usr_fdw_pg_mssql" "Fdw_Mssql2026!"
Intento 'pg' 'usr_fdw_pg_mssql' 'Iniciar sesión en PostgreSQL desde afuera' $false (Primero $r) ("$($r.Errores)" -match 'pg_hba.conf rejects')
$r = MSQ "SELECT TOP 3 id_paciente, estado_facturacion FROM dbo.paciente_integracion;" "usr_fdw_pg_mssql" "Fdw_Mssql2026!"
Intento 'ms' 'usr_fdw_pg_mssql' 'Leer paciente_integracion' $true (Primero $r) ($r.Errores.Count -eq 0)
$r = MSQ "DELETE FROM dbo.facturas_externas WHERE id_factura = 1;" "usr_fdw_pg_mssql" "Fdw_Mssql2026!"
Intento 'ms' 'usr_fdw_pg_mssql' 'Borrar una factura' $false (Primero $r) ("$($r.Errores)" -match 'Error 229')
$t = MGQ "db.getSiblingDB('reportes_medicos').resumen_paciente.countDocuments()" "usr_api_mobile" "Api_Mobile2026" "reportes_medicos"
Intento 'mg' 'usr_api_mobile' 'Leer resumen_paciente' $true "Permitido: $t documentos" ($t -match '^\d+$')
$t = MGQ "db.getSiblingDB('reportes_medicos').resultados_estudios.findOne()" "usr_api_mobile" "Api_Mobile2026" "reportes_medicos"
Intento 'mg' 'usr_api_mobile' 'Leer resultados_estudios' $false $t ($t -match 'Unauthorized')
$t = MGQ "db.getSiblingDB('reportes_medicos').resumen_paciente.insertOne({prueba: 1})" "usr_api_mobile" "Api_Mobile2026" "reportes_medicos"
Intento 'mg' 'usr_api_mobile' 'Insertar en resumen_paciente' $false $t ($t -match 'Unauthorized')

$h = "<div class='tabla'><table class='seg'><tr><th>Motor</th><th>Usuario</th><th>Intento</th><th>Debe ser</th><th>Lo que respondió el servidor</th><th></th></tr>"
foreach ($i in $intentos) {
    $esp = if ($i.Permitido) { "<span class='pill si'>Permitido</span>" } else { "<span class='pill no'>Rechazado</span>" }
    $cls = if ($i.Permitido) { 'ok' } else { 'err' }
    $sello = if ($i.Cumple) { "<span class='check'>&#10004;</span>" } else { "<span class='check mal'>&#10006;</span>" }
    $h += "<tr><td>$(Flujo @($i.Motor))</td><td><code>$(Esc $i.Usuario)</code></td><td>$(Esc $i.Accion)</td><td>$esp</td><td class='resp $cls'>$(Esc $i.Respuesta)</td><td>$sello</td></tr>"
}
Add ($h + "</table></div>")
$ok = -not ($intentos | Where-Object { -not $_.Cumple })
FinPaso "Cada fila tiene un <span class='check'>&#10004;</span>: lo permitido funcionó y todo lo indebido fue rechazado (por permisos, por modo solo lectura, por <b>pg_hba.conf</b>, por el <b>error 229</b> de SQL Server o por <b>Unauthorized</b> de MongoDB)." $ok

# =====================================================================
#  Armado de la pagina
# =====================================================================
$total = $pasos.Count
$bien = @($pasos | Where-Object { $_.ok }).Count
$estado = if ($bien -eq $total) { "<div class='resumen ok'>&#10004; $bien de $total pruebas correctas</div>" } else { "<div class='resumen mal'>&#9888; $bien de $total pruebas correctas: revise las marcadas</div>" }

$css = @'
:root{--pg:#336791;--ms:#cc2927;--mg:#13834a;--dk:#4b5563;--app:#7c3aed;--txt:#1f2937;--suave:#6b7280;--borde:#e5e7eb;--fondo:#f3f4f6}
*{box-sizing:border-box} html{scroll-behavior:smooth}
body{margin:0;font-family:'Segoe UI',Arial,sans-serif;background:var(--fondo);color:var(--txt);line-height:1.5}
header{background:linear-gradient(135deg,#16304f,#336791);color:#fff;padding:32px 24px 26px}
.hwrap{max-width:1100px;margin:0 auto} header h1{margin:0 0 4px;font-size:28px} header p{margin:0;opacity:.85}
.resumen{display:inline-block;margin-top:16px;padding:8px 18px;border-radius:999px;font-weight:700;font-size:17px}
.resumen.ok{background:#dcfce7;color:#14532d} .resumen.mal{background:#fef3c7;color:#78350f}
main{max-width:1100px;margin:0 auto;padding:24px 16px 40px}
.panel{background:#fff;border-radius:14px;box-shadow:0 2px 10px rgba(0,0,0,.06);padding:22px 24px;margin-bottom:22px}
.panel h2{margin:0 0 12px;font-size:20px}
.leer{display:grid;grid-template-columns:repeat(auto-fit,minmax(230px,1fr));gap:10px;font-size:14px;color:var(--suave)}
.leer div{background:var(--fondo);border-radius:10px;padding:10px 12px} .leer b{color:var(--txt)}
.mapa{display:flex;flex-direction:column;align-items:center;gap:8px}
.apps{display:flex;gap:12px;flex-wrap:wrap;justify-content:center}
.baja{font-size:13px;color:var(--suave);text-align:center}
.fila{display:grid;grid-template-columns:1fr auto 1fr auto 1fr;gap:10px;align-items:center;width:100%}
.nodo{border:2px solid;border-radius:12px;padding:12px 14px;text-align:center;background:#fff;min-width:170px}
.nodo b{display:block;font-size:16px} .nodo small{color:var(--suave);font-size:12.5px}
.nodo.pg{border-color:var(--pg);background:#eef4fa} .nodo.ms{border-color:var(--ms);background:#fdf0f0} .nodo.mg{border-color:var(--mg);background:#edf7f1} .nodo.app{border-color:var(--app);background:#f5f0ff}
.nodo.pg b{color:var(--pg)} .nodo.ms b{color:var(--ms)} .nodo.mg b{color:var(--mg)} .nodo.app b{color:var(--app)}
.enlace{text-align:center;font-size:12.5px;color:var(--suave);max-width:190px} .enlace span{display:block;font-weight:700;color:var(--txt);font-size:14px}
.red{font-size:12.5px;color:var(--suave);border:1px dashed #cbd5e1;border-radius:999px;padding:3px 14px}
.indice{display:grid;grid-template-columns:repeat(auto-fit,minmax(240px,1fr));gap:10px}
.indice a{display:flex;gap:10px;align-items:center;padding:10px 12px;border-radius:10px;background:var(--fondo);text-decoration:none;color:var(--txt);font-size:14px}
.indice a:hover{background:#e5e7eb} .indice .n{flex:0 0 26px;height:26px;border-radius:50%;background:#16304f;color:#fff;font-weight:700;display:flex;align-items:center;justify-content:center;font-size:13px}
.indice .s{margin-left:auto;font-weight:700} .s.ok{color:#15803d} .s.mal{color:#b45309}
.paso{background:#fff;border-radius:14px;box-shadow:0 2px 10px rgba(0,0,0,.06);padding:22px 24px;margin-bottom:22px;scroll-margin-top:12px}
.paso-cab{display:flex;gap:14px;align-items:flex-start}
.num{flex:0 0 44px;height:44px;border-radius:50%;background:#16304f;color:#fff;font-weight:700;font-size:20px;display:flex;align-items:center;justify-content:center}
.paso-tit{flex:1;min-width:0} .paso-tit h2{margin:2px 0 6px;font-size:21px}
.sello{flex:0 0 auto;padding:6px 14px;border-radius:999px;font-weight:700;font-size:14px;white-space:nowrap}
.sello.ok{background:#dcfce7;color:#14532d} .sello.mal{background:#fef3c7;color:#78350f}
.chip{display:inline-block;color:#fff;font-size:12px;font-weight:700;padding:2px 10px;border-radius:6px}
.chip.pg{background:var(--pg)} .chip.ms{background:var(--ms)} .chip.mg{background:var(--mg)} .chip.dk{background:var(--dk)} .chip.app{background:var(--app)}
.sep{margin:0 6px;color:var(--suave);font-weight:700}
.que{margin:14px 0 6px;font-size:15.5px}
h3{margin:18px 0 6px;font-size:15px;color:#16304f;text-transform:uppercase;letter-spacing:.03em}
.ev{border:1px solid var(--borde);border-left:6px solid;border-radius:10px;margin:10px 0;padding:12px 14px;min-width:0;background:#fff}
.ev.pg{border-left-color:var(--pg)} .ev.ms{border-left-color:var(--ms)} .ev.mg{border-left-color:var(--mg)} .ev.dk{border-left-color:var(--dk)}
.ev-cab{display:flex;align-items:center;gap:8px;flex-wrap:wrap;margin-bottom:8px}
.motor{color:#fff;font-size:12px;font-weight:700;padding:2px 9px;border-radius:6px}
.pg .motor{background:var(--pg)} .ms .motor{background:var(--ms)} .mg .motor{background:var(--mg)} .dk .motor{background:var(--dk)}
.tit{font-weight:600} .usr{font-size:12px;color:var(--suave);background:var(--fondo);padding:1px 8px;border-radius:6px}
.tabla{overflow-x:auto}
table{border-collapse:collapse;font-size:14px;margin:4px 0;min-width:50%}
th{background:#eef2f7;text-align:left;padding:7px 12px;border-bottom:2px solid #d1d5db;white-space:nowrap}
td{padding:6px 12px;border-bottom:1px solid #eef0f3;white-space:nowrap}
th.dest{background:#fde2e2} td.dest{background:#fff5f5;font-weight:600}
tr.nueva td{background:#fef9c3 !important;font-weight:600}
td.vacio{color:var(--suave);font-style:italic;text-align:center}
.msg{padding:7px 12px;border-radius:8px;margin:5px 0;font-size:14px}
.msg.ok{background:#e8f7ee;color:#0e5530} .msg.err{background:#fdecec;color:#9b1c1c}
details{margin-top:8px} summary{cursor:pointer;color:var(--pg);font-size:13px;font-weight:600}
pre{background:#0f172a;color:#7dd3fc;font:13px/1.45 Consolas,monospace;padding:10px 12px;border-radius:8px;margin:6px 0 0;white-space:pre-wrap;overflow-x:auto}
pre.doc{color:#a7f3d0;max-height:330px;overflow:auto}
.grid2{display:grid;grid-template-columns:minmax(0,1fr) minmax(0,1fr);gap:12px} .grid2>.ev{margin:10px 0}
.ad{display:grid;grid-template-columns:minmax(0,1fr) auto minmax(0,1fr);gap:10px;align-items:start} .ad .col{min-width:0}
.ad table{font-size:13px} .ad th,.ad td{padding:6px 9px}
.flecha{font-size:28px;color:var(--suave);align-self:center}
.etq{display:inline-block;font-size:12px;font-weight:700;padding:2px 10px;border-radius:6px;letter-spacing:.05em}
.etq.antes{background:#e5e7eb;color:#374151} .etq.despues{background:#fef9c3;color:#713f12}
.mirar{margin-top:16px;padding:12px 16px;background:#eff6ff;border:1px solid #bfdbfe;border-radius:10px;font-size:14.5px}
.marca{background:#fde2e2;padding:0 5px;border-radius:4px;font-weight:600} .marca.nueva{background:#fef9c3}
table.seg td{white-space:normal} .resp{font-size:13px} .resp.ok{color:#0e5530} .resp.err{color:#9b1c1c}
.pill{font-size:12px;font-weight:700;padding:2px 10px;border-radius:999px;white-space:nowrap} .pill.si{background:#dcfce7;color:#14532d} .pill.no{background:#e5e7eb;color:#374151}
.check{color:#15803d;font-weight:700;font-size:18px} .check.mal{color:#b45309}
code{background:var(--fondo);padding:1px 6px;border-radius:5px;font-size:13px}
footer{text-align:center;color:var(--suave);font-size:13px;padding:0 16px 30px}
@media (max-width:820px){.grid2,.ad{grid-template-columns:1fr} .flecha{transform:rotate(90deg);justify-self:center} .fila{grid-template-columns:1fr} .enlace{max-width:none} .paso-cab{flex-wrap:wrap}}
'@

$sb = New-Object System.Text.StringBuilder
function W($s) { [void]$sb.Append($s) }
W "<!doctype html><html lang='es'><head><meta charset='utf-8'><meta name='viewport' content='width=device-width, initial-scale=1'><title>Reporte de pruebas</title><style>$css</style></head><body>"
W "<header><div class='hwrap'><h1>Sistema de Gestión de Estudios Médicos Distribuido</h1>"
W "<p>Reporte de pruebas · ejecutado el $(Get-Date -Format 'dd/MM/yyyy') a las $(Get-Date -Format 'HH:mm') · resultados reales de los tres servidores</p>$estado</div></header><main>"

W @"
<section class='panel'><h2>Cómo leer este reporte</h2><div class='leer'>
<div><b>Colores:</b> <span class='chip pg'>PostgreSQL</span> transaccional, <span class='chip ms'>SQL Server</span> integración, <span class='chip mg'>MongoDB</span> reportes.</div>
<div><b>Sello de cada prueba:</b> el script revisa solo el resultado. <span style='color:#15803d;font-weight:700'>&#10004; Correcto</span> significa que salió lo esperado.</div>
<div><b>Resaltados:</b> <span class='marca'>celda rosada</span> = dato que viene de SQL Server · <span class='marca nueva'>fila amarilla</span> = dato nuevo o que cambió.</div>
<div><b>Recuadro azul «Qué mirar»:</b> dice en qué fijarse de los resultados de esa prueba.</div>
<div><b>«Ver la consulta»:</b> muestra el SQL o el comando exacto que se ejecutó.</div>
</div></section>
<section class='panel'><h2>Mapa de conexiones</h2><div class='mapa'>
<div class='apps'><div class='nodo app'><b>Aplicación web</b><small>usuario usr_api_web · vistas api_web</small></div><div class='nodo app'><b>Aplicación móvil</b><small>usuario usr_api_mobile · vistas api_movil</small></div></div>
<div class='baja'>&#8595; contraseña cifrada (scram-sha-256) · solo lectura · solo a clinica_db</div>
<div class='fila'>
<div class='nodo ms'><b>SQL Server</b><small>Integración y facturación<br>segmentación vertical</small></div>
<div class='enlace'><span>&#8592; tds_fdw &#8594;</span>lee tablas y ejecuta procedimientos<br>usuario usr_fdw_pg_mssql</div>
<div class='nodo pg'><b>PostgreSQL</b><small>Núcleo transaccional (centro)<br>segmentación horizontal</small></div>
<div class='enlace'><span>mongo_fdw &#8594;</span>envía estudios, resúmenes e indicadores<br>usuario usr_fdw_pg_mongo</div>
<div class='nodo mg'><b>MongoDB</b><small>Reportes y estadísticas<br>documentos JSON</small></div>
</div>
<div class='red'>Los tres en contenedores Docker, dentro de la red privada red_medica</div>
</div></section>
"@

W "<section class='panel'><h2>Pruebas</h2><div class='indice'>"
foreach ($p in $pasos) {
    $s = if ($p.ok) { "<span class='s ok'>&#10004;</span>" } else { "<span class='s mal'>&#9888;</span>" }
    W "<a href='#paso-$($p.n)'><span class='n'>$($p.n)</span>$(Esc $p.titulo)$s</a>"
}
W "</div></section>"

foreach ($p in $pasos) {
    $sello = if ($p.ok) { "<div class='sello ok'>&#10004; Correcto</div>" } else { "<div class='sello mal'>&#9888; Revisar</div>" }
    W "<section class='paso' id='paso-$($p.n)'><div class='paso-cab'><div class='num'>$($p.n)</div><div class='paso-tit'><h2>$(Esc $p.titulo)</h2>$(Flujo $p.motores)</div>$sello</div>"
    W "<p class='que'><b>Qué se demuestra:</b> $(Esc $p.que)</p>"
    W $p.cuerpo.ToString()
    W "<div class='mirar'><b>Qué mirar:</b> $($p.mirar)</div></section>"
}

W "</main><footer>Proyecto 2 · Bases de Datos II · Instituto Tecnológico de Costa Rica<br>Las pruebas 5 y 6 registran datos nuevos. Para repetir el reporte: <code>powershell -ExecutionPolicy Bypass -File .\instalar.ps1 -Reiniciar</code></footer></body></html>"

[IO.File]::WriteAllText($archivo, $sb.ToString(), (New-Object Text.UTF8Encoding $false))
Write-Host ""
if ($bien -eq $total) { Write-Host "$bien de $total pruebas correctas" -ForegroundColor Green } else { Write-Host "$bien de $total pruebas correctas: revise las marcadas" -ForegroundColor Yellow }
Write-Host "Reporte generado: $archivo"
if (-not $NoAbrir) { Start-Process $archivo }
