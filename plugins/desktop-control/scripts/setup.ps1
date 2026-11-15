# Desktop-control setup for Windows: agent-desktop + Orca.
#   -Check     report only, change nothing
#   -SkipOrca  agent-desktop only
# Kept ASCII-only and Windows PowerShell 5.1 compatible, because a fresh machine may have no pwsh 7.
param([switch]$Check, [switch]$SkipOrca)

$ErrorActionPreference = 'Continue'   # native stderr must not abort the run under PS 5.1
$ProgressPreference = 'SilentlyContinue'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

$OrcaRoot   = Join-Path $env:LOCALAPPDATA 'Programs\orca'
$OrcaBin    = Join-Path $OrcaRoot 'resources\bin'
$OrcaCli    = Join-Path $OrcaBin 'orca.exe'
$OrcaApp    = Join-Path $OrcaRoot 'Orca.exe'
$OrcaSkills = @('orca-cli', 'orchestration')
$OrcaSigner = 'SignPath Foundation'
$script:needsYou = New-Object System.Collections.Generic.List[string]
$script:failed = $false

function Row([string]$state, [string]$name, [string]$detail) {
    if ($state -eq 'FAIL') { $script:failed = $true }
    Write-Output ('[{0,-4}] {1,-22} {2}' -f $state, $name, $detail)
}
function Has([string]$cmd) { return [bool](Get-Command $cmd -ErrorAction SilentlyContinue) }
function FromJson($text) { try { return (($text | Out-String) | ConvertFrom-Json) } catch { return $null } }
function Refresh-Path {
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
}
function Orca-Ready {
    if (-not (Test-Path $OrcaCli)) { return $false }
    $s = FromJson (& $OrcaCli status --json 2>$null)
    return [bool]($s -and $s.result.runtime.state -eq 'ready')
}

Write-Output ('desktop-control setup ({0})' -f $(if ($Check) { 'check only' } else { 'install' }))

# --- Windows ---------------------------------------------------------------
$build = [Environment]::OSVersion.Version.Build
if ($build -ge 17763) { Row 'OK' 'Windows' "build $build" }
else { Row 'FAIL' 'Windows' "build $build; agent-desktop needs Windows 10 1809 (17763) or later" }

# --- Node / npm ------------------------------------------------------------
$haveNpm = Has 'npm'
if ($haveNpm) { Row 'OK' 'Node.js / npm' ("node " + (& node -v 2>$null)) }
else {
    Row 'FAIL' 'Node.js / npm' 'not found'
    $script:needsYou.Add('Install Node.js LTS (https://nodejs.org or: winget install OpenJS.NodeJS.LTS), open a new terminal, run setup again.')
}

# --- agent-desktop ---------------------------------------------------------
if (-not (Has 'agent-desktop') -and -not $Check -and $haveNpm) {
    Write-Output '       installing agent-desktop (npm install -g agent-desktop) ...'
    & npm install -g agent-desktop 2>$null | Out-Null
    Refresh-Path
}
if (Has 'agent-desktop') {
    $st = FromJson (& agent-desktop status 2>$null)
    if ($st -and $st.ok) {
        Row 'OK' 'agent-desktop' ("version $($st.data.version), accessibility " + $st.data.permissions.accessibility.state)
        $snap = FromJson (& agent-desktop snapshot --surface taskbar 2>$null)
        if ($snap -and $snap.ok) { Row 'OK' 'agent-desktop snapshot' 'reads the accessibility tree' }
        else {
            $msg = if ($snap) { "$($snap.error.code): $($snap.error.message)" } else { 'no JSON came back' }
            Row 'FAIL' 'agent-desktop snapshot' $msg
        }
    }
    else { Row 'FAIL' 'agent-desktop' '`agent-desktop status` did not return ok' }
}
elseif ($Check) { Row 'MISS' 'agent-desktop' 'not installed' }
else { Row 'FAIL' 'agent-desktop' 'install did not put agent-desktop on PATH' }

# --- Orca ------------------------------------------------------------------
if ($SkipOrca) { Row 'SKIP' 'Orca' 'skipped by -SkipOrca' }
else {
    # 1. app
    if (-not (Test-Path $OrcaCli) -and -not $Check) {
        $dir = Join-Path $env:TEMP ('orca-setup-' + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force $dir | Out-Null
        $exe = Join-Path $dir 'orca-windows-setup.exe'
        try {
            $rel = Invoke-RestMethod 'https://api.github.com/repos/stablyai/orca/releases/latest' -Headers @{ 'User-Agent' = 'desktop-control-setup' }
            $asset = $rel.assets | Where-Object { $_.name -eq 'orca-windows-setup.exe' } | Select-Object -First 1
            if (-not $asset) { throw "release $($rel.tag_name) has no orca-windows-setup.exe" }
            Write-Output ("       downloading Orca {0} ({1} MB) ..." -f $rel.tag_name, [int]($asset.size / 1MB))
            if (Has 'curl.exe') { & curl.exe -L -s -o $exe $asset.browser_download_url }
            else { Invoke-WebRequest $asset.browser_download_url -OutFile $exe -UseBasicParsing }
            if (-not (Test-Path $exe) -or (Get-Item $exe).Length -ne $asset.size) { throw 'download is incomplete' }
            Write-Output '       checking the installer signature (can take a few minutes) ...'
            $sig = Get-AuthenticodeSignature $exe
            if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch [regex]::Escape($OrcaSigner)) {
                throw "installer signature not accepted (status $($sig.Status), signer $($sig.SignerCertificate.Subject)); nothing was run"
            }
            Write-Output '       running the installer silently ...'
            $p = Start-Process $exe -ArgumentList '/S' -PassThru
            if (-not $p.WaitForExit(600000)) { throw 'installer did not finish within 10 minutes' }
        }
        catch { Row 'FAIL' 'Orca install' $_.Exception.Message }
        finally { Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue }
    }
    if (Test-Path $OrcaCli) { Row 'OK' 'Orca app' ("version " + (Get-Item $OrcaApp).VersionInfo.ProductVersion) }
    elseif ($Check) { Row 'MISS' 'Orca app' 'not installed' }

    if (Test-Path $OrcaCli) {
        # 2. runtime (the CLI only works while the app is running)
        if (-not (Orca-Ready) -and -not $Check) {
            Write-Output '       starting the Orca app and waiting for its runtime (up to 3 minutes) ...'
            Start-Process $OrcaApp | Out-Null
            for ($i = 0; $i -lt 60 -and -not (Orca-Ready); $i++) { Start-Sleep -Seconds 3 }
        }
        $ready = Orca-Ready
        if ($ready) { Row 'OK' 'Orca runtime' 'ready' }
        elseif ($Check) { Row 'WARN' 'Orca runtime' 'the Orca app is not running; open it to use orca commands' }
        else {
            Row 'FAIL' 'Orca runtime' 'not ready after 3 minutes'
            $script:needsYou.Add('Open the Orca app, finish its first-run screens, then run setup again.')
        }

        # 3. skills for agents
        $skillDir = Join-Path $env:USERPROFILE '.claude\skills'
        $missing = @($OrcaSkills | Where-Object { -not (Test-Path (Join-Path $skillDir "$_\SKILL.md")) })
        if ($missing.Count -gt 0 -and -not $Check) {
            $a = @('skills', 'install'); foreach ($s in $missing) { $a += @('--skill', $s) }
            & $OrcaCli @a 2>$null | Out-Null
            $missing = @($OrcaSkills | Where-Object { -not (Test-Path (Join-Path $skillDir "$_\SKILL.md")) })
        }
        if ($missing.Count -eq 0) { Row 'OK' 'Orca skills' ($OrcaSkills -join ', ') }
        elseif ($Check) { Row 'MISS' 'Orca skills' ('not installed: ' + ($missing -join ', ')) }
        else { Row 'FAIL' 'Orca skills' ('could not install: ' + ($missing -join ', ')) }

        # 4. orca on the user PATH (what Orca's "orca in other terminals" switch does)
        $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $true)
        $raw = [string]$key.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        $entries = @($raw -split ';' | Where-Object { $_ })
        $onPath = [bool]($entries | Where-Object { [Environment]::ExpandEnvironmentVariables($_).TrimEnd('\') -ieq $OrcaBin })
        if (-not $onPath -and -not $Check) {
            $kind = [Microsoft.Win32.RegistryValueKind]::ExpandString
            if ($raw) { $kind = $key.GetValueKind('Path') }
            $key.SetValue('Path', (($entries + $OrcaBin) -join ';'), $kind)
            try {
                Add-Type -Namespace DesktopControl -Name Env -MemberDefinition '[DllImport("user32.dll", SetLastError=true, CharSet=CharSet.Auto)] public static extern IntPtr SendMessageTimeout(IntPtr h, uint m, UIntPtr w, string l, uint f, uint t, out UIntPtr r);'
                $r = [UIntPtr]::Zero
                [void][DesktopControl.Env]::SendMessageTimeout([IntPtr]0xffff, 0x1A, [UIntPtr]::Zero, 'Environment', 2, 3000, [ref]$r)
            } catch {}
            $onPath = $true
        }
        $key.Close()
        if ($onPath) { Row 'OK' 'orca on PATH' $OrcaBin } else { Row 'MISS' 'orca on PATH' 'not on the user PATH' }

        # 5. computer use engine and Orca's own environment doctor
        if ($ready) {
            $cap = FromJson (& $OrcaCli computer capabilities --json 2>$null)
            if ($cap -and $cap.ok) { Row 'OK' 'Orca computer use' "$($cap.result.provider) $($cap.result.providerVersion)" }
            else { Row 'FAIL' 'Orca computer use' 'capabilities call failed' }
            foreach ($line in (& $OrcaCli vm env doctor 2>$null)) {
                if ($line -match '^(WARN|FAIL)\s+(\S+):\s*(.*)$') {
                    Row 'WARN' "doctor $($Matches[2])" $Matches[3]   # advisory: never fails the setup
                    if ($Matches[2] -eq 'agent.codex') { $script:needsYou.Add('Optional, only for mixing in Codex workers: run  codex login --device-auth') }
                    if ($Matches[2] -eq 'agent.claude') { $script:needsYou.Add('Sign in to Claude: run  claude  once in a terminal, or sign in inside the Orca app.') }
                }
            }
        }
    }
}

# --- summary ---------------------------------------------------------------
Write-Output ''
if (-not $SkipOrca -and (Test-Path $OrcaCli)) {
    $script:needsYou.Add('Optional: pair your phone under "Orca Mobile" in the Orca sidebar.')
    $script:needsYou.Add('New terminals (and a restarted Claude app) see the updated PATH; ones already open do not.')
}
foreach ($n in $script:needsYou) { Write-Output "NEEDS YOU: $n" }
if ($script:failed) { Write-Output 'RESULT: something failed, see the FAIL lines above.'; exit 1 }
Write-Output 'RESULT: ok'
exit 0
