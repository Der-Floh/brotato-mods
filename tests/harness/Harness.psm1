. (Join-Path $PSScriptRoot '..\..\.vscode\build\common.ps1')

$BuildScript = Join-Path $RepositoryRoot '.vscode\build\build.ps1'
$HarnessSource = Join-Path $PSScriptRoot 'src'
$BootstrapScript = Join-Path $PSScriptRoot 'bootstrap\mod_loader_store.gd'
$RunDirectory = Join-Path $PSScriptRoot 'run'
$RepoBuildDirectory = Join-Path $RunDirectory 'build\repo'
$HarnessBuildDirectory = Join-Path $RunDirectory 'build\harness'
$TestModsDirectory = Join-Path $RunDirectory 'mods'
$ScreenshotDirectory = Join-Path $RunDirectory 'screenshots'
$SessionFile = Join-Path $RunDirectory 'session.json'
$FingerprintFile = Join-Path $RunDirectory 'real-profile-fingerprint.json'

$HarnessModId = 'der_floh-test_harness'
$GameProcessName = 'Brotato'
$GameExecutableName = 'Brotato.exe'

$TestProfileName = 'Brotato Test'
$RealProfile = Join-Path $env:APPDATA 'Brotato'
$TestProfile = Join-Path $env:APPDATA $TestProfileName
$ModProfilesFile = Join-Path $TestProfile 'mod_user_profiles.json'
$ModConfigsDirectory = Join-Path $TestProfile 'configs'
$BootstrapFolderName = 'harness'
$BootstrapFileName = 'mod_loader_store.gd'

$OverrideName = 'override.cfg'
$OverrideMarker = "; der_floh-test_harness: temporary switch to the $TestProfileName profile"
$OverrideContent = @(
    $OverrideMarker
    '[application]'
    ''
    'config/use_custom_user_dir=true'
    "config/custom_user_dir_name=`"$TestProfileName`""
    ''
    '[autoload]'
    ''
    "ModLoaderStore=`"*user://$BootstrapFolderName/$BootstrapFileName`""
    ''
) -join "`n"

$SteamLaunchVariables = 'SteamAppId', 'SteamGameId'
$GameDirectoryVariable = 'BROTATO_GAME_DIR'
$GameFolderInLibrary = 'common\Brotato'

$TokenHeader = 'X-Harness-Token'
$WindowResolution = '1280x720'
$RequestTimeoutSec = 120
$ProbeTimeoutSec = 2
$StopTimeoutSec = 60
$ExitGraceSec = 20
$PollIntervalMs = 500

# --- Game folder ---

function Test-GameFolder {
    param([Parameter(Mandatory)][string]$Path)

    Test-Path -LiteralPath (Join-Path $Path $GameExecutableName) -PathType Leaf
}

function Find-SteamGameDirectory {
    foreach ($library in Get-SteamLibraryFolder) {
        $candidate = Join-Path $library $GameFolderInLibrary
        if (Test-GameFolder $candidate) { return $candidate }
    }
    $null
}

function Resolve-GameDirectory {
    param([string]$GameDirectory)

    foreach ($candidate in $GameDirectory, [Environment]::GetEnvironmentVariable($GameDirectoryVariable)) {
        if ($candidate) {
            if (-not (Test-GameFolder $candidate)) { throw "$candidate has no $GameExecutableName." }
            return $candidate
        }
    }
    $found = Find-SteamGameDirectory
    if (-not $found) { throw "Brotato wasn't found in your Steam libraries. Pass -GameDirectory or set $GameDirectoryVariable to the folder with $GameExecutableName." }
    $found
}

# --- Game process ---

function Test-GameRunning {
    [bool](Get-Process -Name $GameProcessName -ErrorAction SilentlyContinue)
}

function Assert-GameNotRunning {
    if (Test-GameRunning) {
        throw "Brotato is already running. Close it (or run 'harness.ps1 stop') before starting a test session."
    }
}

function Wait-GameExit {
    $deadline = (Get-Date).AddSeconds($StopTimeoutSec)
    while (Test-GameRunning) {
        if ((Get-Date) -gt $deadline) { return $false }
        Start-Sleep -Milliseconds $PollIntervalMs
    }
    $true
}

function Stop-GameProcess {
    Get-Process -Name $GameProcessName -ErrorAction SilentlyContinue | Stop-Process -Force
    if (-not (Wait-GameExit)) { throw "Brotato could not be closed. Close it yourself, then run 'harness.ps1 stop'." }
}

function Stop-SessionGame {
    param([Parameter(Mandatory)][object]$Session)

    Get-Process -Id $Session.pid -ErrorAction SilentlyContinue | Where-Object ProcessName -eq $GameProcessName | Stop-Process -Force
    if (-not (Wait-GameExit)) { throw "Brotato is still running after $StopTimeoutSec s. Close it, then run 'harness.ps1 stop' again." }
}

function Get-LaunchArgument {
    param([Parameter(Mandatory)][hashtable]$Session)

    @(
        "`"--mods-path=$($TestModsDirectory.Replace('\', '/'))`""
        '--windowed'
        '--resolution', $WindowResolution
        '--audio-driver', 'Dummy'
        "--harness-port=$($Session.port)"
        "--harness-token=$($Session.token)"
        "`"--harness-screenshots=$($ScreenshotDirectory.Replace('\', '/'))`""
    ) -join ' '
}

function Start-GameProcess {
    param([Parameter(Mandatory)][hashtable]$Session)

    # Without these, the game's SteamAPI_RestartAppIfNecessary relaunches it through Steam, without our arguments.
    $previous = @{}
    foreach ($variable in $SteamLaunchVariables) {
        $previous[$variable] = [Environment]::GetEnvironmentVariable($variable)
        [Environment]::SetEnvironmentVariable($variable, $BrotatoAppId)
    }
    try {
        $executable = Join-Path $Session.game_directory $GameExecutableName
        Start-Process -FilePath $executable -WorkingDirectory $Session.game_directory -ArgumentList (Get-LaunchArgument $Session) | Out-Null
    }
    finally {
        foreach ($variable in $SteamLaunchVariables) { [Environment]::SetEnvironmentVariable($variable, $previous[$variable]) }
    }
}

# --- Building and selecting mods ---

# GML names a mod after the folder holding its mod_main.gd inside the zip, not after the zip's file name.
function Get-ZipModId {
    param([Parameter(Mandatory)][System.IO.FileInfo]$Zip)

    $archive = [System.IO.Compression.ZipFile]::OpenRead($Zip.FullName)
    try {
        foreach ($entry in $archive.Entries) {
            if ($entry.FullName -match '^mods-unpacked/([^/]+)/mod_main\.gd$') { return $Matches[1] }
        }
    }
    finally {
        $archive.Dispose()
    }
    throw "$($Zip.FullName) has no mods-unpacked/<mod id>/mod_main.gd, so GML can't load it."
}

function Get-HarnessZip {
    Get-ChildItem -Path $HarnessBuildDirectory -Filter "$HarnessModId-*.zip" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
}

function Invoke-ModBuild {
    # Zips of mods that left src/ would otherwise stay selectable.
    Remove-Item -LiteralPath $RepoBuildDirectory -Recurse -Force -ErrorAction SilentlyContinue
    & $BuildScript -OutputDirectory $RepoBuildDirectory -AllowEmpty 6>$null | Out-Null
    & $BuildScript -SourceDirectory $HarnessSource -OutputDirectory $HarnessBuildDirectory -SkipDescriptions 6>$null | Out-Null
}

function Copy-TestMod {
    param([string[]]$Mods, [string[]]$Extra)

    Remove-Item -LiteralPath $TestModsDirectory -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Path $TestModsDirectory -Force | Out-Null

    $repoZips = @(Get-ChildItem -Path $RepoBuildDirectory -Filter '*.zip' -Recurse -ErrorAction SilentlyContinue)
    $builtIds = @($repoZips | ForEach-Object { Get-ZipModId $_ })
    $missing = @($Mods | Where-Object { $_ -and $builtIds -notcontains $_ })
    if ($missing.Count -gt 0) { throw "No built zip for: $($missing -join ', '). Built: $($builtIds -join ', ')" }

    $selected = if ($Mods) { @($repoZips | Where-Object { $Mods -contains (Get-ZipModId $_) }) } else { $repoZips }
    $harnessZip = Get-HarnessZip
    if (-not $harnessZip) { throw 'The harness zip was not built; start without -NoBuild.' }

    foreach ($zip in @($selected) + @($harnessZip)) { Copy-Item -LiteralPath $zip.FullName -Destination $TestModsDirectory }
    foreach ($zipPath in @($Extra | Where-Object { $_ })) { Copy-Item -LiteralPath (Resolve-Path $zipPath).Path -Destination $TestModsDirectory }

    @(Get-ChildItem -LiteralPath $TestModsDirectory -Filter '*.zip' | ForEach-Object { Get-ZipModId $_ })
}

# --- Test profile ---

function Get-OverrideFile {
    param([Parameter(Mandatory)][string]$GameDirectory)

    Join-Path $GameDirectory $OverrideName
}

function Test-HarnessOverride {
    param([Parameter(Mandatory)][string]$Path)

    (Test-Path -LiteralPath $Path) -and (Get-Content -LiteralPath $Path -TotalCount 1) -eq $OverrideMarker
}

function Assert-NoForeignOverride {
    param([Parameter(Mandatory)][string]$GameDirectory)

    $override = Get-OverrideFile $GameDirectory
    if ((Test-Path -LiteralPath $override) -and -not (Test-HarnessOverride $override)) {
        throw "$override exists and wasn't written by the harness; refusing to replace it."
    }
}

function Write-ProfileSwitch {
    param([Parameter(Mandatory)][string]$GameDirectory)

    $bootstrapFolder = New-Item -ItemType Directory -Path (Join-Path $TestProfile $BootstrapFolderName) -Force
    Copy-Item -LiteralPath $BootstrapScript -Destination (Join-Path $bootstrapFolder.FullName $BootstrapFileName) -Force
    [System.IO.File]::WriteAllText((Get-OverrideFile $GameDirectory), $OverrideContent)
}

function Remove-ProfileSwitch {
    param([Parameter(Mandatory)][string]$GameDirectory)

    $override = Get-OverrideFile $GameDirectory
    if (Test-HarnessOverride $override) { Remove-Item -LiteralPath $override }
}

function Assert-TestProfile {
    param([Parameter(Mandatory)][object]$Status)

    $reported = [System.IO.Path]::GetFullPath($Status.user_data_dir)
    if ($reported -ne [System.IO.Path]::GetFullPath($TestProfile)) {
        throw "The game started in $reported instead of the test profile $TestProfile, so it was closed."
    }
}

# GML keeps a mod disabled in its user profile once it was, so a mod loaded again later would stay off.
function Enable-TestProfileMod {
    if (-not (Test-Path -LiteralPath $ModProfilesFile)) { return }
    $profiles = Get-Content -LiteralPath $ModProfilesFile -Raw | ConvertFrom-Json
    foreach ($userProfile in $profiles.profiles.PSObject.Properties.Value) {
        foreach ($mod in $userProfile.mod_list.PSObject.Properties.Value) {
            $mod | Add-Member -NotePropertyName is_active -NotePropertyValue $true -Force
        }
    }
    [System.IO.File]::WriteAllText($ModProfilesFile, ($profiles | ConvertTo-Json -Depth 10))
}

function Get-ProfileFingerprint {
    $fingerprint = @{}
    foreach ($file in Get-ChildItem -LiteralPath $RealProfile -File -Recurse -ErrorAction SilentlyContinue) {
        $fingerprint[$file.FullName.Substring($RealProfile.Length + 1)] = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
    }
    $fingerprint
}

function Save-ProfileFingerprint {
    Get-ProfileFingerprint | ConvertTo-Json | Set-Content -LiteralPath $FingerprintFile -Encoding UTF8
}

function Compare-ProfileFingerprint {
    if (-not (Test-Path -LiteralPath $FingerprintFile)) { return @() }
    $before = Get-Content -LiteralPath $FingerprintFile -Raw | ConvertFrom-Json
    $after = Get-ProfileFingerprint
    $names = @($before.PSObject.Properties.Name) + @($after.Keys) | Sort-Object -Unique
    @($names | Where-Object { $before.PSObject.Properties[$_] -eq $null -or -not $after.ContainsKey($_) -or $before.$_ -ne $after[$_] })
}

# --- Session and API ---

function Save-Session {
    param([Parameter(Mandatory)][hashtable]$Session)

    $Session | ConvertTo-Json | Set-Content -LiteralPath $SessionFile -Encoding UTF8
}

function Get-Session {
    if (-not (Test-Path -LiteralPath $SessionFile)) { throw "No test session is running. Use 'harness.ps1 start' first." }
    Get-Content -LiteralPath $SessionFile -Raw | ConvertFrom-Json
}

function Get-FreePort {
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    $listener.Start()
    try { $listener.LocalEndpoint.Port } finally { $listener.Stop() }
}

function Wait-HarnessReady {
    param([Parameter(Mandatory)][hashtable]$Session, [Parameter(Mandatory)][int]$TimeoutSec)

    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    $goneSince = $null
    while ((Get-Date) -lt $deadline) {
        try {
            $response = Invoke-HarnessCommand -Name 'status' -Session ([pscustomobject]$Session) -TimeoutSec $ProbeTimeoutSec
            if ($response.ok) { return $response.result }
        }
        catch {
            Write-Verbose "Harness not answering yet: $($_.Exception.Message)"
        }
        if (Test-GameRunning) { $goneSince = $null }
        elseif (-not $goneSince) { $goneSince = Get-Date }
        elseif (((Get-Date) - $goneSince).TotalSeconds -gt $ExitGraceSec) {
            throw "Brotato exited before the harness answered. See 'harness.ps1 log', then run 'harness.ps1 stop'."
        }
        Start-Sleep -Milliseconds $PollIntervalMs
    }
    throw "The harness did not answer within $TimeoutSec s. See 'harness.ps1 log', then run 'harness.ps1 stop'."
}

# --- Exported ---

<#
.SYNOPSIS
Builds the mods, switches to the test profile, launches the game with the chosen mods and waits for the harness API.
#>
function Start-HarnessSession {
    [CmdletBinding()]
    param(
        [string[]]$Mods,
        [string[]]$Extra,
        [switch]$NoBuild,
        [string]$GameDirectory,
        [int]$StartTimeoutSec = 180
    )

    $game = Resolve-GameDirectory $GameDirectory
    Assert-GameNotRunning
    if (Test-Path -LiteralPath $SessionFile) { throw "A test session is still recorded in $SessionFile. Run 'harness.ps1 stop' first." }
    Assert-NoForeignOverride $game
    if (-not $NoBuild) { Invoke-ModBuild }
    $modIds = Copy-TestMod -Mods $Mods -Extra $Extra
    Save-ProfileFingerprint
    Enable-TestProfileMod

    $session = @{ port = Get-FreePort; token = [guid]::NewGuid().ToString('N'); pid = 0; game_directory = $game }
    Save-Session $session
    Write-ProfileSwitch $game
    $ready = $false
    try {
        Start-GameProcess $session
        $status = Wait-HarnessReady -Session $session -TimeoutSec $StartTimeoutSec
        Assert-TestProfile $status
        $ready = $true
    }
    finally {
        if (-not $ready) { Stop-GameProcess }
        Remove-ProfileSwitch $game
    }
    $session.pid = $status.pid
    Save-Session $session
    [pscustomobject]@{ ok = $true; mods = $modIds; status = $status }
}

<#
.SYNOPSIS
Quits the game (killing it if it is frozen), removes a leftover override.cfg and reports whether your real profile stayed unchanged. Also repairs an interrupted session.
#>
function Stop-HarnessSession {
    [CmdletBinding()]
    param([string]$GameDirectory)

    $session = if (Test-Path -LiteralPath $SessionFile) { Get-Session } else { $null }
    $game = if ($session -and $session.PSObject.Properties['game_directory']) { $session.game_directory } else { Resolve-GameDirectory $GameDirectory }
    if ($session) {
        try { Invoke-HarnessCommand -Name 'quit' -Session $session -TimeoutSec $ProbeTimeoutSec | Out-Null }
        catch { Write-Verbose "Quit request failed, the game may already be closed: $($_.Exception.Message)" }
        # A frozen game never handles quit; killing it is safe because it only ever runs in the test profile.
        if (-not (Wait-GameExit)) { Stop-SessionGame $session }
        Remove-Item -LiteralPath $SessionFile
    }
    elseif (Test-GameRunning) {
        throw 'Brotato is running without a recorded test session; leaving it alone.'
    }
    Remove-ProfileSwitch $game
    $changed = @(Compare-ProfileFingerprint)
    [pscustomobject]@{ ok = $true; real_profile_unchanged = ($changed.Count -eq 0); changed_files = $changed }
}

<#
.SYNOPSIS
Sends one command to the harness API of the running session and returns its response ({ok, result} or {ok, error}).
#>
function Invoke-HarnessCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [object]$Arguments = @{},
        [string]$Json,
        [object]$Session,
        [int]$TimeoutSec = $RequestTimeoutSec
    )

    if (-not $Session) { $Session = Get-Session }
    $body = if ($Json) { $Json } else { $Arguments | ConvertTo-Json -Depth 10 -Compress }
    Invoke-RestMethod -Method Post -Uri "http://127.0.0.1:$($Session.port)/$Name" -Headers @{ $TokenHeader = $Session.token } -ContentType 'application/json; charset=utf-8' -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec $TimeoutSec
}

<#
.SYNOPSIS
Returns the last lines of the test profile's godot.log, or of modloader.log with -ModLoader.
#>
function Get-HarnessLog {
    [CmdletBinding()]
    param([int]$Lines = 60, [switch]$ModLoader)

    $file = if ($ModLoader) { 'modloader.log' } else { 'godot.log' }
    Get-Content -LiteralPath (Join-Path $TestProfile "logs\$file") -Tail $Lines
}

<#
.SYNOPSIS
Deletes the test profile's mod configs, so the next session starts every mod with its default settings.
#>
function Clear-HarnessModConfig {
    if (Test-Path -LiteralPath $ModConfigsDirectory) { Remove-Item -LiteralPath $ModConfigsDirectory -Recurse -Force }
}

function Test-HarnessGameRunning { Test-GameRunning }

function Get-HarnessRunDirectory { $RunDirectory }

function Get-HarnessTestProfile { $TestProfile }

Export-ModuleMember -Function Start-HarnessSession, Stop-HarnessSession, Invoke-HarnessCommand, Get-HarnessLog, Clear-HarnessModConfig, Test-HarnessGameRunning, Get-HarnessRunDirectory, Get-HarnessTestProfile
