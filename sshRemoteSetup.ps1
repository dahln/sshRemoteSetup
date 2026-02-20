#Requires -Version 5.1
# sshRemoteSetup.ps1
# Automates SSH key-based authentication setup on a remote Linux machine.
# Compatible with Windows PowerShell 5.1+ and PowerShell Core 7+
#
# Usage: .\sshRemoteSetup.ps1 <IP_ADDRESS> <USERNAME> <PASSWORD> [SSH_PORT] [DISABLE_PASSWORD_AUTH]
# Example: .\sshRemoteSetup.ps1 192.168.1.100 ubuntu mypassword 22 true

param(
    [Parameter(Mandatory = $true,  Position = 0)] [string]$IpAddress,
    [Parameter(Mandatory = $true,  Position = 1)] [string]$Username,
    [Parameter(Mandatory = $true,  Position = 2)] [string]$Password,
    [Parameter(Mandatory = $false, Position = 3)] [int]$SshPort = 22,
    [Parameter(Mandatory = $false, Position = 4)] [string]$DisablePasswordAuth = "false"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Normalize DisablePasswordAuth
$DisablePasswordAuth = $DisablePasswordAuth.ToLower()
if ($DisablePasswordAuth -ne "true" -and $DisablePasswordAuth -ne "false") {
    Write-Warning "Invalid value for DisablePasswordAuth. Using default value of false."
    $DisablePasswordAuth = "false"
}

Write-Host "Setting up SSH on remote Linux machine..."

# ---------------------------------------------------------------------------
# Ensure Posh-SSH module is available
# ---------------------------------------------------------------------------
if (-not (Get-Module -ListAvailable -Name Posh-SSH)) {
    Write-Host "Posh-SSH module not found. Installing..."
    Install-Module -Name Posh-SSH -Force -Scope CurrentUser -AllowClobber
}
Import-Module Posh-SSH -Force

# ---------------------------------------------------------------------------
# Generate SSH key pair locally
# ---------------------------------------------------------------------------
$sshDir = Join-Path $HOME ".ssh"
if (-not (Test-Path $sshDir)) {
    New-Item -ItemType Directory -Path $sshDir | Out-Null
}

$keyPath = Join-Path $sshDir "id_ed25519_$IpAddress"

if (Test-Path $keyPath) {
    Write-Host "SSH key already exists at $keyPath. Skipping key generation."
} else {
    Write-Host "Generating SSH key pair at $keyPath..."
    $keyGenArgs = @('-t', 'ed25519', '-f', $keyPath, '-N', '', '-q')
    & ssh-keygen @keyGenArgs
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Error generating SSH key pair."
        exit 1
    }
    Write-Host "SSH key pair generated successfully."
}

$publicKeyPath = "$keyPath.pub"
$publicKey = (Get-Content $publicKeyPath -Raw).Trim()

# ---------------------------------------------------------------------------
# Update local ~/.ssh/config
# ---------------------------------------------------------------------------
$sshConfigPath = Join-Path $sshDir "config"
if (-not (Test-Path $sshConfigPath)) {
    New-Item -ItemType File -Path $sshConfigPath | Out-Null
}

$existingConfig = Get-Content $sshConfigPath -Raw -ErrorAction SilentlyContinue
$sshConfigEntry = @"

Host $IpAddress
    IdentityFile $keyPath
    User $Username
    Port $SshPort
"@

if ($existingConfig -and $existingConfig -match "(?m)^Host $([regex]::Escape($IpAddress))$") {
    Write-Host "Host $IpAddress already exists in SSH config."
} else {
    Add-Content -Path $sshConfigPath -Value $sshConfigEntry
    Write-Host "Updated SSH config at $sshConfigPath"
}

# ---------------------------------------------------------------------------
# Copy public key to remote machine and configure sshd
# ---------------------------------------------------------------------------
Write-Host "Copying public key to remote Linux machine..."

$securePassword = ConvertTo-SecureString $Password -AsPlainText -Force
$credential = New-Object System.Management.Automation.PSCredential($Username, $securePassword)

$session = New-SSHSession -ComputerName $IpAddress -Port $SshPort -Credential $credential -AcceptKey:$true
if (-not $session) {
    Write-Error "Failed to establish SSH connection to $IpAddress."
    exit 1
}

try {
    # Create .ssh directory on remote machine
    $cmd = Invoke-SSHCommand -SessionId $session.SessionId -Command "mkdir -p ~/.ssh && chmod 700 ~/.ssh"
    if ($cmd.Output) { Write-Host "Create .ssh directory: $($cmd.Output)" }

    # Ensure authorized_keys exists with proper permissions
    $cmd = Invoke-SSHCommand -SessionId $session.SessionId -Command "touch ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
    if ($cmd.Output) { Write-Host "Create authorized_keys: $($cmd.Output)" }

    # Append public key using base64 encoding to avoid shell escaping issues
    $encodedKey = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($publicKey))
    $cmd = Invoke-SSHCommand -SessionId $session.SessionId -Command "DECODED=\$(echo '$encodedKey' | base64 -d); grep -qF \"\$DECODED\" ~/.ssh/authorized_keys || printf '%s\n' \"\$DECODED\" >> ~/.ssh/authorized_keys"
    if ($cmd.Output) { Write-Host "Append key: $($cmd.Output)" }

    # Report authorized_keys line count
    $cmd = Invoke-SSHCommand -SessionId $session.SessionId -Command "wc -l < ~/.ssh/authorized_keys"
    Write-Host "Authorized keys line count: $($cmd.Output)"

    # Ensure PubkeyAuthentication is enabled in sshd_config
    $cmd = Invoke-SSHCommand -SessionId $session.SessionId -Command "sudo sed -Ei 's/^#?[[:space:]]*PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config"
    if ($cmd.ExitStatus -ne 0) { Write-Error "Failed to enable PubkeyAuthentication: $($cmd.Output)" }
    Write-Host "PubkeyAuthentication enabled."

    Write-Host "Public key copied to remote Linux machine successfully."

    # -----------------------------------------------------------------------
    # Optionally disable password authentication
    # -----------------------------------------------------------------------
    if ($DisablePasswordAuth -eq "true") {
        Write-Host "Disabling password authentication on remote Linux machine..."

        # Backup sshd_config
        $cmd = Invoke-SSHCommand -SessionId $session.SessionId -Command "sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup"
        if ($cmd.ExitStatus -ne 0) { Write-Warning "Could not back up sshd_config: $($cmd.Output)" }

        # Disable password authentication
        $cmd = Invoke-SSHCommand -SessionId $session.SessionId -Command "sudo sed -Ei 's/^#?[[:space:]]*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config"
        if ($cmd.ExitStatus -ne 0) { Write-Error "Failed to disable PasswordAuthentication: $($cmd.Output)" }
        Write-Host "PasswordAuthentication disabled."

        # Restart SSH service (sshd on RHEL/CentOS, ssh on Debian/Ubuntu)
        $cmd = Invoke-SSHCommand -SessionId $session.SessionId -Command "systemctl list-units --type=service | grep -q 'sshd.service' && sudo systemctl restart sshd || sudo systemctl restart ssh"
        if ($cmd.ExitStatus -ne 0) { Write-Error "Failed to restart SSH service: $($cmd.Output)" }
        Write-Host "SSH service restarted."

        Write-Host "Password authentication disabled on remote Linux machine successfully."
    }
} finally {
    Remove-SSHSession -SessionId $session.SessionId | Out-Null
}

Write-Host "SSH setup completed successfully."
