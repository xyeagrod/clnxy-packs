
# CLNXY PACKS - BUILD CATALOG
# Uruchom z folderu repozytorium:
# powershell -ExecutionPolicy Bypass -File .\tools\build-catalog.ps1

$ErrorActionPreference = 'Stop'

try {
    Write-Host "`n=== CLNXY CATALOG BUILDER ===" -ForegroundColor Cyan

    # Ścieżki
    $root     = Split-Path -Parent $PSScriptRoot
    $packsDir = Join-Path $root 'packs'
    $distDir  = Join-Path $root 'dist'
    $catalogPath = Join-Path $root 'catalog.json'

    Write-Host "ROOT: $root"

    # Sprawdzenie folderów
    if (-not (Test-Path -LiteralPath $packsDir -PathType Container)) {
        throw "Nie znaleziono folderu packs: $packsDir"
    }

    New-Item -ItemType Directory -Force -Path $distDir | Out-Null

    # Pobranie paczek
    $directories = @(Get-ChildItem -LiteralPath $packsDir -Directory)
    $entries = @()

    Write-Host "Znaleziono paczek: $($directories.Count)" -ForegroundColor Cyan

    foreach ($dir in $directories) {

        Write-Host "`nPrzetwarzanie: $($dir.Name)" -ForegroundColor Yellow

        # Manifest
        $manifestPath = Join-Path $dir.FullName 'pack.json'

        if (-not (Test-Path -LiteralPath $manifestPath)) {
            Write-Warning "Pomijam $($dir.Name): brak pack.json"
            continue
        }

        $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 |
            ConvertFrom-Json

        if ([string]::IsNullOrWhiteSpace($manifest.id)) {
            throw "Paczka $($dir.Name) nie posiada ID w pack.json"
        }

        Write-Host "Manifest: OK"

        # Tworzenie ZIP
        $zipPath = Join-Path $distDir "$($manifest.id).zip"

        if (Test-Path -LiteralPath $zipPath) {
            Remove-Item -LiteralPath $zipPath -Force
        }

        Compress-Archive `
            -Path (Join-Path $dir.FullName '*') `
            -DestinationPath $zipPath `
            -Force

        Write-Host "ZIP: OK"

        # SHA256 i rozmiar
        $hash = (Get-FileHash -Path $zipPath -Algorithm SHA256).Hash.ToLower()
        $size = (Get-Item -LiteralPath $zipPath).Length

        Write-Host "SHA256: OK"
        Write-Host "Rozmiar: $size bajtów"

        # Instrukcje
        $instructionsText = ''

        if ($manifest.instructions) {
            $instructionsPath = Join-Path $dir.FullName $manifest.instructions

            if (Test-Path -LiteralPath $instructionsPath -PathType Leaf) {
                $instructionsText = Get-Content -LiteralPath $instructionsPath -Raw -Encoding UTF8
            }
        }

        # Obrazy
        $prefix = "packs/$($dir.Name)/"

        $previews = @()

        foreach ($p in @($manifest.previews)) {
            if ($p) {
                $previews += ($prefix + $p)
            }
        }

        $thumb = $null

        if ($manifest.thumbnail) {
            $thumb = $prefix + $manifest.thumbnail
        }

        # Wpis katalogu
        $entries += [ordered]@{
            id               = $manifest.id
            name             = $manifest.name
            author           = $manifest.author
            version          = $manifest.version
            description      = $manifest.description
            colorGroup       = $manifest.colorGroup
            thumbnail        = $thumb
            previews         = $previews
            contains         = @($manifest.contains)
            requires         = @($manifest.requires)
            instructionsText = $instructionsText
            package          = "dist/$($manifest.id).zip"
            sha256           = $hash
            sizeBytes        = $size
        }

        Write-Host "Wpis katalogu: OK" -ForegroundColor Green
    }

    # Budowanie katalogu
    Write-Host "`nGenerowanie catalog.json..." -ForegroundColor Cyan

    $catalog = [ordered]@{
        version = 1
        packs   = $entries
    }

    
Write-Host "TEST A: Przed ConvertTo-Json"

Write-Host "Konwersja JSON przez Newtonsoft.Json..."

Write-Host "Generowanie JSON..." -ForegroundColor Cyan

# Zamiana danych na zwykłe obiekty PowerShell
$cleanEntries = @(
    foreach ($entry in $entries) {
        @{
            id               = [string]$entry.id
            name             = [string]$entry.name
            author           = [string]$entry.author
            version          = [string]$entry.version
            description      = [string]$entry.description
            colorGroup       = [string]$entry.colorGroup
            thumbnail        = $entry.thumbnail
            previews         = @($entry.previews)
            contains         = @($entry.contains)
            requires         = @(
                foreach ($req in $entry.requires) {
                    @{
                        name     = $req.name
                        url      = $req.url
                        optional = $req.optional
                        note     = $req.note
                    }
                }
            )
            instructionsText = [string]$entry.instructionsText
            package          = [string]$entry.package
            sha256           = [string]$entry.sha256
            sizeBytes        = [long]$entry.sizeBytes
        }
    }
)

$catalog = @{
    version = 1
    packs   = $cleanEntries
}

$json = ConvertTo-Json -InputObject $catalog -Depth 10

Write-Host "JSON wygenerowany!" -ForegroundColor Green


Write-Host "JSON wygenerowany poprawnie!" -ForegroundColor Green

Write-Host "TEST B: Po ConvertTo-Json"
Write-Host "Dlugosc JSON: $($json.Length)"

$encoding = New-Object System.Text.UTF8Encoding($false)

Write-Host "TEST C: Przed zapisem"

[System.IO.File]::WriteAllText(
    $catalogPath,
    $json,
    $encoding
)

Write-Host "TEST D: Po zapisie"

Write-Host "Plik istnieje: $(Test-Path $catalogPath)"


    if ([string]::IsNullOrWhiteSpace($json)) {
        throw "ConvertTo-Json zwrócił pusty wynik."
    }

    # Zapis UTF-8 bez BOM
    $encoding = New-Object System.Text.UTF8Encoding($false)

    [System.IO.File]::WriteAllText(
        $catalogPath,
        $json,
        $encoding
    )

    # Weryfikacja
    if (-not (Test-Path -LiteralPath $catalogPath -PathType Leaf)) {
        throw "Nie udało się utworzyć catalog.json."
    }

    $catalogSize = (Get-Item -LiteralPath $catalogPath).Length

    Write-Host "`n================================" -ForegroundColor Green
    Write-Host "BUILD ZAKOŃCZONY POMYŚLNIE" -ForegroundColor Green
    Write-Host "Paczki: $($entries.Count)"
    Write-Host "Katalog: $catalogPath"
    Write-Host "Rozmiar katalogu: $catalogSize bajtów"
    Write-Host "================================" -ForegroundColor Green
}
catch {
    Write-Host "`n================================" -ForegroundColor Red
    Write-Host "BUILD NIE POWIÓDŁ SIĘ" -ForegroundColor Red
    Write-Host "BŁĄD: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host "LINIA: $($_.InvocationInfo.ScriptLineNumber)"
    Write-Host "================================" -ForegroundColor Red

    exit 1
}
