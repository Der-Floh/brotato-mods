<#
.SYNOPSIS
Converts the README of every mod into the BBCode of its Steam Workshop description.

.DESCRIPTION
Workshop descriptions use Steam's BBCode, so each mod's README.md is converted: headings become [h1] to [h3], tables stay tables, inline code becomes bold and relative links point to the file on GitHub. Each description is written to <OutputDirectory>/<namespace>-<name>.txt, ready to paste into the Workshop item's description; publish-workshop.ps1 uses it for new items. Steam keeps only the first 8000 characters, so longer descriptions are reported.

build.ps1 runs this script after packing the zips. Run it on its own to regenerate only the descriptions.

.PARAMETER SourceDirectory
Folder holding the author folders. Defaults to src/ in the repository root.

.PARAMETER OutputDirectory
Folder the descriptions are written to. Defaults to out/workshop/ in the repository root.

.EXAMPLE
./.vscode/build/workshop-descriptions.ps1
#>
[CmdletBinding()]
param(
    [string]$SourceDirectory,
    [string]$OutputDirectory
)

. (Join-Path $PSScriptRoot 'common.ps1')
. (Join-Path $PSScriptRoot 'bbcode.ps1')

if (-not $SourceDirectory) { $SourceDirectory = $DefaultSourceDirectory }
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $DefaultZipDirectory $WorkshopDirectoryName }

$ReadmeFileName = 'README.md'
$MaxDescriptionLength = 8000

$modDirectories = @(Get-ModDirectory -Path $SourceDirectory -AllowEmpty)
$outputRoot = New-Item -ItemType Directory -Path $OutputDirectory -Force
$utf8 = [System.Text.UTF8Encoding]::new($false)

foreach ($modDirectory in $modDirectories) {
    $readmePath = Join-Path $modDirectory.FullName $ReadmeFileName
    if (-not (Test-Path -LiteralPath $readmePath -PathType Leaf)) {
        throw "$($modDirectory.Name) has no $ReadmeFileName"
    }
    $description = ConvertTo-SteamBBCode -Lines (Read-MarkdownLine $readmePath) -LinkBase (Get-ModLinkBase -ModDirectory $modDirectory)
    $outputPath = Join-Path $outputRoot.FullName "$($modDirectory.Name).txt"
    [System.IO.File]::WriteAllText($outputPath, "$description`n", $utf8)
    Write-Host "Converted: $(Get-ModAuthor -ModDirectory $modDirectory)/$($modDirectory.Name)/$ReadmeFileName -> $($modDirectory.Name).txt"
    if ($description.Length -gt $MaxDescriptionLength) {
        Write-Warning "$($modDirectory.Name): the description has $($description.Length) characters; Steam keeps only the first $MaxDescriptionLength."
    }
}
