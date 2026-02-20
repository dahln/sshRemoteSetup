# SSH Remote Setup

A .NET 10 File-Based App (Windows) **and a Bash shell script (Linux/macOS)** that automate SSH key-based authentication setup on remote Linux machines. These tools eliminate the need for password authentication and provide a convenient way to initialize SSH connectivity to multiple remote servers.

## Purpose

`sshRemoteSetup` streamlines the process of transitioning from password-based SSH authentication to key-based authentication:
- **Uses password authentication** to initially connect and set up key-based access
- Generates ED25519 SSH key pairs on your local Windows machine
- Uploads public keys to remote Linux machines via the initial password connection
- Configures local SSH config for convenient host access
- **Optionally disables password authentication** after key setup for enhanced security

This workflow is ideal for DevOps, remote server management, and setting up secure SSH access across multiple machines without exposing them to password-based vulnerabilities.

## Requirements

### Windows (.NET Script)
- **.NET 10 SDK** (required for File-Based App compilation and execution)
- **Windows OS** (uses Windows-specific path handling)
- **SSH tools** (`ssh-keygen` must be available in PATH - typically pre-installed on Windows 10/11 with recent updates)
- **Network connectivity** to target remote Linux machines

### Linux / macOS (Shell Script)
- **Bash** (version 4+; required for the `${var,,}` lowercase expansion used for parameter normalisation)
- **ssh-keygen** (typically pre-installed)
- **sshpass** (installed automatically if missing, requires `sudo`; available in standard repos for Ubuntu/Debian and RHEL/CentOS/Fedora)
- **Network connectivity** to target remote Linux machines

## Installation & Setup

1. Clone or download the repository
2. For the .NET script: ensure you have .NET 10 SDK installed
3. For the shell script: make it executable: `chmod +x sshRemoteSetup.sh`

## Usage

### Linux / macOS — Shell Script

```bash
./sshRemoteSetup.sh <IP_ADDRESS> <USERNAME> <PASSWORD> [SSH_PORT] [DISABLE_PASSWORD_AUTH]
```

### Windows — .NET 10 File-Based App

A File-Based App allows you to run a single C# file directly without a project file:

```bash
dotnet run sshRemoteSetup.cs <IP_ADDRESS> <USERNAME> <PASSWORD> [SSH_PORT] [DISABLE_PASSWORD_AUTH]
```

### Parameters

| Parameter | Required | Description | Example |
|-----------|----------|-------------|---------|
| `IP_ADDRESS` | Yes | IP address of the remote Linux machine | `192.168.1.100` |
| `USERNAME` | Yes | Username on the remote machine | `user` |
| `PASSWORD` | Yes | Password for initial SSH connection | `mypassword` |
| `SSH_PORT` | No | SSH port on remote machine (default: 22) | `2222` |
| `DISABLE_PASSWORD_AUTH` | No | Disable password auth after key setup (default: false) | `true` |

### Examples

**Basic usage** - Set up SSH key authentication to a remote server:
```bash
# Linux / macOS
./sshRemoteSetup.sh 192.168.1.100 ubuntu mypassword

# Windows
dotnet run sshRemoteSetup.cs 192.168.1.100 ubuntu mypassword
```

**Custom SSH port** - Connect to a server running SSH on a non-standard port:
```bash
# Linux / macOS
./sshRemoteSetup.sh 192.168.1.100 admin password123 2222

# Windows
dotnet run sshRemoteSetup.cs 192.168.1.100 admin password123 2222
```

**Full security hardening** - Disable password authentication after key setup:
```bash
# Linux / macOS
./sshRemoteSetup.sh 192.168.1.100 root password123 22 true

# Windows
dotnet run sshRemoteSetup.cs 192.168.1.100 root password123 22 true
```

## Authentication Flow

The program follows a secure migration path from password-based to key-based authentication:

1. **Generates SSH Key Pair**: Creates a new ED25519 key pair locally, naming it `id_ed25519_<IP_ADDRESS>` to support multiple remote machines
2. **Creates `.ssh` Directory**: Ensures the `.ssh` directory exists in your user profile
3. **Updates SSH Config**: Adds an entry to your SSH config file for convenient host access
4. **Uses Password Auth to Bootstrap**: **Connects to the remote machine using the provided password** to upload your public key to `~/.ssh/authorized_keys`
5. **Enables Key Authentication**: Configures the remote sshd to accept public key authentication
6. **Optional Password Disabling**: If the `DISABLE_PASSWORD_AUTH` flag is set to `true`, **removes password-based login** on the remote machine, forcing key-based authentication only

**After setup completes**, you'll authenticate using SSH keys instead of passwords on subsequent connections.

## Key Features

- **Password-to-Key migration**: Uses password authentication to bootstrap key-based access
- **Multi-host support**: Generate separate keys for each remote machine
- **Automatic SSH config management**: Simplifies future SSH connections
- **Secure ED25519 keys**: Uses modern cryptography standards
- **Optional hardening**: Disable password authentication after key setup for enhanced security
- **Error handling**: Clear error messages and validation
- **Security-progressive**: Start with password, transition to keys, optionally lock down to keys only

## SSH Config Integration

After successful setup, the tool updates your `~/.ssh/config` file with an entry like:

```
Host 192.168.1.100
    IdentityFile /Users/username/.ssh/id_ed25519_192.168.1.100
    User ubuntu
    Port 22
```

This allows you to simply run `ssh 192.168.1.100` instead of managing keys manually.

## Dependencies

### Shell Script (`sshRemoteSetup.sh`)
- **sshpass** - Enables non-interactive password-based SSH authentication; auto-installed via `apt-get` (Debian/Ubuntu), `dnf` (RHEL 8+/Fedora), or `yum` (RHEL 7/CentOS 7) if not already present.

### .NET Script (`sshRemoteSetup.cs`)
- **SSH.NET 2025.1.0** - Managed SSH client library for .NET
  (Automatically managed via package reference in the code)

## Security Considerations

- Store generated private keys securely
- Only disable password authentication after confirming key-based access works
- The tool requires initial password access to the remote machine
- Remote machine requires `sudo` privileges for sshd configuration changes (when disabling passwords)

## Troubleshooting

- **"ssh-keygen not found"**: Ensure SSH tools are in your system PATH
- **"sshpass not found"**: The script attempts auto-install; if it fails, install manually (`sudo apt-get install sshpass` or `sudo dnf install sshpass`)
- **Connection failed**: Verify IP address, credentials, and firewall settings
- **Permission denied**: Ensure the user has sudo privileges or sshd_config is world-writable
