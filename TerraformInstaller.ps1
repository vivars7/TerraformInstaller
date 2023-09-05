param (
    [string]$defaultPath = "$env:ProgramFiles\Terraform"
)

# Ensure running as administrator
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Warning "You need to run this script as an Administrator. Restarting as administrator..."
    Start-Process powershell.exe -Verb RunAs -ArgumentList ("-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" $($args -join ' ')")
    exit
}

# Ask user for the path or use default if no input is provided
$path = Read-Host -Prompt "Enter the installation path (Press Enter for default [$defaultPath])"
if (-not $path) {
    $path = $defaultPath
}

# Fetch all available versions
$releasesPage = "https://releases.hashicorp.com/terraform"
try {
    Write-Progress -Status "Fetching Terraform Versions" -Activity "Connecting to HashiCorp..."
    $pageContent = Invoke-RestMethod -Uri $releasesPage
    Write-Progress -Status "Fetching Terraform Versions" -Activity "Done" -Completed
} catch {
    Write-Error "Failed to fetch the Terraform releases page."
    exit
}

# Extract versions and filter out prereleases (alpha, beta, rc)
$versionPattern = "terraform_(\d+\.\d+\.\d+)(?!-(alpha|beta|rc))"
$versions = [regex]::Matches($pageContent, $versionPattern) | ForEach-Object { $_.Groups[1].Value }

# Sort versions and select the latest
$latestVersion = $versions | Where-Object { $_ -as [version] } | Sort-Object { [version]$_ } -Descending | Select-Object -First 1

# Construct download link
$downloadLink = "https://releases.hashicorp.com/terraform/$latestVersion/terraform_${latestVersion}_windows_amd64.zip"

# Download Terraform zip with WebClient and buffering
$downloadPath = "$env:USERPROFILE\Downloads\terraform_${latestVersion}_windows_amd64.zip"

$webClient = New-Object System.Net.WebClient
$webStream = $webClient.OpenRead($downloadLink)
$fileStream = [System.IO.File]::Create($downloadPath)

$bufferSize = 1MB
$buffer = New-Object byte[] $bufferSize

Write-Progress -Status "Downloading Terraform" -Activity "Connecting to HashiCorp..."
try {
    while (($read = $webStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
        $fileStream.Write($buffer, 0, $read)
        # Update the progress bar (e.g., based on download progress)
    }
    Write-Progress -Status "Downloading Terraform" -Activity "Download Complete" -Completed
} finally {
    $fileStream.Close()
    $webStream.Close()
}

# Create installation path if it doesn't exist
if (-not (Test-Path $path)) {
    New-Item -Path $path -ItemType Directory | Out-Null
}

# Unzip to the specified path
Write-Progress -Status "Installing Terraform" -Activity "Extracting files..."
Expand-Archive -Path $downloadPath -DestinationPath $path
Write-Progress -Status "Installing Terraform" -Activity "Installation Complete" -Completed

# Add Terraform path to a new environment variable and add that to the system PATH
$envVarName = "Terraform"
$env:Terraform = $path
[System.Environment]::SetEnvironmentVariable($envVarName, $path, [System.EnvironmentVariableTarget]::Machine)

$env:Path += ";$env:Terraform"
[System.Environment]::SetEnvironmentVariable("Path", $env:Path, [System.EnvironmentVariableTarget]::Machine)

# Check Terraform version
& "$path\terraform.exe" version

# Clean up
Remove-Item -Path $downloadPath
