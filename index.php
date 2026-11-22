<?php
/**
 * IT Tools PowerShell web loader.
 * Usage: irm https://get.snapsbilling.com | iex
 * Keep Tools.bat and config.php beside this index.php.
 *
 * Flow when a password is required (set in config.php):
 *   1) irm | iex  -> this returns a small script that PROMPTS for the password
 *   2) that script POSTs the password back here
 *   3) the server checks it, and ONLY if correct returns the real loader
 *      (so Tools.bat is never sent to anyone without the password)
 */
declare(strict_types=1);

date_default_timezone_set('Asia/Riyadh');

header('Content-Type: text/plain; charset=utf-8');
header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');
header('Pragma: no-cache');
header('Expires: 0');
header('X-Content-Type-Options: nosniff');
header("Content-Security-Policy: default-src 'none'; frame-ancestors 'none'");

// Escape a value for a single-quoted PowerShell string.
function ps_q(string $s): string { return str_replace("'", "''", $s); }

// ---- load settings ----
$cfg = [
    'require_password' => false,
    'password'         => '',
    'password_sha256'  => '',
    'prompt_message'   => 'IT Tools - enter the access password',
    'denied_message'   => 'Wrong password - access denied.',
    'max_tries'        => 3,
    'wrong_delay'      => 2,
];
$cfgFile = __DIR__ . DIRECTORY_SEPARATOR . 'config.php';
if (is_file($cfgFile)) {
    $loaded = include $cfgFile;
    if (is_array($loaded)) { $cfg = array_merge($cfg, $loaded); }
}

$host    = $_SERVER['HTTP_HOST'] ?? 'get.snapsbilling.com';
$postUrl = 'https://' . $host . '/';

$hasSecret = ($cfg['password'] !== '') || ($cfg['password_sha256'] !== '');
$needPw    = !empty($cfg['require_password']);

if ($needPw && !$hasSecret) {
    // Fail closed: gate turned on but no password set.
    echo "Write-Host 'IT Tools: access password is required but not configured on the server. Edit config.php.' -ForegroundColor Red\n";
    exit;
}

if ($needPw) {
    $provided = $_POST['pw'] ?? $_GET['pw'] ?? null;

    if ($provided === null) {
        // STAGE 1 - prompt for the password, then re-request with it.
        $maxTries = max(1, (int) $cfg['max_tries']);
        $stage1 = <<<'PS1'
& {
    $ErrorActionPreference = 'Stop'
    for ($i = 1; $i -le __MAXTRIES__; $i++) {
        $sec = Read-Host '__MSG__' -AsSecureString
        $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
        try { $pw = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
        try {
            $resp = Invoke-RestMethod -Uri '__POSTURL__' -Method Post -Body @{ pw = $pw } -TimeoutSec 30
        } catch {
            Write-Host ('IT Tools: could not reach the server - ' + $_.Exception.Message) -ForegroundColor Red
            break
        }
        if ($resp -match '#ITTOOLS-DENIED') {
            if ($i -lt __MAXTRIES__) { Write-Host 'Wrong password. Try again.' -ForegroundColor Yellow }
            else { Write-Host 'Wrong password. Access denied.' -ForegroundColor Red }
            continue
        }
        Invoke-Expression $resp
        break
    }
}
PS1;
        echo strtr($stage1, [
            '__MSG__'      => ps_q((string) $cfg['prompt_message']),
            '__POSTURL__'  => ps_q($postUrl),
            '__MAXTRIES__' => (string) $maxTries,
        ]);
        exit;
    }

    // Verify the provided password.
    $ok = false;
    if ($cfg['password_sha256'] !== '') {
        $ok = hash_equals(strtolower((string) $cfg['password_sha256']), strtolower(hash('sha256', (string) $provided)));
    } elseif ($cfg['password'] !== '') {
        $ok = hash_equals((string) $cfg['password'], (string) $provided);
    }

    if (!$ok) {
        if (!empty($cfg['wrong_delay'])) { sleep((int) $cfg['wrong_delay']); }
        // Marker the prompt script looks for, so it can re-ask.
        echo "#ITTOOLS-DENIED\n";
        echo "Write-Host '" . ps_q((string) $cfg['denied_message']) . "' -ForegroundColor Red\n";
        exit;
    }
    // Correct - fall through and deliver Tools.bat.
}

// ---- STAGE 2 - deliver Tools.bat (verified) ----
$batPath = __DIR__ . DIRECTORY_SEPARATOR . 'Tools.bat';

if (!is_file($batPath) || !is_readable($batPath)) {
    http_response_code(500);
    echo "Write-Host 'IT Tools: Tools.bat is missing or unreadable beside index.php.' -ForegroundColor Red\n";
    exit;
}

$batContents = file_get_contents($batPath);
$sha256 = hash_file('sha256', $batPath);

if ($batContents === false || $sha256 === false) {
    http_response_code(500);
    echo "Write-Host 'IT Tools: unable to read or hash Tools.bat.' -ForegroundColor Red\n";
    exit;
}

$b64 = base64_encode($batContents);
$sha256 = strtoupper($sha256);
$version = date('Y.m.d.His', filemtime($batPath));

$loader = <<<'POWERSHELL'
# -----------------------------------------------------------------
# IT Tools - get.snapsbilling.com
# Build: __VERSION__
# SHA256: __SHA256__
# -----------------------------------------------------------------
& {
    $ErrorActionPreference = 'Stop'
    $ProgressPreference = 'SilentlyContinue'

    $encoded  = '__BASE64__'
    $expected = '__SHA256__'
    $version  = '__VERSION__'

    try {
        $bytes = [Convert]::FromBase64String($encoded)

        $sha = [Security.Cryptography.SHA256]::Create()
        try {
            $actual = ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '')
        }
        finally {
            $sha.Dispose()
        }

        if (-not [string]::Equals($actual, $expected, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'SHA256 verification failed. The downloaded file was not started.'
        }

        # Version-specific folder prevents collision with a previously downloaded build.
        $safeVersion = $version -replace '[^0-9A-Za-z._-]', '_'
        $dir = Join-Path (Join-Path $env:TEMP 'ITTools') $safeVersion
        New-Item -ItemType Directory -Path $dir -Force | Out-Null

        $file = Join-Path $dir 'Tools.bat'
        [IO.File]::WriteAllBytes($file, $bytes)

        $writtenHash = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash
        if (-not [string]::Equals($writtenHash, $expected, [StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue
            throw 'Saved file failed SHA256 verification. It was not started.'
        }

        Write-Host "IT Tools build $version verified." -ForegroundColor Green
        Write-Host 'Starting IT Tools. Approve the Windows UAC prompt to continue.' -ForegroundColor Cyan

        $cmdArgs = '/d /c ""' + $file + '""'
        Start-Process -FilePath $env:ComSpec -ArgumentList $cmdArgs -Verb RunAs
    }
    catch [System.ComponentModel.Win32Exception] {
        if ($_.Exception.NativeErrorCode -eq 1223) {
            Write-Host 'IT Tools: UAC permission was declined. Nothing was started.' -ForegroundColor Yellow
        }
        else {
            Write-Host ('IT Tools: Windows could not start the program: ' + $_.Exception.Message) -ForegroundColor Red
        }
    }
    catch {
        Write-Host ('IT Tools: ' + $_.Exception.Message) -ForegroundColor Red
    }
}
POWERSHELL;

$replacements = [
    '__BASE64__'  => $b64,
    '__SHA256__'  => $sha256,
    '__VERSION__' => $version,
];

echo strtr($loader, $replacements);
