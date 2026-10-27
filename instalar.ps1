# =====================================================================
#  instalar.ps1 - Levanta los 3 servidores y ejecuta TODOS los scripts
#  en el orden correcto. Ejecutar desde la carpeta del proyecto:
#       powershell -ExecutionPolicy Bypass -File .\instalar.ps1
#  Para borrar todo y empezar desde cero:
#       powershell -ExecutionPolicy Bypass -File .\instalar.ps1 -Reiniciar
# =====================================================================
param([switch]$Reiniciar)

# Los errores se revisan con $LASTEXITCODE despues de cada comando
$ErrorActionPreference = "Continue"

function Paso($texto) { Write-Host "`n==== $texto ====" -ForegroundColor Cyan }

if ($Reiniciar) {
    Paso "0. Borrando la instalacion anterior (contenedores y datos)"
    docker compose down -v
}

Paso "1. Descargando imagenes y levantando contenedores"
# Descarga las 3 imagenes ya listas (PostgreSQL desde GitHub Container Registry).
# Si la de PostgreSQL no se puede descargar, "up" la construye desde postgres/Dockerfile.
docker compose pull --ignore-pull-failures
docker compose up -d

Paso "2. Esperando a que los 3 servidores esten listos"
do { Start-Sleep 3; docker exec pg_clinica pg_isready -U postgres *> $null } until ($LASTEXITCODE -eq 0)
Write-Host "PostgreSQL listo"
do { Start-Sleep 3; docker exec mongo_reportes mongosh --quiet -u admin -p Admin_Mongo2026 --eval "db.runCommand({ping:1}).ok" *> $null } until ($LASTEXITCODE -eq 0)
Write-Host "MongoDB listo"
do { Start-Sleep 3; docker exec mssql_integra /opt/mssql-tools18/bin/sqlcmd -C -S localhost -U sa -P "Admin_Sql2026!" -Q "SELECT 1" *> $null } until ($LASTEXITCODE -eq 0)
Write-Host "SQL Server listo"

# Si las bases ya existen, no se vuelven a crear (daria errores de "ya existe")
$existe = docker exec mssql_integra /opt/mssql-tools18/bin/sqlcmd -C -S localhost -U sa -P "Admin_Sql2026!" -h -1 -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM sys.databases WHERE name = 'IntegracionMedica'"
if ("$existe".Trim() -eq "1") {
    Write-Host "`nEl sistema YA ESTA INSTALADO: los 3 servidores estan funcionando." -ForegroundColor Green
    Write-Host "Para borrar todo e instalar desde cero ejecute:"
    Write-Host "  powershell -ExecutionPolicy Bypass -File .\instalar.ps1 -Reiniciar"
    exit 0
}

Paso "3. SQL Server: base IntegracionMedica"
foreach ($f in "01_crear_bd.sql", "02_datos_prueba.sql", "03_procedimientos.sql", "04_seguridad.sql") {
    Write-Host "-> $f"
    docker exec mssql_integra /opt/mssql-tools18/bin/sqlcmd -C -S localhost -U sa -P "Admin_Sql2026!" -b -i "/scripts/$f"
    if ($LASTEXITCODE -ne 0) { throw "Fallo $f" }
}

Paso "4. MongoDB: base reportes_medicos"
foreach ($f in "01_crear_bd.js", "02_seguridad.js") {
    Write-Host "-> $f"
    docker exec mongo_reportes mongosh --quiet -u admin -p Admin_Mongo2026 --authenticationDatabase admin "/scripts/$f"
    if ($LASTEXITCODE -ne 0) { throw "Fallo $f" }
}

Paso "5. PostgreSQL: base clinica_db"
foreach ($f in "01_modelo_segmentado.sql", "02_datos_prueba.sql", "03_roles.sql",
               "04_fdw_sqlserver.sql", "05_fdw_mongodb.sql",
               "06_operaciones_distribuidas.sql", "07_vistas_api.sql") {
    Write-Host "-> $f"
    docker exec pg_clinica psql -U postgres -d clinica_db -v ON_ERROR_STOP=1 -q -f "/scripts/$f"
    if ($LASTEXITCODE -ne 0) { throw "Fallo $f" }
}

Paso "6. Carga inicial hacia MongoDB y sincronizacion con SQL Server"
docker exec pg_clinica psql -U postgres -d clinica_db -c "SELECT mongo.fn_exportar_resultados() AS estudios, mongo.fn_exportar_indicadores_mensuales() AS indicadores, mssql.fn_sincronizar_convenios() AS convenios;"

Paso "LISTO. Para la demostracion ejecute:"
Write-Host "  docker exec -it pg_clinica psql -U postgres -d clinica_db -f /scripts/08_consultas_prueba.sql"
Write-Host "  docker exec -it mssql_integra /opt/mssql-tools18/bin/sqlcmd -C -S localhost -U sa -P `"Admin_Sql2026!`" -i /scripts/05_consultas_prueba.sql"
Write-Host "  docker exec -it mongo_reportes mongosh -u admin -p Admin_Mongo2026 /scripts/03_consultas_analiticas.js"
