<#
.SYNOPSIS
Uploads every mod whose version changed to its Steam Workshop item with steamcmd.

.DESCRIPTION
Run it on your PC after publishing the GitHub release. It builds and validates the mods, then compares each mod's version_number with the version .github/workshop-items.json records as uploaded, and uploads the mods that differ:

- Each upload's content folder holds only the mod's zip, because Brotato's mod loader loads every zip in a Workshop item.
- The change note is the mod's changelog.md section for that version, converted to Steam's BBCode, unless -ChangeNote is given.
- An existing item keeps the title, description, preview, tags and visibility set on its Workshop page; -UpdateDescription also replaces its description with the converted README.
- A mod without an item gets a new hidden item, titled with its README heading, with the converted README as description and media/preview.png as preview image when there is one. Set its tags and visibility on its Workshop page, then make it public.

After each successful upload, the item id and the uploaded version are written to .github/workshop-items.json; commit that file. steamcmd logs in with your Steam account: it asks for your password and Steam Guard code the first time, then reuses the saved login, and your Steam client may be signed out while it uploads.

.PARAMETER SteamUser
Your Steam account name. Defaults to the STEAM_USER environment variable.

.PARAMETER Mods
Only consider these mods.

.PARAMETER ChangeNote
The change note for every uploaded mod instead of its changelog section.

.PARAMETER UpdateDescription
Also replace the description of existing items with the converted README.

.PARAMETER Force
Upload even when the item already has the mod's version.

.PARAMETER DryRun
Write the steamcmd item files to out/workshop-upload/ and print what would be uploaded, without running steamcmd or changing workshop-items.json.

.PARAMETER NoBuild
Use the zips of the previous build instead of building and validating again.

.PARAMETER SteamCmd
Path to steamcmd.exe. Defaults to the STEAMCMD environment variable, then steamcmd on the PATH.

.EXAMPLE
./.vscode/build/publish-workshop.ps1 -SteamUser my_account -DryRun
#>
[CmdletBinding()]
param(
    [string]$SteamUser = $env:STEAM_USER,
    [string[]]$Mods,
    [string]$ChangeNote,
    [switch]$UpdateDescription,
    [switch]$Force,
    [switch]$DryRun,
    [switch]$NoBuild,
    [string]$SteamCmd = $env:STEAMCMD
)

. (Join-Path $PSScriptRoot 'common.ps1')
. (Join-Path $PSScriptRoot 'bbcode.ps1')

$WorkshopItemsFile = Join-Path $RepositoryRoot '.github\workshop-items.json'
$UploadDirectory = Join-Path $DefaultZipDirectory $WorkshopUploadDirectoryName
$DescriptionDirectory = Join-Path $DefaultZipDirectory $WorkshopDirectoryName
$ChangelogFileName = 'changelog.md'
$ReadmeFileName = 'README.md'
$PreviewPath = 'media\preview.png'
$HiddenVisibility = '2'
$NewItemId = '0'
$SteamCmdDownloadUrl = 'https://developer.valvesoftware.com/wiki/SteamCMD#Windows'
$SuccessPattern = '(?m)^Success\.'
$PublishedFileIdPattern = '"publishedfileid"\s+"(\d+)"'

function Read-WorkshopItem {
    $items = [ordered]@{}
    if (-not (Test-Path -LiteralPath $WorkshopItemsFile)) { return $items }
    $json = Get-Content -LiteralPath $WorkshopItemsFile -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($property in $json.PSObject.Properties) {
        $items[$property.Name] = [ordered]@{
            'published-file-id' = [string]$property.Value.'published-file-id'
            'uploaded-version'  = [string]$property.Value.'uploaded-version'
        }
    }
    $items
}

function Save-WorkshopItem {
    param([Parameter(Mandatory)][System.Collections.Specialized.OrderedDictionary]$Items)

    $sorted = [ordered]@{}
    foreach ($modId in $Items.Keys | Sort-Object) { $sorted[$modId] = $Items[$modId] }
    [System.IO.File]::WriteAllText($WorkshopItemsFile, ($sorted | ConvertTo-Json -Depth 5) + "`n", [System.Text.UTF8Encoding]::new($false))
}

function Resolve-SteamCmd {
    if ($SteamCmd) {
        if (-not (Test-Path -LiteralPath $SteamCmd -PathType Leaf)) { throw "steamcmd was not found at $SteamCmd." }
        return $SteamCmd
    }
    $command = Get-Command steamcmd -ErrorAction SilentlyContinue
    if (-not $command) { throw "steamcmd was not found. Install it ($SteamCmdDownloadUrl), then pass -SteamCmd, set STEAMCMD or put it on your PATH." }
    $command.Source
}

function Get-ChangelogSection {
    param([Parameter(Mandatory)][System.IO.DirectoryInfo]$ModDirectory, [Parameter(Mandatory)][string]$Version)

    $changelog = Join-Path $ModDirectory.FullName $ChangelogFileName
    if (-not (Test-Path -LiteralPath $changelog)) { return @() }
    $section = [System.Collections.Generic.List[string]]::new()
    $inSection = $false
    foreach ($line in Read-MarkdownLine $changelog) {
        if ($line -match '^##\s') {
            if ($inSection) { break }
            $inSection = $line -match "^##\s+\[?$([regex]::Escape($Version))\]?(\s|$)"
            continue
        }
        if ($inSection) { $section.Add($line) }
    }
    $section.ToArray()
}

function Get-ModTitle {
    param([Parameter(Mandatory)][System.IO.DirectoryInfo]$ModDirectory)

    $heading = Read-MarkdownLine (Join-Path $ModDirectory.FullName $ReadmeFileName) | Where-Object { $_ -match '^#\s+(.+)$' } | Select-Object -First 1
    if ($heading -match '^#\s+(.+)$') { return $Matches[1].Trim() }
    $ModDirectory.Name
}

# Valve's item files escape backslashes; double quotes would end a value early, so they become single quotes.
function ConvertTo-VdfValue {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)

    $Text.Replace('\', '\\').Replace('"', "'")
}

function New-UploadFolder {
    param([Parameter(Mandatory)][string]$ModId, [Parameter(Mandatory)][System.IO.FileInfo]$Zip)

    $folder = Join-Path $UploadDirectory $ModId
    Remove-Item -LiteralPath $folder -Recurse -Force -ErrorAction SilentlyContinue
    $content = New-Item -ItemType Directory -Path (Join-Path $folder 'content') -Force
    Copy-Item -LiteralPath $Zip.FullName -Destination $content.FullName
    [pscustomobject]@{ Folder = $folder; Content = $content.FullName }
}

function Write-ItemFile {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][System.Collections.Specialized.OrderedDictionary]$Fields)

    $lines = @('"workshopitem"', '{')
    foreach ($key in $Fields.Keys) { $lines += "`t`"$key`"`t`"$(ConvertTo-VdfValue $Fields[$key])`"" }
    $lines += '}'
    [System.IO.File]::WriteAllText($Path, ($lines -join "`n") + "`n", [System.Text.UTF8Encoding]::new($false))
}

function New-UploadPlan {
    param([Parameter(Mandatory)][System.IO.DirectoryInfo]$ModDirectory, [Parameter(Mandatory)]$Items)

    $manifest = Read-ModManifest -ModDirectory $ModDirectory
    $modId = $ModDirectory.Name
    $version = [string]$manifest.version_number
    $item = if ($Items.Contains($modId)) { $Items[$modId] } else { $null }
    $itemId = if ($item -and $item['published-file-id']) { $item['published-file-id'] } else { $NewItemId }
    if ($item -and $item['uploaded-version'] -eq $version -and -not $Force) {
        Write-Host "Up to date: $modId $version (item $itemId)"
        return $null
    }
    $zip = Get-ChildItem -LiteralPath (Join-Path $DefaultZipDirectory (Get-ModAuthor -ModDirectory $ModDirectory)) -Filter "$modId-$version.zip" -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $zip) { throw "No zip for $modId $version in out/; build first or leave out -NoBuild." }

    $linkBase = Get-ModLinkBase -ModDirectory $ModDirectory
    $note = if ($ChangeNote) { $ChangeNote } else { ConvertTo-SteamBBCode -Lines (Get-ChangelogSection $ModDirectory $version) -LinkBase $linkBase }
    if (-not $note) { $note = "Version $version" }
    $upload = New-UploadFolder -ModId $modId -Zip $zip
    $fields = [ordered]@{ appid = $BrotatoAppId; publishedfileid = $itemId; contentfolder = $upload.Content; changenote = $note }
    $isNew = $itemId -eq $NewItemId
    if ($isNew -or $UpdateDescription) {
        $fields.description = (Get-Content -LiteralPath (Join-Path $DescriptionDirectory "$modId.txt") -Raw -Encoding UTF8).TrimEnd()
    }
    if ($isNew) {
        $fields.title = Get-ModTitle -ModDirectory $ModDirectory
        $fields.visibility = $HiddenVisibility
        $preview = Join-Path $ModDirectory.FullName $PreviewPath
        if (Test-Path -LiteralPath $preview) { $fields.previewfile = $preview }
        else { Write-Warning "$modId has no $PreviewPath, so its new Workshop item starts without a preview image." }
    }
    $itemFile = Join-Path $upload.Folder 'item.vdf'
    Write-ItemFile -Path $itemFile -Fields $fields
    [pscustomobject]@{ ModId = $modId; Version = $version; ItemId = $itemId; IsNew = $isNew; ItemFile = $itemFile; Note = $note }
}

function Invoke-Upload {
    param([Parameter(Mandatory)][string]$SteamCmdPath, [Parameter(Mandatory)][psobject]$Plan)

    # Windows PowerShell turns a native command's stderr into terminating errors under 'Stop'.
    $ErrorActionPreference = 'Continue'
    $output = & $SteamCmdPath +login $SteamUser +workshop_build_item $Plan.ItemFile +quit 2>&1 | ForEach-Object { "$_" }
    $output | Write-Host
    if (-not ($output -join "`n" -match $SuccessPattern)) { throw "steamcmd did not report success for $($Plan.ModId); see its output above." }
    $written = (Get-Content -LiteralPath $Plan.ItemFile -Raw) -match $PublishedFileIdPattern
    if (-not $written -or $Matches[1] -eq $NewItemId) { throw "steamcmd did not write the item id for $($Plan.ModId) into $($Plan.ItemFile)." }
    $Matches[1]
}

if (-not $DryRun -and -not $SteamUser) { throw 'Pass -SteamUser or set STEAM_USER to your Steam account name.' }
if (-not $NoBuild) {
    & (Join-Path $PSScriptRoot 'build.ps1') | Out-Null
    $global:LASTEXITCODE = 0
    & (Join-Path $PSScriptRoot 'validate.ps1') | Out-Null
    if ($global:LASTEXITCODE) { throw 'The built zips failed validation; run validate.ps1 to see why.' }
}
$uncommitted = try { git -C $RepositoryRoot status --porcelain -- src } catch { $null }
if ($uncommitted) { Write-Warning 'src/ has uncommitted changes, which would be uploaded too.' }

$items = Read-WorkshopItem
$modDirectories = @(Get-ModDirectory -Path $DefaultSourceDirectory -AllowEmpty | Where-Object { -not $Mods -or $Mods -contains $_.Name })
$plans = @(foreach ($modDirectory in $modDirectories) { New-UploadPlan -ModDirectory $modDirectory -Items $items })
if ($plans.Count -eq 0) {
    Write-Host 'Nothing to upload.'
    return
}
foreach ($plan in $plans) {
    $action = if ($plan.IsNew) { 'create a new hidden item' } else { "update item $($plan.ItemId)" }
    Write-Host "$($plan.ModId) $($plan.Version): $action ($($plan.ItemFile))"
}
if ($DryRun) { return }

$steamCmdPath = Resolve-SteamCmd
# Logs in once in the foreground, so password and Steam Guard prompts show; the uploads then reuse the saved login.
& $steamCmdPath +login $SteamUser +quit
foreach ($plan in $plans) {
    $itemId = Invoke-Upload -SteamCmdPath $steamCmdPath -Plan $plan
    $items[$plan.ModId] = [ordered]@{ 'published-file-id' = $itemId; 'uploaded-version' = $plan.Version }
    Save-WorkshopItem -Items $items
    Write-Host "Uploaded: $($plan.ModId) $($plan.Version) -> https://steamcommunity.com/sharedfiles/filedetails/?id=$itemId"
}
