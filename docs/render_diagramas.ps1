# Convierte los diagramas SVG de docs\diagramas a PNG usando Microsoft Edge (sin ventana)
#   powershell -ExecutionPolicy Bypass -File .\docs\render_diagramas.ps1
$edge = "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
$carpeta = Join-Path $PSScriptRoot "diagramas"

Get-ChildItem $carpeta -Filter *.svg | ForEach-Object {
    [xml]$svg = Get-Content $_.FullName -Raw -Encoding UTF8
    $ancho = $svg.svg.width; $alto = $svg.svg.height
    $png = [IO.Path]::ChangeExtension($_.FullName, ".png")
    $url = "file:///" + ($_.FullName -replace "\\", "/")
    & $edge --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=2 `
        "--window-size=$ancho,$alto" "--screenshot=$png" $url 2>$null | Out-Null
    Start-Sleep -Milliseconds 800
    Write-Host "$($_.Name) -> $([IO.Path]::GetFileName($png))"
}
