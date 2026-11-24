<#
.SYNOPSIS
Fetches the third-party mods listed in src/ThirdParty/ThirdParty-Mods.csv as zips Godot Mod Loader can load.

.DESCRIPTION
Each row (Name, Author, Url) becomes src/ThirdParty/<Author>/<Name>.zip, which the integration tests load in the sessions that ask for that mod. Where it came from is written next to it as <Name>.zip.source.

- github.com/<owner>/<repo>: the latest release's .zip asset, the file players install. Without a release, the default branch is packed when it has manifest.json at its root.
- github.com/<owner>/<repo>/tree/<ref>/<path>: that folder at <ref>, packed as a mod.
- steamcommunity.com/sharedfiles/filedetails/?id=<id>: the zip Steam downloaded for that Workshop item, so subscribe to it in Steam first.
- Any other host: put the zip there yourself.

Existing zips are kept unless -Update is given. Nothing else in src/ThirdParty is touched; the mods there are references and are never edited.

.PARAMETER Name
Only fetch the rows with these names.

.PARAMETER Update
Fetch again even when the zip already exists.

.EXAMPLE
./tests/fetch-third-party.ps1
#>
[CmdletBinding()]
param(
    [string[]]$Name,
    [switch]$Update
)

. (Join-Path $PSScriptRoot '..\.vscode\build\common.ps1')

$ThirdPartyDirectory = Join-Path $DefaultSourceDirectory $ThirdPartyDirectoryName
$ModListFile = Join-Path $ThirdPartyDirectory 'ThirdParty-Mods.csv'
$SourceSuffix = '.source'
$GitHubUrlPattern = '^https://github\.com/(?<owner>[^/]+)/(?<repo>[^/]+?)(?:\.git)?(?:/tree/(?<ref>[^/]+)/(?<path>.+?))?/?$'
$WorkshopUrlPattern = '^https://steamcommunity\.com/(?:sharedfiles|workshop)/filedetails/\?(?:.*&)?id=(?<id>\d+)'
$ApiRoot = 'https://api.github.com/repos'
$ArchiveRoot = 'https://codeload.github.com'
$RequestHeaders = @{ 'User-Agent' = 'brotato-mods-tests'; Accept = 'application/vnd.github+json' }
if ($env:GITHUB_TOKEN) { $RequestHeaders.Authorization = "Bearer $env:GITHUB_TOKEN" }

function Get-ThirdPartyZipPath {
    param([Parameter(Mandatory)][psobject]$Row)

    Join-Path (Join-Path $ThirdPartyDirectory $Row.Author) "$($Row.Name).zip"
}

function New-TemporaryDirectory {
    New-Item -ItemType Directory -Path (Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString('N')))
}

function Save-Download {
    param([Parameter(Mandatory)][string]$Url, [Parameter(Mandatory)][string]$Path)

    Invoke-WebRequest -Uri $Url -Headers $RequestHeaders -OutFile $Path -UseBasicParsing
}

function Get-LatestReleaseZip {
    param([Parameter(Mandatory)][string]$Owner, [Parameter(Mandatory)][string]$Repo)

    try {
        $release = Invoke-RestMethod -Uri "$ApiRoot/$Owner/$Repo/releases/latest" -Headers $RequestHeaders
    }
    catch {
        if ($_.Exception.Response -and [int]$_.Exception.Response.StatusCode -eq 404) { return $null }
        throw
    }
    $asset = @($release.assets | Where-Object { $_.name -like '*.zip' }) | Select-Object -First 1
    if (-not $asset) { return $null }
    [pscustomobject]@{ Url = $asset.browser_download_url; Source = "release $($release.tag_name)" }
}

function Get-DefaultBranch {
    param([Parameter(Mandatory)][string]$Owner, [Parameter(Mandatory)][string]$Repo)

    (Invoke-RestMethod -Uri "$ApiRoot/$Owner/$Repo" -Headers $RequestHeaders).default_branch
}

function Get-ModId {
    param([Parameter(Mandatory)][string]$ModDirectory)

    $manifest = Get-Content -LiteralPath (Join-Path $ModDirectory $ManifestFileName) -Raw -Encoding UTF8 | ConvertFrom-Json
    "$($manifest.namespace)-$($manifest.name)"
}

# Packs one folder of a GitHub source archive; the zip's folder is named after the mod id, as GML requires.
function New-ZipFromSource {
    param(
        [Parameter(Mandatory)][string]$Owner,
        [Parameter(Mandatory)][string]$Repo,
        [Parameter(Mandatory)][string]$Ref,
        [string]$Path,
        [Parameter(Mandatory)][string]$ZipPath
    )

    $workDirectory = New-TemporaryDirectory
    try {
        $archive = Join-Path $workDirectory.FullName 'source.zip'
        Save-Download -Url "$ArchiveRoot/$Owner/$Repo/zip/$Ref" -Path $archive
        $extracted = Join-Path $workDirectory.FullName 'source'
        Expand-Archive -LiteralPath $archive -DestinationPath $extracted
        $root = @(Get-ChildItem -LiteralPath $extracted -Directory)[0].FullName
        $modDirectory = if ($Path) { Join-Path $root $Path } else { $root }
        if (-not (Test-Path -LiteralPath (Join-Path $modDirectory $ManifestFileName) -PathType Leaf)) {
            throw "No $ManifestFileName in $Owner/$Repo at '$Ref' $(if ($Path) { "under $Path" } else { 'in its root' })."
        }
        New-ModZip -ModDirectory (Get-Item -LiteralPath $modDirectory) -ZipPath $ZipPath -ModFolderName (Get-ModId $modDirectory)
    }
    finally {
        Remove-Item -LiteralPath $workDirectory.FullName -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Save-GitHubMod {
    param([Parameter(Mandatory)][hashtable]$Url, [Parameter(Mandatory)][string]$Partial)

    if ($Url.ref) {
        New-ZipFromSource -Owner $Url.owner -Repo $Url.repo -Ref $Url.ref -Path $Url.path -ZipPath $Partial
        return "tree $($Url.ref)/$($Url.path)"
    }
    $release = Get-LatestReleaseZip -Owner $Url.owner -Repo $Url.repo
    if ($release) {
        Save-Download -Url $release.Url -Path $Partial
        return $release.Source
    }
    $branch = Get-DefaultBranch -Owner $Url.owner -Repo $Url.repo
    New-ZipFromSource -Owner $Url.owner -Repo $Url.repo -Ref $branch -ZipPath $Partial
    "branch $branch"
}

# Steam keeps a subscribed Workshop item's files in steamapps/workshop/content/<app id>/<item id>/.
function Save-WorkshopMod {
    param([Parameter(Mandatory)][string]$ItemId, [Parameter(Mandatory)][string]$Partial)

    foreach ($library in Get-SteamLibraryFolder) {
        $itemDirectory = Join-Path $library "workshop\content\$BrotatoAppId\$ItemId"
        $zips = @(Get-ChildItem -LiteralPath $itemDirectory -Filter '*.zip' -File -ErrorAction SilentlyContinue)
        if ($zips.Count -eq 0) { continue }
        if ($zips.Count -gt 1) { throw "Workshop item $ItemId has $($zips.Count) zips in $itemDirectory; pick one and put it there yourself." }
        Copy-Item -LiteralPath $zips[0].FullName -Destination $Partial
        return "workshop $ItemId, $($zips[0].Name) from $($zips[0].LastWriteTime.ToString('yyyy-MM-dd'))"
    }
    $null
}

function Save-ThirdPartyMod {
    param([Parameter(Mandatory)][psobject]$Row, [Parameter(Mandatory)][string]$ZipPath)

    $partial = "$ZipPath.partial"
    New-Item -ItemType Directory -Path (Split-Path $ZipPath -Parent) -Force | Out-Null
    Remove-Item -LiteralPath $partial -ErrorAction SilentlyContinue

    if ($Row.Url -match $GitHubUrlPattern) {
        $source = Save-GitHubMod -Url @{ owner = $Matches['owner']; repo = $Matches['repo']; ref = $Matches['ref']; path = $Matches['path'] } -Partial $partial
    }
    elseif ($Row.Url -match $WorkshopUrlPattern) {
        $itemId = $Matches['id']
        $source = Save-WorkshopMod -ItemId $itemId -Partial $partial
        if (-not $source) {
            Write-Warning "$($Row.Name): Workshop item $itemId isn't downloaded. Subscribe to it in Steam ($($Row.Url)), let Steam download it, then run this again."
            return
        }
    }
    else {
        Write-Warning "$($Row.Name): $($Row.Url) is neither a GitHub nor a Workshop URL; put the mod's zip at $ZipPath yourself."
        return
    }
    Move-Item -LiteralPath $partial -Destination $ZipPath -Force
    Set-Content -LiteralPath "$ZipPath$SourceSuffix" -Value $source -Encoding UTF8
    Write-Host "Fetched: $($Row.Name) ($source) -> $ZipPath"
}

if (-not (Test-Path -LiteralPath $ModListFile -PathType Leaf)) { throw "No third-party mod list at $ModListFile." }

foreach ($row in Import-Csv -LiteralPath $ModListFile) {
    if ($Name -and $Name -notcontains $row.Name) { continue }
    $zipPath = Get-ThirdPartyZipPath $row
    if ((Test-Path -LiteralPath $zipPath -PathType Leaf) -and -not $Update) {
        Write-Host "Kept: $($row.Name) ($(Get-Content -LiteralPath "$zipPath$SourceSuffix" -ErrorAction SilentlyContinue))"
        continue
    }
    Save-ThirdPartyMod -Row $row -ZipPath $zipPath
}
