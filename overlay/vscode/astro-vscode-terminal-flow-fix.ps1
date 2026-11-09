param(
    [ValidateSet('Check', 'Apply', 'Restore')]
    [string]$Action = 'Check',
    [string]$AppRoot
)

# VS Code 1.143.1 terminal ACK boundary repair. No GUI, process termination,
# network operation, product.json edit, or additional runtime dependency.
# Run with Windows PowerShell 5.1 or newer. AppRoot is resources\app, obtained
# explicitly from the VS Code installation being repaired (env.appRoot).
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:AstroFlowVersion = '1.143.1'
$script:AstroFlowCommit = 'e646868227c3e3a9e3f24277c8c7220be42c0be7'
$script:AstroFlowOriginalHash = '15e8cc92ce20c723543d35b57a5d1bee2df79cbd7426c19cdd88db7d2eb0e3e4'
$script:AstroFlowPatchedHash = '4b9b4c79bb43d256a61d434556f4a460d43608d0bef2e43153e00e9e09487264'
$script:AstroFlowRelativeTarget = 'out\vs\platform\terminal\node\ptyHostMain.js'
$script:AstroFlowOldMethod = 'acknowledgeDataEvent(t){this._unacknowledgedCharCount=Math.max(this._unacknowledgedCharCount-t,0),this._logService.trace(`Flow control: Ack ${t} chars (unacknowledged: ${this._unacknowledgedCharCount})`),this._isPtyPaused&&this._unacknowledgedCharCount<5e3&&(this._logService.trace(`Flow control: Resume (${this._unacknowledgedCharCount} < 5000)`),this._ptyProcess?.resume(),this._isPtyPaused=!1)}'
$script:AstroFlowNewMethod = $script:AstroFlowOldMethod.Replace('this._unacknowledgedCharCount<5e3', 'this._unacknowledgedCharCount<=5e3').Replace(' < 5000)', ' <= 5000)')
$script:AstroFlowUtf8 = New-Object System.Text.UTF8Encoding($false, $true)

function Get-AstroFlowHash([byte[]]$Bytes) {
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($algorithm.ComputeHash($Bytes)).Replace('-', '').ToLowerInvariant() }
    finally { $algorithm.Dispose() }
}

function Get-AstroFlowFileHash([string]$Path) {
    return Get-AstroFlowHash ([IO.File]::ReadAllBytes($Path))
}

function Assert-AstroFlowPlainPath([string]$Path) {
    # Do not follow junctions/symlinks into a different installation or backup.
    $item = Get-Item -LiteralPath $Path -Force
    while ($null -ne $item) {
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Reparse-point path is not supported: $($item.FullName)"
        }
        if ($item -is [IO.FileInfo]) { $item = $item.Directory }
        else { $item = $item.Parent }
    }
}

function Get-AstroFlowContext([string]$Root) {
    if ([string]::IsNullOrWhiteSpace($Root)) { throw 'AppRoot must explicitly identify the VS Code resources\app directory.' }
    $rootPath = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    Assert-AstroFlowPlainPath $rootPath
    $target = Join-Path $rootPath $script:AstroFlowRelativeTarget
    Assert-AstroFlowPlainPath $target
    $productPath = Join-Path $rootPath 'product.json'
    $packagePath = Join-Path $rootPath 'package.json'
    Assert-AstroFlowPlainPath $productPath
    Assert-AstroFlowPlainPath $packagePath
    $product = [IO.File]::ReadAllText($productPath) | ConvertFrom-Json
    $package = [IO.File]::ReadAllText($packagePath) | ConvertFrom-Json
    if ($product.version -ne $script:AstroFlowVersion -or $package.version -ne $script:AstroFlowVersion -or $product.commit -ne $script:AstroFlowCommit) {
        throw "Unsupported VS Code version/commit. Expected $script:AstroFlowVersion / $script:AstroFlowCommit."
    }
    # Do not bypass an installation integrity check. This supported build does
    # not checksum ptyHostMain.js; it does checksum the renderer bundle.
    $checksumNames = @($product.checksums.PSObject.Properties | ForEach-Object { $_.Name.Replace('\', '/') })
    if ($checksumNames -contains 'vs/platform/terminal/node/ptyHostMain.js' -or $checksumNames -contains 'out/vs/platform/terminal/node/ptyHostMain.js') {
        throw 'Target is covered by this installation integrity manifest; no patch was applied.'
    }
    $profileHome = [Environment]::GetEnvironmentVariable('USERPROFILE')
    if ([string]::IsNullOrWhiteSpace($profileHome)) { $profileHome = [Environment]::GetFolderPath('UserProfile') }
    if ([string]::IsNullOrWhiteSpace($profileHome) -or -not [IO.Path]::IsPathRooted($profileHome)) { throw 'Cannot resolve the current user home directory.' }
    $profileHome = [IO.Path]::GetFullPath($profileHome)
    Assert-AstroFlowPlainPath $profileHome
    $identity = Get-AstroFlowHash ($script:AstroFlowUtf8.GetBytes($target.ToLowerInvariant()))
    $entry = Join-Path $profileHome ('.astronvim\vscode-runtime-backups\' + $identity)
    return @{
        app_root = $rootPath; target = $target; entry = $entry
        backup = Join-Path $entry 'ptyHostMain.js.original'
        metadata = Join-Path $entry 'metadata.json'
        product_path = $productPath; product_hash = Get-AstroFlowFileHash $productPath
        package_path = $packagePath; package_hash = Get-AstroFlowFileHash $packagePath
    }
}

function Write-AstroFlowNewFile([string]$Path, [byte[]]$Bytes) {
    $stream = New-Object IO.FileStream($Path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try { $stream.Write($Bytes, 0, $Bytes.Length); $stream.Flush($true) }
    finally { $stream.Dispose() }
}

function Write-AstroFlowAtomic([string]$Path, [byte[]]$Bytes) {
    $temporary = Join-Path ([IO.Path]::GetDirectoryName($Path)) ('.astro-flow-' + [Guid]::NewGuid().ToString('N') + '.tmp')
    try {
        Write-AstroFlowNewFile $temporary $Bytes
        if ([IO.File]::Exists($Path)) { [IO.File]::Replace($temporary, $Path, [NullString]::Value) }
        else { [IO.File]::Move($temporary, $Path) }
    }
    finally { if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) } }
}

function Write-AstroFlowMetadata([hashtable]$Context, [hashtable]$Metadata) {
    $json = ConvertTo-Json -InputObject $Metadata -Depth 5
    Write-AstroFlowAtomic $Context.metadata ($script:AstroFlowUtf8.GetBytes($json + "`n"))
}

function Get-AstroFlowMetadata([hashtable]$Context) {
    if (-not [IO.File]::Exists($Context.metadata)) { return $null }
    Assert-AstroFlowPlainPath $Context.metadata
    $metadata = [IO.File]::ReadAllText($Context.metadata) | ConvertFrom-Json
    if ($metadata.schema -ne 1 -or $metadata.target -cne $Context.target -or
        $metadata.original_sha256 -ne $script:AstroFlowOriginalHash -or $metadata.patched_sha256 -ne $script:AstroFlowPatchedHash -or
        $metadata.version -ne $script:AstroFlowVersion -or $metadata.commit -ne $script:AstroFlowCommit) {
        throw 'Backup metadata does not match this exact installation and patch.'
    }
    return $metadata
}

function Assert-AstroFlowBackup([hashtable]$Context) {
    if (-not [IO.File]::Exists($Context.backup)) { throw 'Original backup is missing; refusing to invent or overwrite it.' }
    Assert-AstroFlowPlainPath $Context.backup
    if ((Get-AstroFlowFileHash $Context.backup) -ne $script:AstroFlowOriginalHash) { throw 'Original backup SHA-256 mismatch.' }
}

function Assert-AstroFlowInstallUnchanged([hashtable]$Context) {
    if ((Get-AstroFlowFileHash $Context.product_path) -ne $Context.product_hash -or
        (Get-AstroFlowFileHash $Context.package_path) -ne $Context.package_hash) {
        throw 'VS Code installation metadata changed during the operation.'
    }
}

function Set-AstroFlowTarget([hashtable]$Context, [byte[]]$Bytes, [string]$ExpectedCurrentHash, [string]$ExpectedNewHash) {
    Assert-AstroFlowInstallUnchanged $Context
    Assert-AstroFlowPlainPath $Context.target
    if ((Get-AstroFlowFileHash $Context.target) -ne $ExpectedCurrentHash) { throw 'Target changed; refusing to overwrite another update.' }
    if ((Get-AstroFlowHash $Bytes) -ne $ExpectedNewHash) { throw 'Replacement bytes do not match the approved patch.' }
    Write-AstroFlowAtomic $Context.target $Bytes
    if ((Get-AstroFlowFileHash $Context.target) -ne $ExpectedNewHash) { throw 'Post-write SHA-256 mismatch; no unknown bytes will be overwritten.' }
    Assert-AstroFlowInstallUnchanged $Context
}

function Invoke-AstroFlowPatch([string]$Mode, [string]$Root) {
    $context = Get-AstroFlowContext $Root
    $currentHash = Get-AstroFlowFileHash $context.target
    if ($currentHash -ne $script:AstroFlowOriginalHash -and $currentHash -ne $script:AstroFlowPatchedHash) {
        throw 'Unsupported target SHA-256; the file may have been updated or modified. Nothing was written.'
    }
    if ($Mode -eq 'Check') {
        $managed = $false
        if ([IO.File]::Exists($context.metadata)) {
            $null = Get-AstroFlowMetadata $context
            Assert-AstroFlowBackup $context
            $managed = $true
        }
        return @{ success = $true; action = $Mode; status = $(if ($currentHash -eq $script:AstroFlowPatchedHash) { 'patched' } else { 'needs_patch' }); managed_backup = $managed; target = $context.target; sha256 = $currentHash; backup_directory = $context.entry; version = $script:AstroFlowVersion }
    }

    [IO.Directory]::CreateDirectory($context.entry) | Out-Null
    Assert-AstroFlowPlainPath $context.entry
    $lockPath = Join-Path $context.entry 'operation.lock'
    if ([IO.File]::Exists($lockPath)) { Assert-AstroFlowPlainPath $lockPath }
    # Exclusive handle, immediate conflict failure. No retries or timeout extension.
    $operationLock = New-Object IO.FileStream($lockPath, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    try {
        $currentHash = Get-AstroFlowFileHash $context.target
        $previous = Get-AstroFlowMetadata $context
        if ($currentHash -eq $script:AstroFlowPatchedHash) {
            if ($null -eq $previous) { throw 'Patch is present without matching managed metadata; no backup or file was changed.' }
            Assert-AstroFlowBackup $context
            if ($Mode -eq 'Apply') {
                $status = 'already_applied'
                if ($previous.phase -ne 'applied') {
                    $recovered = @{}
                    foreach ($property in $previous.PSObject.Properties) { $recovered[$property.Name] = $property.Value }
                    $recovered.phase = 'applied'
                    $recovered.updated_utc = [DateTime]::UtcNow.ToString('o')
                    Write-AstroFlowMetadata $context $recovered
                    $status = 'recovered_applied'
                }
                return @{ success = $true; action = $Mode; status = $status; target = $context.target; sha256 = $currentHash; backup_directory = $context.entry; restart_required = $true }
            }
        }
        elseif ($currentHash -eq $script:AstroFlowOriginalHash) {
            if ($Mode -eq 'Restore') { return @{ success = $true; action = $Mode; status = 'already_original'; target = $context.target; sha256 = $currentHash; backup_directory = $context.entry } }
        }
        else { throw 'Target changed while acquiring the operation lock. Nothing was written.' }

        $metadata = @{
            schema = 1; target = $context.target; app_root = $context.app_root
            version = $script:AstroFlowVersion; commit = $script:AstroFlowCommit
            original_sha256 = $script:AstroFlowOriginalHash; patched_sha256 = $script:AstroFlowPatchedHash
            phase = 'prepared'; updated_utc = [DateTime]::UtcNow.ToString('o')
        }
        if ($Mode -eq 'Apply') {
            $original = [IO.File]::ReadAllBytes($context.target)
            if ((Get-AstroFlowHash $original) -ne $script:AstroFlowOriginalHash) { throw 'Original changed before backup.' }
            $text = $script:AstroFlowUtf8.GetString($original)
            $first = $text.IndexOf($script:AstroFlowOldMethod, [StringComparison]::Ordinal)
            if ($first -lt 0 -or $text.IndexOf($script:AstroFlowOldMethod, $first + 1, [StringComparison]::Ordinal) -ge 0) { throw 'Expected exactly one approved recovery method.' }
            $patched = $script:AstroFlowUtf8.GetBytes($text.Replace($script:AstroFlowOldMethod, $script:AstroFlowNewMethod))
            if ((Get-AstroFlowHash $patched) -ne $script:AstroFlowPatchedHash) { throw 'Computed patch SHA-256 mismatch.' }
            if (-not [IO.File]::Exists($context.backup)) { Write-AstroFlowNewFile $context.backup $original }
            Assert-AstroFlowBackup $context
            Write-AstroFlowMetadata $context $metadata
            try {
                Set-AstroFlowTarget $context $patched $script:AstroFlowOriginalHash $script:AstroFlowPatchedHash
                $metadata.phase = 'applied'
                Write-AstroFlowMetadata $context $metadata
            }
            catch {
                $failure = $_
                # Roll back only our exact committed bytes. A newer/third-party
                # file is preserved and the immutable home backup remains.
                if ((Get-AstroFlowFileHash $context.target) -eq $script:AstroFlowPatchedHash) {
                    Set-AstroFlowTarget $context ([IO.File]::ReadAllBytes($context.backup)) $script:AstroFlowPatchedHash $script:AstroFlowOriginalHash
                }
                throw $failure
            }
            return @{ success = $true; action = $Mode; status = 'applied'; target = $context.target; sha256 = $script:AstroFlowPatchedHash; backup_directory = $context.entry; restart_required = $true }
        }

        Assert-AstroFlowBackup $context
        $metadata.phase = 'restore_prepared'
        Write-AstroFlowMetadata $context $metadata
        Set-AstroFlowTarget $context ([IO.File]::ReadAllBytes($context.backup)) $script:AstroFlowPatchedHash $script:AstroFlowOriginalHash
        $metadata.phase = 'restored'
        Write-AstroFlowMetadata $context $metadata
        return @{ success = $true; action = $Mode; status = 'restored'; target = $context.target; sha256 = $script:AstroFlowOriginalHash; backup_directory = $context.entry; restart_required = $true }
    }
    finally { $operationLock.Dispose() }
}

# Dot-sourcing exposes the same transaction functions for isolated failure
# injection tests; it performs no installation or backup operation.
if ($MyInvocation.InvocationName -eq '.') { return }
try {
    Invoke-AstroFlowPatch $Action $AppRoot | ConvertTo-Json -Depth 6
    exit 0
}
catch {
    @{ success = $false; action = $Action; error = $_.Exception.Message; status = 'failed' } | ConvertTo-Json -Depth 6
    exit 1
}
