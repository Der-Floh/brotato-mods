Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem

$RepositoryRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$RepositoryUrl = 'https://github.com/Der-Floh/brotato-mods'
$DefaultSourceDirectory = Join-Path $RepositoryRoot 'src'
$DefaultZipDirectory = Join-Path $RepositoryRoot 'out'
$WorkshopDirectoryName = 'workshop'
$WorkshopUploadDirectoryName = 'workshop-upload'
$MediaDirectoryName = 'media'
$ZipModsRoot = 'mods-unpacked'
$ManifestFileName = 'manifest.json'
# Other authors' mods, kept only for reference and for integration tests; never built, validated or published.
$ThirdPartyDirectoryName = 'ThirdParty'
$BrotatoAppId = '1942280'
$SteamRegistryKey = 'HKCU:\Software\Valve\Steam'

# The steamapps folders of every Steam library on this PC, from Steam's libraryfolders.vdf.
function Get-SteamLibraryFolder {
    $steam = Get-ItemProperty -LiteralPath $SteamRegistryKey -Name SteamPath -ErrorAction SilentlyContinue
    if (-not $steam) { return }
    $libraryFile = Join-Path $steam.SteamPath 'steamapps\libraryfolders.vdf'
    if (-not (Test-Path -LiteralPath $libraryFile)) { return }
    foreach ($match in [regex]::Matches((Get-Content -LiteralPath $libraryFile -Raw), '"path"\s+"([^"]+)"')) {
        Join-Path $match.Groups[1].Value.Replace('\\', '\') 'steamapps'
    }
}

function Get-ModDirectory {
    param(
        [Parameter(Mandatory)][string]$Path,
        [switch]$AllowEmpty
    )

    $modDirectories = @(
        Get-ChildItem -LiteralPath $Path -Directory -ErrorAction SilentlyContinue |
            Where-Object Name -ne $ThirdPartyDirectoryName |
            Get-ChildItem -Directory |
            Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName $ManifestFileName) -PathType Leaf } |
            Sort-Object FullName
    )
    if ($modDirectories.Count -eq 0 -and -not $AllowEmpty) {
        throw "No mods found in $Path (expected <author>/<mod>/$ManifestFileName)"
    }
    $modDirectories
}

function Get-ModAuthor {
    param([Parameter(Mandatory)][System.IO.DirectoryInfo]$ModDirectory)

    $ModDirectory.Parent.Name
}

# Where relative links in a mod's README and changelog point to on GitHub.
function Get-ModLinkBase {
    param([Parameter(Mandatory)][System.IO.DirectoryInfo]$ModDirectory)

    "$RepositoryUrl/blob/main/src/$(Get-ModAuthor -ModDirectory $ModDirectory)/$($ModDirectory.Name)/"
}

function Get-ModItem {
    param([Parameter(Mandatory)][System.IO.DirectoryInfo]$ModDirectory)

    foreach ($item in Get-ChildItem -LiteralPath $ModDirectory.FullName -Recurse) {
        $relativePath = $item.FullName.Substring($ModDirectory.FullName.Length + 1).Replace('\', '/')
        if ($relativePath.Split('/')[0] -eq $MediaDirectoryName) { continue }
        [pscustomobject]@{
            Item         = $item
            RelativePath = $relativePath
        }
    }
}

function Read-ModManifest {
    param([Parameter(Mandatory)][System.IO.DirectoryInfo]$ModDirectory)

    Get-Content -LiteralPath (Join-Path $ModDirectory.FullName $ManifestFileName) -Raw -Encoding UTF8 | ConvertFrom-Json
}

# Packs a mod folder under mods-unpacked/<ModFolderName>/, the layout GML expects; the folder name must be the mod id.
function New-ModZip {
    param(
        [Parameter(Mandatory)][System.IO.DirectoryInfo]$ModDirectory,
        [Parameter(Mandatory)][string]$ZipPath,
        [string]$ModFolderName = $ModDirectory.Name
    )

    $entryRoot = "$ZipModsRoot/$ModFolderName/"
    $archive = [System.IO.Compression.ZipFile]::Open($ZipPath, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        [void]$archive.CreateEntry("$ZipModsRoot/")
        [void]$archive.CreateEntry($entryRoot)
        foreach ($modItem in Get-ModItem -ModDirectory $ModDirectory) {
            $entryName = $entryRoot + $modItem.RelativePath
            if ($modItem.Item.PSIsContainer) {
                [void]$archive.CreateEntry("$entryName/")
            }
            else {
                [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $modItem.Item.FullName, $entryName)
            }
        }
    }
    finally {
        $archive.Dispose()
    }
}
