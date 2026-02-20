//https://www.nuget.org/packages/SSH.NET
#:package SSH.NET@2025.1.0
using Renci.SshNet;

// Helper method to execute a command and return exit code and output
(int ExitCode, string Output) ExecuteCommand(string command)
{
    var process = new System.Diagnostics.Process
    {
        StartInfo = new System.Diagnostics.ProcessStartInfo
        {
            FileName = "cmd.exe",
            Arguments = $"/c {command}",
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true,
        }
    };
    process.Start();
    string output = process.StandardOutput.ReadToEnd();
    string error = process.StandardError.ReadToEnd();
    process.WaitForExit();
    string fullOutput = output + error;
    if (!string.IsNullOrEmpty(fullOutput))
        Console.WriteLine($"Output: {fullOutput}");
    return (process.ExitCode, fullOutput);
}


Console.WriteLine("Setting up SSH on remote Linux machine...");


#region Read and validate command line parameters
//No parameters, output usage instructions
if (args.Length == 0)
{
    Console.WriteLine("Usage: dotnet run  sshRemoteSetup.cs <IP_ADDRESS> <USERNAME> <PASSWORD> [SSH_PORT] [DISABLE_PASSWORD_AUTH]");
    Console.WriteLine("Example: dotnet run  sshRemoteSetup.cs 192.168.1.100 user password 22 true");
    return;
}

//Read the IP Address parameter from the command line
if (args.Length < 1)
{
    Console.WriteLine("Usage: sshRemoteSetup <IP_ADDRESS>");
    return;
}
string ipAddress = args[0];

//Read the username parameter from the command line
if (args.Length < 2)
{
    Console.WriteLine("Usage: sshRemoteSetup <IP_ADDRESS> <USERNAME>");
    return;
}
string username = args[1];

//Read the password parameter from the command line
if (args.Length < 3)
{
    Console.WriteLine("Usage: sshRemoteSetup <IP_ADDRESS> <USERNAME> <PASSWORD>");
    return;
}
string password = args[2];

//Read port parameter from command line to specify the SSH port on the remote Linux machine. This is optional, and defaults to 22.
int sshPort = 22;
if (args.Length >= 4)
{
    if (!int.TryParse(args[3], out sshPort))
    {
        Console.WriteLine("Invalid value for SSH port parameter. Using default value of 22.");
        sshPort = 22;
    }
}

//Read parameter from command line to disable password authentication on the remote Linux machine after copying the public key. This is optional, and defaults to false.
bool disablePasswordAuth = false;
if (args.Length >= 5)
{
    if (!bool.TryParse(args[4], out disablePasswordAuth))
    {
        Console.WriteLine("Invalid value for disablePasswordAuth parameter. Using default value of false.");
        disablePasswordAuth = false;
    }
}
#endregion


// On Windows machine, generate an SSH key pair using ssh-keygen, 
// using ED25519 algorithm, and save it to the default location. 
// This program will be ran multiple times, for each remote Linux machine, 
// so we need to ensure the key gen files are not overwritten. 
// We can do this by appending the IP address to the file name.

// Create .ssh directory if it doesn't exist
string sshDir = System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".ssh");
System.IO.Directory.CreateDirectory(sshDir);

string keyPath = System.IO.Path.Combine(sshDir, $"id_ed25519_{ipAddress}");
string keyGenCommand = $"ssh-keygen -t ed25519 -f {keyPath} -N \"\"";
Console.WriteLine($"Generating SSH key pair using command: {keyGenCommand}");
var (keyGenExitCode, keyGenOutput) = ExecuteCommand(keyGenCommand);
if (keyGenExitCode != 0)
{
    Console.WriteLine("Error generating SSH key pair.");
    return;
}
Console.WriteLine("SSH key pair generated successfully.");




//Read the public key from the generated file
string publicKeyPath = $"{keyPath}.pub";
string publicKey = File.ReadAllText(publicKeyPath);

// Update SSH config to include this host and key
string sshConfigPath = System.IO.Path.Combine(sshDir, "config");
string sshConfigEntry = $@"Host {ipAddress}
    IdentityFile {keyPath}
    User {username}
    Port {sshPort}
";

// Read existing config or create if doesn't exist
string existingConfig = File.Exists(sshConfigPath) ? File.ReadAllText(sshConfigPath) : "";

// Check if this host already exists in config
if (!existingConfig.Contains($"Host {ipAddress}"))
{
    // Append the new entry
    File.AppendAllText(sshConfigPath, "\n" + sshConfigEntry);
    Console.WriteLine($"Updated SSH config at {sshConfigPath}");
}
else
{
    Console.WriteLine($"Host {ipAddress} already exists in SSH config");
}




//Use SSH.NET to copy the public key to the remote Linux machine
Console.WriteLine($"Copying public key to remote Linux machine...");
try
{
    using (var sshClient = new SshClient(ipAddress, sshPort, username, password))
    {
        sshClient.Connect();
        
        // Create .ssh directory on remote machine if it doesn't exist
        var createDirCmd = sshClient.CreateCommand("mkdir -p ~/.ssh && chmod 700 ~/.ssh");
        createDirCmd.Execute();
        Console.WriteLine($"Create .ssh directory output: {createDirCmd.Result}");
        
        // Ensure authorized_keys file exists with proper permissions
        var createAuthKeysCmd = sshClient.CreateCommand("touch ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys");
        createAuthKeysCmd.Execute();
        Console.WriteLine($"Create authorized_keys output: {createAuthKeysCmd.Result}");
        
        // Append public key to authorized_keys using printf to handle special characters better
        string publicKeyEscaped = publicKey.Trim().Replace("\"", "\\\"").Replace("$", "\\$").Replace("`", "\\`");
        string authorizedKeysCmd = $"printf '%s\\n' \"{publicKeyEscaped}\" >> ~/.ssh/authorized_keys";
        var appendKeyCmd = sshClient.CreateCommand(authorizedKeysCmd);
        appendKeyCmd.Execute();
        Console.WriteLine($"Append key output: {appendKeyCmd.Result}");
        
        // Verify the key was actually added
        var verifyCmd = sshClient.CreateCommand("cat ~/.ssh/authorized_keys | wc -l");
        verifyCmd.Execute();
        Console.WriteLine($"Authorized keys line count: {verifyCmd.Result}");
        
        // Ensure public key authentication is enabled in sshd_config
        var enableKeyAuthCmd = sshClient.CreateCommand("sudo sed -i 's/^#PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config && sudo sed -i 's/^PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config");
        enableKeyAuthCmd.Execute();
        Console.WriteLine($"Enable PubkeyAuthentication output: {enableKeyAuthCmd.Result}");
        
        sshClient.Disconnect();
    }
}
catch (Exception ex)
{
    Console.WriteLine($"Error copying public key to remote Linux machine: {ex.Message}");
    return;
}
Console.WriteLine("Public key copied to remote Linux machine successfully.");





//Disable password authentication on the remote Linux machine if the parameter is set to true. This will enhance security by only allowing SSH key authentication.
if (disablePasswordAuth)
{
    Console.WriteLine("Disabling password authentication on remote Linux machine.");
    try
    {
        using (var sshClient = new SshClient(ipAddress, sshPort, username, password))
        {
            sshClient.Connect();
            
            // Backup sshd_config and disable password authentication
            var backupCmd = sshClient.CreateCommand("sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup");
            backupCmd.Execute();
            
            // Disable password authentication
            var disableCmd = sshClient.CreateCommand("sudo sed -i 's/^#PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config && sudo sed -i 's/^PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config");
            disableCmd.Execute();
            
            var restartCmd = sshClient.CreateCommand("sudo systemctl restart sshd");
            restartCmd.Execute();
            
            sshClient.Disconnect();
        }
    }
    catch (Exception ex)
    {
        Console.WriteLine($"Error disabling password authentication on remote Linux machine: {ex.Message}");
        return;
    }
    Console.WriteLine("Password authentication disabled on remote Linux machine successfully.");
}




Console.WriteLine("SSH setup completed successfully.");
