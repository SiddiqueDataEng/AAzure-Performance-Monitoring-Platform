#Requires -Version 5.1
#Requires -Modules Az

<#
.SYNOPSIS
    Deploys Azure Performance Monitoring Platform infrastructure
.DESCRIPTION
    This script deploys the complete Azure Performance Monitoring Platform infrastructure
    including Log Analytics, Application Insights, Data Explorer, Automation Account, and monitoring components.
.PARAMETER SubscriptionId
    Azure subscription ID where resources will be deployed
.PARAMETER ResourceGroupName
    Name of the resource group to create or use
.PARAMETER Location
    Azure region for resource deployment
.PARAMETER EnvironmentName
    Environment name (dev, test, prod)
.PARAMETER NotificationEmail
    Email address for alert notifications
.PARAMETER TemplateFile
    Path to ARM template file
.PARAMETER ParametersFile
    Path to ARM parameters file
.EXAMPLE
    .\Deploy-Infrastructure.ps1 -SubscriptionId "12345678-1234-1234-1234-123456789012" -ResourceGroupName "rg-apmp-prod" -EnvironmentName "prod" -NotificationEmail "admin@company.com"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SubscriptionId,
    
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory = $false)]
    [string]$Location = "East US 2",
    
    [Parameter(Mandatory = $false)]
    [ValidateSet("dev", "test", "prod")]
    [string]$EnvironmentName = "prod",
    
    [Parameter(Mandatory = $true)]
    [string]$NotificationEmail,
    
    [Parameter(Mandatory = $false)]
    [string]$TemplateFile = "$PSScriptRoot\..\ARM-Templates\main-template.json",
    
    [Parameter(Mandatory = $false)]
    [string]$ParametersFile = "$PSScriptRoot\..\ARM-Templates\parameters.json"
)

# Set error action preference
$ErrorActionPreference = "Stop"

# Function to write colored output
function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    Write-Host $Message -ForegroundColor $Color
}

# Function to log messages
function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    Write-ColorOutput $logMessage -Color $(
        switch ($Level) {
            "ERROR" { "Red" }
            "WARNING" { "Yellow" }
            "SUCCESS" { "Green" }
            default { "White" }
        }
    )
}

try {
    Write-Log "Starting Azure Performance Monitoring Platform deployment..." -Level "INFO"
    
    # Check if Azure PowerShell module is installed
    if (-not (Get-Module -ListAvailable -Name Az)) {
        Write-Log "Azure PowerShell module not found. Installing..." -Level "WARNING"
        Install-Module -Name Az -Force -AllowClobber
    }
    
    # Connect to Azure
    Write-Log "Connecting to Azure..." -Level "INFO"
    $context = Get-AzContext
    if (-not $context -or $context.Subscription.Id -ne $SubscriptionId) {
        Connect-AzAccount -SubscriptionId $SubscriptionId
    }
    
    # Set subscription context
    Set-AzContext -SubscriptionId $SubscriptionId
    Write-Log "Using subscription: $($(Get-AzContext).Subscription.Name)" -Level "INFO"
    
    # Create resource group if it doesn't exist
    $resourceGroup = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue
    if (-not $resourceGroup) {
        Write-Log "Creating resource group: $ResourceGroupName" -Level "INFO"
        New-AzResourceGroup -Name $ResourceGroupName -Location $Location -Tag @{
            "Project" = "Azure Performance Monitoring Platform"
            "Environment" = $EnvironmentName
            "CreatedBy" = $env:USERNAME
            "CreatedDate" = (Get-Date).ToString("yyyy-MM-dd")
        }
        Write-Log "Resource group created successfully" -Level "SUCCESS"
    } else {
        Write-Log "Using existing resource group: $ResourceGroupName" -Level "INFO"
    }
    
    # Validate template files exist
    if (-not (Test-Path $TemplateFile)) {
        throw "Template file not found: $TemplateFile"
    }
    
    if (-not (Test-Path $ParametersFile)) {
        throw "Parameters file not found: $ParametersFile"
    }
    
    # Update parameters file with provided values
    Write-Log "Updating deployment parameters..." -Level "INFO"
    $parametersContent = Get-Content $ParametersFile | ConvertFrom-Json
    $parametersContent.parameters.environmentName.value = $EnvironmentName
    $parametersContent.parameters.location.value = $Location
    $parametersContent.parameters.notificationEmail.value = $NotificationEmail
    
    # Create temporary parameters file
    $tempParametersFile = "$env:TEMP\apmp-parameters-$(Get-Date -Format 'yyyyMMddHHmmss').json"
    $parametersContent | ConvertTo-Json -Depth 10 | Set-Content $tempParametersFile
    
    # Deploy ARM template
    Write-Log "Starting ARM template deployment..." -Level "INFO"
    $deploymentName = "APMP-Deployment-$(Get-Date -Format 'yyyyMMddHHmmss')"
    
    $deployment = New-AzResourceGroupDeployment `
        -ResourceGroupName $ResourceGroupName `
        -Name $deploymentName `
        -TemplateFile $TemplateFile `
        -TemplateParameterFile $tempParametersFile `
        -Verbose
    
    if ($deployment.ProvisioningState -eq "Succeeded") {
        Write-Log "Infrastructure deployment completed successfully!" -Level "SUCCESS"
        
        # Display deployment outputs
        Write-Log "Deployment Outputs:" -Level "INFO"
        foreach ($output in $deployment.Outputs.GetEnumerator()) {
            Write-Log "  $($output.Key): $($output.Value.Value)" -Level "INFO"
        }
        
        # Store sensitive outputs in Key Vault
        Write-Log "Storing sensitive configuration in Key Vault..." -Level "INFO"
        $keyVaultName = $deployment.Outputs.keyVaultUri.Value.Split('/')[2].Split('.')[0]
        
        # Store workspace key
        $workspaceKey = ConvertTo-SecureString -String $deployment.Outputs.workspaceKey.Value -AsPlainText -Force
        Set-AzKeyVaultSecret -VaultName $keyVaultName -Name "LogAnalyticsWorkspaceKey" -SecretValue $workspaceKey
        
        # Store Application Insights instrumentation key
        $aiKey = ConvertTo-SecureString -String $deployment.Outputs.applicationInsightsInstrumentationKey.Value -AsPlainText -Force
        Set-AzKeyVaultSecret -VaultName $keyVaultName -Name "ApplicationInsightsInstrumentationKey" -SecretValue $aiKey
        
        # Store storage account connection string
        $storageConnectionString = ConvertTo-SecureString -String $deployment.Outputs.storageAccountConnectionString.Value -AsPlainText -Force
        Set-AzKeyVaultSecret -VaultName $keyVaultName -Name "StorageAccountConnectionString" -SecretValue $storageConnectionString
        
        Write-Log "Configuration stored in Key Vault successfully" -Level "SUCCESS"
        
        # Create deployment summary
        $deploymentSummary = @{
            DeploymentName = $deploymentName
            ResourceGroupName = $ResourceGroupName
            Environment = $EnvironmentName
            Location = $Location
            DeploymentTime = Get-Date
            Status = "Success"
            Outputs = $deployment.Outputs
        }
        
        $summaryFile = "$PSScriptRoot\..\..\Deployment-Summary-$(Get-Date -Format 'yyyyMMddHHmmss').json"
        $deploymentSummary | ConvertTo-Json -Depth 10 | Set-Content $summaryFile
        Write-Log "Deployment summary saved to: $summaryFile" -Level "INFO"
        
    } else {
        throw "Deployment failed with status: $($deployment.ProvisioningState)"
    }
    
    # Clean up temporary files
    if (Test-Path $tempParametersFile) {
        Remove-Item $tempParametersFile -Force
    }
    
    Write-Log "Azure Performance Monitoring Platform deployment completed successfully!" -Level "SUCCESS"
    Write-Log "Next steps:" -Level "INFO"
    Write-Log "1. Configure alert rules using Deploy-AlertRules.ps1" -Level "INFO"
    Write-Log "2. Deploy monitoring dashboards using Deploy-Dashboards.ps1" -Level "INFO"
    Write-Log "3. Set up automation runbooks using Deploy-Runbooks.ps1" -Level "INFO"
    
} catch {
    Write-Log "Deployment failed: $($_.Exception.Message)" -Level "ERROR"
    Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level "ERROR"
    
    # Clean up temporary files
    if (Test-Path $tempParametersFile) {
        Remove-Item $tempParametersFile -Force
    }
    
    exit 1
}