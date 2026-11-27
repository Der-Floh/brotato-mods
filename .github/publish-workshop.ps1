<#
.SYNOPSIS
Uploads the mods of a GitHub release to their Steam Workshop items with steamcmd, using your Steam login on this PC.

.DESCRIPTION
Run it once the Publish Release workflow has attached a release's zips. It lists the repository's GitHub releases, newest first, with the mod versions each one holds and the version .github/workshop-items.json records as uploaded, and asks which release to upload; -Tag picks one without asking. For every mod of that release whose version differs from the recorded one:

- The zip is downloaded from the release and its build provenance is checked with gh attestation verify, so only zips that the release workflow built reach the Workshop.
- The upload's content folder holds only that zip, because Brotato's mod loader loads every zip in a Workshop item.
- The change note is the version's section of the changelog.md inside the zip, converted to Steam's BBCode, unless -ChangeNote is given.
- An existing item keeps the title, description, preview, tags and visibility set on its Workshop page; -UpdateDescription also replaces its description with the README.md inside the zip.
- A mod without an item gets a new hidden item, titled with its README heading, with the README as description and the mod's media/preview.png as preview image when there is one. Set its tags and visibility on its Workshop page, then make it public.

After each upload, the item id and the uploaded version are written to .github/workshop-items.json; commit that file. gh must be signed in to read the releases and check the zips. steamcmd logs in with your Steam account: it asks for your password and Steam Guard code the first time, then reuses the saved login, and your Steam client may be signed out while it uploads.

.PARAMETER Tag
The release to upload, such as v1.2.0, instead of picking one from the list.

.PARAMETER SteamUser
Your Steam account name. Defaults to the STEAM_USER environment variable; without either, the script asks for it.

.PARAMETER Mods
Only consider these mods of the release.

.PARAMETER ChangeNote
The change note for every uploaded mod instead of its changelog section.

.PARAMETER UpdateDescription
Also replace the description of existing items with the converted README.

.PARAMETER Force
Upload even when the item already has the mod's version.

.PARAMETER DryRun
Download and check the zips and write the steamcmd item files to out/workshop-upload/, then print what would be uploaded, without running steamcmd or changing workshop-items.json.

.PARAMETER SteamCmd
Path to steamcmd.exe. Defaults to the STEAMCMD environment variable, then steamcmd on the PATH.

.EXAMPLE
./.github/publish-workshop.ps1 -SteamUser my_account -DryRun
#>
[CmdletBinding()]
param(
    [string]$Tag,
    [string]$SteamUser = $env:STEAM_USER,
    [string[]]$Mods,
    [string]$ChangeNote,
    [switch]$UpdateDescription,
    [switch]$Force,
    [switch]$DryRun,
    [string]$SteamCmd = $env:STEAMCMD
)

. (Join-Path $PSScriptRoot '..\.vscode\build\common.ps1')
. (Join-Path $PSScriptRoot '..\.vscode\build\bbcode.ps1')

$Repository = ([uri]$RepositoryUrl).AbsolutePath.Trim('/')
# The zips are attested by the shared Mod Publish workflow, which lives in this repository.
$AttestationSignerRepository = 'Der-Floh/Der-Floh'
$WorkshopItemsFile = Join-Path $RepositoryRoot '.github\workshop-items.json'
$UploadDirectory = Join-Path $DefaultZipDirectory $WorkshopUploadDirectoryName
$ChangelogFileName = 'changelog.md'
$ReadmeFileName = 'README.md'
$PreviewPath = 'media\preview.png'
$ReleaseListLimit = 20
$MaxDescriptionLength = 8000
$HiddenVisibility = '2'
$NewItemId = '0'
$ZipNamePattern = '^(?<mod>.+)-(?<version>\d+(\.\d+)+(-[0-9A-Za-z.-]+)?)\.zip$'
$WorkshopItemUrl = 'https://steamcommunity.com/sharedfiles/filedetails/?id='
$SteamCmdDownloadUrl = 'https://developer.valvesoftware.com/wiki/SteamCMD#Windows'
$SuccessPattern = 'Committing update\.\.\.\s*Success\.'
$PublishedFileIdPattern = '"publishedfileid"\s+"(\d+)"'

# --- Workshop items ---

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

function Get-UploadState {
    param([Parameter(Mandatory)][psobject]$Mod, [Parameter(Mandatory)]$Items)

    if (-not $Items.Contains($Mod.ModId)) { return 'no Workshop item yet' }
    $uploaded = $Items[$Mod.ModId]['uploaded-version']
    if (-not $uploaded) { return 'Workshop item without a finished upload' }
    if ($uploaded -eq $Mod.Version) { return 'on the Workshop' }
    "Workshop has $uploaded"
}

# --- Releases ---

function Get-ReleaseMod {
    param([AllowEmptyCollection()][object[]]$Assets)

    foreach ($asset in $Assets) {
        if ($asset.name -match $ZipNamePattern) {
            [pscustomobject]@{ ModId = $Matches['mod']; Version = $Matches['version']; AssetName = $asset.name }
        }
    }
}

function Get-Release {
    $json = gh api "repos/$Repository/releases?per_page=$ReleaseListLimit"
    if ($LASTEXITCODE) { throw "gh could not list the releases of $Repository. Sign in with 'gh auth login'." }
    foreach ($release in ($json -join "`n" | ConvertFrom-Json)) {
        if ($release.draft) { continue }
        $releaseMods = @(Get-ReleaseMod $release.assets)
        if ($releaseMods.Count -eq 0) { continue }
        [pscustomobject]@{ Tag = $release.tag_name; Published = ([datetime]$release.published_at).ToLocalTime(); IsPrerelease = $release.prerelease; Mods = $releaseMods }
    }
}

function Write-ReleaseList {
    param([Parameter(Mandatory)][object[]]$Releases, [Parameter(Mandatory)]$Items)

    for ($index = 0; $index -lt $Releases.Count; $index++) {
        $release = $Releases[$index]
        $prerelease = if ($release.IsPrerelease) { ' (prerelease)' } else { '' }
        Write-Host ('{0,3}  {1}  {2:yyyy-MM-dd}{3}' -f ($index + 1), $release.Tag, $release.Published, $prerelease)
        foreach ($mod in $release.Mods) {
            Write-Host ('       {0} {1} ({2})' -f $mod.ModId, $mod.Version, (Get-UploadState -Mod $mod -Items $Items))
        }
    }
}

function Select-Release {
    param([Parameter(Mandatory)][object[]]$Releases, [Parameter(Mandatory)]$Items)

    if ($Tag) {
        $release = $Releases | Where-Object Tag -eq $Tag | Select-Object -First 1
        if (-not $release) { throw "$Repository has no release $Tag with mod zips among its last $ReleaseListLimit releases." }
        return $release
    }
    Write-ReleaseList -Releases $Releases -Items $Items
    $answer = Read-Host 'Release to upload [1]'
    $choice = if ($answer) { $answer -as [int] } else { 1 }
    if (-not $choice -or $choice -lt 1 -or $choice -gt $Releases.Count) { throw "Pick a number from 1 to $($Releases.Count)." }
    $Releases[$choice - 1]
}

function Save-ReleaseZip {
    param([Parameter(Mandatory)][psobject]$Release, [Parameter(Mandatory)][psobject]$Mod, [Parameter(Mandatory)][string]$Destination)

    gh release download $Release.Tag --repo $Repository --pattern $Mod.AssetName --dir $Destination --clobber
    if ($LASTEXITCODE) { throw "gh could not download $($Mod.AssetName) from release $($Release.Tag)." }
    Join-Path $Destination $Mod.AssetName
}

function Assert-Attested {
    param([Parameter(Mandatory)][string]$Zip)

    # Windows PowerShell turns a native command's stderr into terminating errors under 'Stop'.
    $ErrorActionPreference = 'Continue'
    $output = gh attestation verify $Zip --repo $Repository --signer-repo $AttestationSignerRepository 2>&1 | ForEach-Object { "$_" }
    if ($LASTEXITCODE) {
        $output | Write-Host
        throw "$(Split-Path $Zip -Leaf) has no valid attestation from the release workflow of $Repository, so it is not uploaded."
    }
}

# --- Upload plan ---

function Expand-ModDocument {
    param([Parameter(Mandatory)][string]$Zip, [Parameter(Mandatory)][string]$ModId, [Parameter(Mandatory)][string]$Destination)

    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    $archive = [System.IO.Compression.ZipFile]::OpenRead($Zip)
    try {
        foreach ($fileName in $ReadmeFileName, $ChangelogFileName) {
            $entry = $archive.GetEntry("$ZipModsRoot/$ModId/$fileName")
            if ($entry) { [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, (Join-Path $Destination $fileName), $true) }
        }
    }
    finally {
        $archive.Dispose()
    }
}

function Get-ChangelogSection {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Version)

    if (-not (Test-Path -LiteralPath $Path)) { return @() }
    $section = [System.Collections.Generic.List[string]]::new()
    $inSection = $false
    foreach ($line in Read-MarkdownLine $Path) {
        if ($line -match '^##\s') {
            if ($inSection) { break }
            $inSection = $line -match "^##\s+\[?$([regex]::Escape($Version))\]?(\s|$)"
            continue
        }
        if ($inSection) { $section.Add($line) }
    }
    $section.ToArray()
}

function Get-ReadmeTitle {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Fallback)

    $heading = Read-MarkdownLine $Path | Where-Object { $_ -match '^#\s+(.+)$' } | Select-Object -First 1
    if ($heading -match '^#\s+(.+)$') { return $Matches[1].Trim() }
    $Fallback
}

# validate.ps1 requires every mod's namespace, the part of its id before the first '-', to be its author folder.
function Get-ModPath {
    param([Parameter(Mandatory)][string]$ModId)

    "$($ModId.Split('-')[0])/$ModId"
}

# Valve's item files escape backslashes; double quotes would end a value early, so they become single quotes.
function ConvertTo-VdfValue {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)

    $Text.Replace('\', '\\').Replace('"', "'")
}

function Write-ItemFile {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][System.Collections.Specialized.OrderedDictionary]$Fields)

    $lines = @('"workshopitem"', '{')
    foreach ($key in $Fields.Keys) { $lines += "`t`"$key`"`t`"$(ConvertTo-VdfValue $Fields[$key])`"" }
    $lines += '}'
    [System.IO.File]::WriteAllText($Path, ($lines -join "`n") + "`n", [System.Text.UTF8Encoding]::new($false))
}

function Get-Description {
    param([Parameter(Mandatory)][string]$ReadmePath, [Parameter(Mandatory)][string]$LinkBase, [Parameter(Mandatory)][string]$ModId)

    $description = ConvertTo-SteamBBCode -Lines (Read-MarkdownLine $ReadmePath) -LinkBase $LinkBase
    if ($description.Length -gt $MaxDescriptionLength) {
        Write-Warning "$($ModId): the description has $($description.Length) characters; Steam keeps only the first $MaxDescriptionLength."
    }
    $description
}

function New-UploadPlan {
    param([Parameter(Mandatory)][psobject]$Release, [Parameter(Mandatory)][psobject]$Mod, [Parameter(Mandatory)]$Items)

    $item = if ($Items.Contains($Mod.ModId)) { $Items[$Mod.ModId] } else { $null }
    $itemId = if ($item -and $item['published-file-id']) { $item['published-file-id'] } else { $NewItemId }
    if ($item -and $item['uploaded-version'] -eq $Mod.Version -and -not $Force) {
        Write-Host "Up to date: $($Mod.ModId) $($Mod.Version) (item $itemId)"
        return
    }

    $folder = Join-Path $UploadDirectory $Mod.ModId
    Remove-Item -LiteralPath $folder -Recurse -Force -ErrorAction SilentlyContinue
    $content = New-Item -ItemType Directory -Path (Join-Path $folder 'content') -Force
    $zip = Save-ReleaseZip -Release $Release -Mod $Mod -Destination $content.FullName
    Assert-Attested $zip
    $documents = Join-Path $folder 'documents'
    Expand-ModDocument -Zip $zip -ModId $Mod.ModId -Destination $documents
    $readme = Join-Path $documents $ReadmeFileName
    $modPath = Get-ModPath $Mod.ModId
    $linkBase = "$RepositoryUrl/blob/$($Release.Tag)/src/$modPath/"

    $note = if ($ChangeNote) { $ChangeNote } else { ConvertTo-SteamBBCode -Lines (Get-ChangelogSection (Join-Path $documents $ChangelogFileName) $Mod.Version) -LinkBase $linkBase }
    if (-not $note) { $note = "Version $($Mod.Version)" }
    $fields = [ordered]@{ appid = $BrotatoAppId; publishedfileid = $itemId; contentfolder = $content.FullName; changenote = $note }
    $isNew = $itemId -eq $NewItemId
    if (($isNew -or $UpdateDescription) -and (Test-Path -LiteralPath $readme)) {
        $fields.description = Get-Description -ReadmePath $readme -LinkBase $linkBase -ModId $Mod.ModId
    }
    if ($isNew) {
        $fields.title = if (Test-Path -LiteralPath $readme) { Get-ReadmeTitle -Path $readme -Fallback $Mod.ModId } else { $Mod.ModId }
        $fields.visibility = $HiddenVisibility
        $preview = Join-Path (Join-Path $DefaultSourceDirectory $modPath) $PreviewPath
        if (Test-Path -LiteralPath $preview) { $fields.previewfile = $preview }
        else { Write-Warning "$($Mod.ModId) has no $PreviewPath, so its new Workshop item starts without a preview image." }
    }
    $itemFile = Join-Path $folder 'item.vdf'
    Write-ItemFile -Path $itemFile -Fields $fields
    [pscustomobject]@{ ModId = $Mod.ModId; Version = $Mod.Version; ItemId = $itemId; IsNew = $isNew; ItemFile = $itemFile }
}

# --- Upload ---

function Resolve-SteamCmd {
    if ($SteamCmd) {
        if (-not (Test-Path -LiteralPath $SteamCmd -PathType Leaf)) { throw "steamcmd was not found at $SteamCmd." }
        return $SteamCmd
    }
    $command = Get-Command steamcmd -ErrorAction SilentlyContinue
    if (-not $command) { throw "steamcmd was not found. Install it ($SteamCmdDownloadUrl), then pass -SteamCmd, set STEAMCMD or put it on your PATH." }
    $command.Source
}

function Invoke-Upload {
    param([Parameter(Mandatory)][string]$SteamCmdPath, [Parameter(Mandatory)][psobject]$Plan)

    # Windows PowerShell turns a native command's stderr into terminating errors under 'Stop'.
    $ErrorActionPreference = 'Continue'
    # steamcmd writes UTF-8, but captured output is decoded with the console's code page.
    $consoleEncoding = [Console]::OutputEncoding
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    try {
        $output = & $SteamCmdPath +login $SteamUser +workshop_build_item $Plan.ItemFile +quit 2>&1 | ForEach-Object { "$_" }
    }
    finally {
        [Console]::OutputEncoding = $consoleEncoding
    }
    $output | Write-Host
    ($output -join "`n") -match $SuccessPattern
}

# steamcmd writes the id of a new item into the item file as soon as it creates the item.
function Read-ItemId {
    param([Parameter(Mandatory)][string]$ItemFile)

    if ((Get-Content -LiteralPath $ItemFile -Raw) -match $PublishedFileIdPattern) { return $Matches[1] }
    $NewItemId
}

if (-not $DryRun -and -not $SteamUser) { $SteamUser = Read-Host 'Steam account name' }
if (-not $DryRun -and -not $SteamUser) { throw 'Enter your Steam account name, pass -SteamUser or set STEAM_USER.' }

$items = Read-WorkshopItem
$releases = @(Get-Release)
if ($releases.Count -eq 0) { throw "$Repository has no release with mod zips yet. Publish a GitHub release first; its workflow attaches them." }
$release = Select-Release -Releases $releases -Items $items
$releaseMods = @($release.Mods | Where-Object { -not $Mods -or $Mods -contains $_.ModId })
$plans = @(foreach ($mod in $releaseMods) { New-UploadPlan -Release $release -Mod $mod -Items $items })
if ($plans.Count -eq 0) {
    Write-Host 'Nothing to upload.'
    return
}
foreach ($plan in $plans) {
    $action = if ($plan.IsNew) { 'create a new hidden item' } else { "update item $($plan.ItemId)" }
    Write-Host "$($plan.ModId) $($plan.Version) from $($release.Tag): $action ($($plan.ItemFile))"
}
if ($DryRun) { return }

$steamCmdPath = Resolve-SteamCmd
# Logs in once in the foreground, so password and Steam Guard prompts show; the uploads then reuse the saved login.
& $steamCmdPath +login $SteamUser +quit
foreach ($plan in $plans) {
    $succeeded = Invoke-Upload -SteamCmdPath $steamCmdPath -Plan $plan
    $itemId = Read-ItemId $plan.ItemFile
    # A created item is recorded even when its upload failed, so the next run updates it instead of creating another.
    if ($itemId -ne $NewItemId) {
        $items[$plan.ModId] = [ordered]@{ 'published-file-id' = $itemId; 'uploaded-version' = $(if ($succeeded) { $plan.Version } else { '' }) }
        Save-WorkshopItem -Items $items
    }
    if (-not $succeeded) { throw "steamcmd did not report success for $($plan.ModId); see its output above." }
    if ($itemId -eq $NewItemId) { throw "steamcmd did not write the item id for $($plan.ModId) into $($plan.ItemFile)." }
    Write-Host "Uploaded: $($plan.ModId) $($plan.Version) -> $WorkshopItemUrl$itemId"
}
Write-Host 'Commit .github/workshop-items.json.'
