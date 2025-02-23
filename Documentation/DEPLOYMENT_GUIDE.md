# 🚀 Azure Performance Monitoring Platform - Deployment Guide

## 📋 Table of Contents

1. [Prerequisites](#prerequisites)
2. [Quick Start Deployment](#quick-start-deployment)
3. [Detailed Deployment Steps](#detailed-deployment-steps)
4. [Configuration](#configuration)
5. [Validation](#validation)
6. [Post-Deployment Tasks](#post-deployment-tasks)
7. [Troubleshooting](#troubleshooting)
8. [Maintenance](#maintenance)

---

## 🔧 Prerequisites

### Azure Requirements
- **Azure Subscription** with appropriate permissions
- **Resource Group** creation permissions
- **Contributor** or **Owner** role on the subscription
- **Azure CLI** or **Azure PowerShell** installed locally

### Software Requirements
- **PowerShell 5.1** or later (Windows) / **PowerShell Core 7.0+** (Cross-platform)
- **Azure PowerShell Module** (Az module)
- **Git** for source code management
- **Visual Studio Code** (recommended for editing)

### Permissions Required
```
Microsoft.Resources/subscriptions/resourceGroups/*
Microsoft.OperationalInsights/*
Microsoft.Insights/*
Microsoft.Kusto/*
Microsoft.Automation/*
Microsoft.Storage/*
Microsoft.KeyVault/*
Microsoft.Authorization/roleAssignments/*
```

### Resource Quotas
Ensure your subscription has sufficient quotas for:
- **Log Analytics Workspaces**: 1 per environment
- **Application Insights**: 1 per environment
- **Data Explorer Clusters**: 1 per environment
- **Automation Accounts**: 1 per environment
- **Storage Accounts**: 1 per environment
- **Key Vaults**: 1 per environment

---

## ⚡ Quick Start Deployment

### Option 1: One-Click Deployment (Recommended)

```powershell
# Clone the repository
git clone https://github.com/your-org/azure-performance-monitoring-platform.git
cd azure-performance-monitoring-platform/Azure-Performance-Monitoring-Platform

# Run the quick deployment script
.\Infrastructure\PowerShell\Deploy-Infrastructure.ps1 `
    -SubscriptionId "your-subscription-id" `
    -ResourceGroupName "rg-apmp-prod" `
    -EnvironmentName "prod" `
    -NotificationEmail "admin@yourcompany.com"
```

### Option 2: Azure DevOps Pipeline Deployment

1. **Import the repository** into your Azure DevOps project
2. **Create a service connection** to your Azure subscription
3. **Update pipeline variables** in `CI-CD/Azure-DevOps/azure-pipelines.yml`
4. **Run the pipeline** to deploy automatically

### Option 3: Manual ARM Template Deployment

```bash
# Using Azure CLI
az deployment group create \
  --resource-group rg-apmp-prod \
  --template-file Infrastructure/ARM-Templates/main-template.json \
  --parameters Infrastructure/ARM-Templates/parameters.json \
  --parameters notificationEmail=admin@yourcompany.com
```

---

## 📖 Detailed Deployment Steps

### Step 1: Environment Preparation

1. **Create Resource Group**
```powershell
# Connect to Azure
Connect-AzAccount
Set-AzContext -SubscriptionId "your-subscription-id"

# Create resource group
New-AzResourceGroup -Name "rg-apmp-prod" -Location "East US 2" -Tag @{
    "Project" = "Azure Performance Monitoring Platform"
    "Environment" = "Production"
    "Owner" = "Platform Team"
}
```

2. **Validate Prerequisites**
```powershell
# Check Azure PowerShell version
Get-Module -ListAvailable Az | Select-Object Name, Version

# Verify permissions
Get-AzRoleAssignment -SignInName (Get-AzContext).Account.Id | Where-Object {$_.RoleDefinitionName -in @("Owner", "Contributor")}

# Check resource quotas
Get-AzVMUsage -Location "East US 2" | Where-Object {$_.Name.Value -like "*workspace*"}
```

### Step 2: Infrastructure Deployment

1. **Deploy Core Infrastructure**
```powershell
# Navigate to the project directory
cd "Azure-Performance-Monitoring-Platform"

# Update parameters file with your values
$parametersFile = "Infrastructure\ARM-Templates\parameters.json"
$parameters = Get-Content $parametersFile | ConvertFrom-Json
$parameters.parameters.notificationEmail.value = "your-email@company.com"
$parameters.parameters.environmentName.value = "prod"
$parameters | ConvertTo-Json -Depth 10 | Set-Content $parametersFile

# Deploy infrastructure
.\Infrastructure\PowerShell\Deploy-Infrastructure.ps1 `
    -SubscriptionId "your-subscription-id" `
    -ResourceGroupName "rg-apmp-prod" `
    -EnvironmentName "prod" `
    -NotificationEmail "your-email@company.com"
```

2. **Monitor Deployment Progress**
```powershell
# Check deployment status
Get-AzResourceGroupDeployment -ResourceGroupName "rg-apmp-prod" | Select-Object DeploymentName, ProvisioningState, Timestamp

# View deployment logs
Get-AzLog -ResourceGroup "rg-apmp-prod" -StartTime (Get-Date).AddHours(-1) | Where-Object {$_.OperationName -like "*deployment*"}
```

### Step 3: Monitoring Components Deployment

1. **Deploy Alert Rules**
```powershell
# Get workspace and action group IDs
$workspace = Get-AzOperationalInsightsWorkspace -ResourceGroupName "rg-apmp-prod" | Where-Object {$_.Name -like "*apmp*"}
$actionGroup = Get-AzActionGroup -ResourceGroupName "rg-apmp-prod" | Where-Object {$_.Name -like "*apmp*"}

# Deploy alert rules
New-AzResourceGroupDeployment `
    -ResourceGroupName "rg-apmp-prod" `
    -Name "APMP-AlertRules-$(Get-Date -Format 'yyyyMMddHHmmss')" `
    -TemplateFile "Monitoring\Alert-Rules\performance-alert-rules.json" `
    -workspaceResourceId $workspace.ResourceId `
    -actionGroupResourceId $actionGroup.Id `
    -environmentName "prod"
```

2. **Deploy Performance Dashboard**
```powershell
# Deploy Azure Workbook
$workbookContent = Get-Content "Monitoring\Dashboards\performance-dashboard.json" -Raw
$workbookName = "APMP-Performance-Dashboard-prod"

# Create workbook (requires Azure CLI)
az monitor app-insights workbook create `
    --resource-group "rg-apmp-prod" `
    --name $workbookName `
    --display-name "Azure Performance Monitoring Platform Dashboard" `
    --serialized-data $workbookContent `
    --category "performance"
```

### Step 4: Automation Deployment

1. **Deploy Runbooks**
```powershell
# Get automation account
$automationAccount = Get-AzAutomationAccount -ResourceGroupName "rg-apmp-prod" | Where-Object {$_.AutomationAccountName -like "*apmp*"}

# Import health check runbook
Import-AzAutomationRunbook `
    -ResourceGroupName "rg-apmp-prod" `
    -AutomationAccountName $automationAccount.AutomationAccountName `
    -Name "APMP-Health-Check-Automation" `
    -Type PowerShell `
    -Path "Automation\Runbooks\Health-Check-Automation.ps1" `
    -Description "Automated health check runbook for APMP"

# Publish runbook
Publish-AzAutomationRunbook `
    -ResourceGroupName "rg-apmp-prod" `
    -AutomationAccountName $automationAccount.AutomationAccountName `
    -Name "APMP-Health-Check-Automation"
```

2. **Create Automation Schedules**
```powershell
# Create schedule for health checks
New-AzAutomationSchedule `
    -ResourceGroupName "rg-apmp-prod" `
    -AutomationAccountName $automationAccount.AutomationAccountName `
    -Name "APMP-Health-Check-Schedule" `
    -Description "Runs health checks every 15 minutes" `
    -StartTime (Get-Date).AddMinutes(10) `
    -Interval 15 `
    -Frequency Minute

# Link runbook to schedule
Register-AzAutomationScheduledRunbook `
    -ResourceGroupName "rg-apmp-prod" `
    -AutomationAccountName $automationAccount.AutomationAccountName `
    -RunbookName "APMP-Health-Check-Automation" `
    -ScheduleName "APMP-Health-Check-Schedule" `
    -Parameters @{
        WorkspaceId = $workspace.CustomerId
        SubscriptionId = "your-subscription-id"
        ResourceGroupName = "rg-apmp-prod"
    }
```

---

## ⚙️ Configuration

### Log Analytics Workspace Configuration

1. **Configure Data Retention**
```powershell
# Set retention to 90 days
Set-AzOperationalInsightsWorkspace `
    -ResourceGroupName "rg-apmp-prod" `
    -Name $workspace.Name `
    -RetentionInDays 90
```

2. **Enable Diagnostic Settings**
```powershell
# Enable diagnostics for all resources
$resources = Get-AzResource -ResourceGroupName "rg-apmp-prod"
foreach ($resource in $resources) {
    Set-AzDiagnosticSetting `
        -ResourceId $resource.ResourceId `
        -WorkspaceId $workspace.ResourceId `
        -Enabled $true `
        -Name "APMP-Diagnostics"
}
```

### Application Insights Configuration

1. **Configure Sampling**
```powershell
# Set sampling rate to 100% for production monitoring
$appInsights = Get-AzApplicationInsights -ResourceGroupName "rg-apmp-prod" | Where-Object {$_.Name -like "*apmp*"}
# Note: Sampling configuration is typically done in application code
```

2. **Configure Alerts**
```powershell
# Additional custom alerts can be configured here
# Example: High error rate alert
New-AzMetricAlertRuleV2 `
    -ResourceGroupName "rg-apmp-prod" `
    -Name "APMP-High-Error-Rate" `
    -Description "Alert when error rate exceeds 5%" `
    -Severity 1 `
    -WindowSize (New-TimeSpan -Minutes 5) `
    -Frequency (New-TimeSpan -Minutes 1) `
    -TargetResourceId $appInsights.Id `
    -Condition (New-AzMetricAlertRuleV2Criteria -MetricName "requests/failed" -Operator GreaterThan -Threshold 5)
```

### Key Vault Configuration

1. **Store Sensitive Configuration**
```powershell
$keyVault = Get-AzKeyVault -ResourceGroupName "rg-apmp-prod" | Where-Object {$_.VaultName -like "*apmp*"}

# Store workspace key
$workspaceKey = (Get-AzOperationalInsightsWorkspaceSharedKey -ResourceGroupName "rg-apmp-prod" -Name $workspace.Name).PrimarySharedKey
Set-AzKeyVaultSecret -VaultName $keyVault.VaultName -Name "LogAnalyticsWorkspaceKey" -SecretValue (ConvertTo-SecureString $workspaceKey -AsPlainText -Force)

# Store Application Insights instrumentation key
$aiKey = (Get-AzApplicationInsights -ResourceGroupName "rg-apmp-prod" -Name $appInsights.Name).InstrumentationKey
Set-AzKeyVaultSecret -VaultName $keyVault.VaultName -Name "ApplicationInsightsInstrumentationKey" -SecretValue (ConvertTo-SecureString $aiKey -AsPlainText -Force)
```

---

## ✅ Validation

### Infrastructure Validation

1. **Verify Resource Deployment**
```powershell
# Check all resources are deployed
$expectedResources = @(
    "Microsoft.OperationalInsights/workspaces",
    "Microsoft.Insights/components",
    "Microsoft.Kusto/clusters",
    "Microsoft.Automation/automationAccounts",
    "Microsoft.Storage/storageAccounts",
    "Microsoft.KeyVault/vaults",
    "Microsoft.Insights/actionGroups"
)

$deployedResources = Get-AzResource -ResourceGroupName "rg-apmp-prod" | Group-Object ResourceType
foreach ($expectedType in $expectedResources) {
    $found = $deployedResources | Where-Object {$_.Name -eq $expectedType}
    if ($found) {
        Write-Host "✅ $expectedType deployed successfully" -ForegroundColor Green
    } else {
        Write-Host "❌ $expectedType not found" -ForegroundColor Red
    }
}
```

2. **Test Connectivity**
```powershell
# Test Log Analytics connectivity
$workspaceId = $workspace.CustomerId
$query = "Heartbeat | limit 1"
try {
    $result = Invoke-AzOperationalInsightsQuery -WorkspaceId $workspaceId -Query $query
    Write-Host "✅ Log Analytics connectivity verified" -ForegroundColor Green
} catch {
    Write-Host "❌ Log Analytics connectivity failed: $($_.Exception.Message)" -ForegroundColor Red
}

# Test Application Insights connectivity
try {
    $metrics = Get-AzMetric -ResourceId $appInsights.Id -MetricName "requests/count" -TimeGrain 00:05:00
    Write-Host "✅ Application Insights connectivity verified" -ForegroundColor Green
} catch {
    Write-Host "❌ Application Insights connectivity failed: $($_.Exception.Message)" -ForegroundColor Red
}
```

### Monitoring Validation

1. **Verify Alert Rules**
```powershell
# Check alert rules are created and enabled
$alertRules = Get-AzScheduledQueryRule -ResourceGroupName "rg-apmp-prod"
Write-Host "Alert Rules Deployed: $($alertRules.Count)"
foreach ($rule in $alertRules) {
    $status = if ($rule.Enabled) { "✅ Enabled" } else { "❌ Disabled" }
    Write-Host "  $($rule.Name): $status"
}
```

2. **Test Dashboard Access**
```powershell
# Get workbook information
$workbooks = Get-AzApplicationInsightsWorkbook -ResourceGroupName "rg-apmp-prod"
foreach ($workbook in $workbooks) {
    Write-Host "📊 Dashboard: $($workbook.DisplayName)"
    Write-Host "   URL: https://portal.azure.com/#@tenant/resource$($workbook.Id)"
}
```

### Automation Validation

1. **Test Runbook Execution**
```powershell
# Start health check runbook manually
$job = Start-AzAutomationRunbook `
    -ResourceGroupName "rg-apmp-prod" `
    -AutomationAccountName $automationAccount.AutomationAccountName `
    -Name "APMP-Health-Check-Automation" `
    -Parameters @{
        WorkspaceId = $workspace.CustomerId
        SubscriptionId = "your-subscription-id"
        ResourceGroupName = "rg-apmp-prod"
    }

Write-Host "Health check job started: $($job.JobId)"

# Wait for completion and check results
do {
    Start-Sleep -Seconds 10
    $jobStatus = Get-AzAutomationJob -ResourceGroupName "rg-apmp-prod" -AutomationAccountName $automationAccount.AutomationAccountName -Id $job.JobId
    Write-Host "Job status: $($jobStatus.Status)"
} while ($jobStatus.Status -eq "Running")

if ($jobStatus.Status -eq "Completed") {
    Write-Host "✅ Health check runbook executed successfully" -ForegroundColor Green
    $output = Get-AzAutomationJobOutput -ResourceGroupName "rg-apmp-prod" -AutomationAccountName $automationAccount.AutomationAccountName -Id $job.JobId -Stream Output
    $output | ForEach-Object { Write-Host $_.Summary }
} else {
    Write-Host "❌ Health check runbook failed: $($jobStatus.Status)" -ForegroundColor Red
}
```

---

## 🔧 Post-Deployment Tasks

### 1. Configure Data Sources

```powershell
# Configure performance counters
$perfCounters = @(
    "\\Processor(_Total)\\% Processor Time",
    "\\Memory\\% Committed Bytes In Use",
    "\\Memory\\Available MBytes",
    "\\LogicalDisk(_Total)\\% Free Space",
    "\\LogicalDisk(_Total)\\Disk Reads/sec",
    "\\LogicalDisk(_Total)\\Disk Writes/sec"
)

foreach ($counter in $perfCounters) {
    New-AzOperationalInsightsWindowsPerformanceCounterDataSource `
        -ResourceGroupName "rg-apmp-prod" `
        -WorkspaceName $workspace.Name `
        -ObjectName ($counter.Split('\\')[1]) `
        -InstanceName ($counter.Split('\\')[2].Split(')')[0].TrimStart('(')) `
        -CounterName ($counter.Split('\\')[3]) `
        -IntervalSeconds 60 `
        -Name "APMP-$($counter.Replace('\\', '-').Replace('(', '').Replace(')', '').Replace('%', 'Percent'))"
}
```

### 2. Set Up Custom Logs

```powershell
# Configure custom log ingestion for application logs
$customLogConfig = @{
    "customLogName" = "ApplicationPerformance_CL"
    "description" = "Custom application performance logs"
    "inputs" = @(
        @{
            "location" = @{
                "fileSystemLocations" = @{
                    "windowsFileTypeLogPaths" = @("C:\\Logs\\Application\\*.log")
                    "linuxFileTypeLogPaths" = @("/var/log/application/*.log")
                }
            }
            "recordDelimiter" = @{
                "regexDelimiter" = @{
                    "pattern" = "\\n"
                    "matchIndex" = 0
                }
            }
        }
    )
}

# Note: Custom log configuration requires REST API calls or Azure CLI
```

### 3. Configure Notification Channels

```powershell
# Add additional notification channels to action group
$actionGroup = Get-AzActionGroup -ResourceGroupName "rg-apmp-prod" | Where-Object {$_.Name -like "*apmp*"}

# Add SMS receiver
$smsReceiver = New-AzActionGroupSmsReceiverObject -Name "OnCall-SMS" -CountryCode "1" -PhoneNumber "555-123-4567"
Update-AzActionGroup -ResourceGroupName "rg-apmp-prod" -Name $actionGroup.Name -SmsReceiver $smsReceiver

# Add webhook receiver for Teams/Slack integration
$webhookReceiver = New-AzActionGroupWebhookReceiverObject -Name "Teams-Webhook" -ServiceUri "https://your-teams-webhook-url"
Update-AzActionGroup -ResourceGroupName "rg-apmp-prod" -Name $actionGroup.Name -WebhookReceiver $webhookReceiver
```

### 4. Set Up RBAC

```powershell
# Create custom role for APMP operators
$roleDefinition = @{
    "Name" = "APMP Operator"
    "Description" = "Can view and manage Azure Performance Monitoring Platform resources"
    "Actions" = @(
        "Microsoft.OperationalInsights/workspaces/read",
        "Microsoft.OperationalInsights/workspaces/query/action",
        "Microsoft.Insights/components/read",
        "Microsoft.Insights/alertRules/*",
        "Microsoft.Automation/automationAccounts/runbooks/read",
        "Microsoft.Automation/automationAccounts/jobs/*"
    )
    "NotActions" = @()
    "AssignableScopes" = @("/subscriptions/your-subscription-id/resourceGroups/rg-apmp-prod")
}

$roleDefinitionJson = $roleDefinition | ConvertTo-Json -Depth 10
New-AzRoleDefinition -InputFile $roleDefinitionJson

# Assign role to monitoring team
New-AzRoleAssignment -ObjectId "monitoring-team-object-id" -RoleDefinitionName "APMP Operator" -ResourceGroupName "rg-apmp-prod"
```

---

## 🔍 Troubleshooting

### Common Issues and Solutions

#### Issue 1: Deployment Fails with Permission Error
```
Error: The client 'user@domain.com' with object id 'xxx' does not have authorization to perform action 'Microsoft.Resources/subscriptions/resourceGroups/write'
```

**Solution:**
```powershell
# Check current permissions
Get-AzRoleAssignment -SignInName (Get-AzContext).Account.Id

# Request Contributor or Owner role from subscription administrator
# Or use a service principal with appropriate permissions
```

#### Issue 2: Log Analytics Workspace Not Receiving Data
```
Error: No data available in Log Analytics workspace
```

**Solution:**
```powershell
# Check diagnostic settings
Get-AzDiagnosticSetting -ResourceId $resourceId

# Verify data sources configuration
Get-AzOperationalInsightsDataSource -ResourceGroupName "rg-apmp-prod" -WorkspaceName $workspace.Name

# Test data ingestion
$testData = @{
    "Computer" = $env:COMPUTERNAME
    "TimeGenerated" = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
    "Message" = "Test log entry from APMP deployment"
}
# Send test data using REST API or PowerShell cmdlets
```

#### Issue 3: Alert Rules Not Triggering
```
Error: Alert rules created but not firing
```

**Solution:**
```powershell
# Check alert rule configuration
$alertRules = Get-AzScheduledQueryRule -ResourceGroupName "rg-apmp-prod"
foreach ($rule in $alertRules) {
    Write-Host "Rule: $($rule.Name)"
    Write-Host "  Enabled: $($rule.Enabled)"
    Write-Host "  Query: $($rule.Criteria.AllOf[0].Query)"
    Write-Host "  Threshold: $($rule.Criteria.AllOf[0].Threshold)"
}

# Test queries manually in Log Analytics
$testQuery = "Perf | where ObjectName == 'Processor' | limit 10"
Invoke-AzOperationalInsightsQuery -WorkspaceId $workspace.CustomerId -Query $testQuery
```

#### Issue 4: Runbook Execution Failures
```
Error: Runbook fails with authentication error
```

**Solution:**
```powershell
# Check automation account managed identity
$automationAccount = Get-AzAutomationAccount -ResourceGroupName "rg-apmp-prod" -Name $automationAccountName
if (-not $automationAccount.Identity) {
    # Enable system-assigned managed identity
    Set-AzAutomationAccount -ResourceGroupName "rg-apmp-prod" -Name $automationAccountName -AssignSystemIdentity
}

# Assign required permissions to managed identity
$principalId = $automationAccount.Identity.PrincipalId
New-AzRoleAssignment -ObjectId $principalId -RoleDefinitionName "Log Analytics Reader" -ResourceGroupName "rg-apmp-prod"
New-AzRoleAssignment -ObjectId $principalId -RoleDefinitionName "Monitoring Reader" -ResourceGroupName "rg-apmp-prod"
```

### Diagnostic Commands

```powershell
# Check resource health
Get-AzResourceHealth -ResourceId $workspace.ResourceId

# View activity logs
Get-AzLog -ResourceGroup "rg-apmp-prod" -StartTime (Get-Date).AddHours(-24) | Where-Object {$_.Level -eq "Error"}

# Test network connectivity
Test-NetConnection -ComputerName "api.loganalytics.io" -Port 443
Test-NetConnection -ComputerName "dc.applicationinsights.azure.com" -Port 443

# Validate ARM template
Test-AzResourceGroupDeployment -ResourceGroupName "rg-apmp-prod" -TemplateFile "Infrastructure\ARM-Templates\main-template.json" -TemplateParameterFile "Infrastructure\ARM-Templates\parameters.json"
```

---

## 🔄 Maintenance

### Regular Maintenance Tasks

#### Weekly Tasks
1. **Review Performance Metrics**
```powershell
# Generate weekly performance report
$weeklyReport = @{
    "Period" = "$(Get-Date -Format 'yyyy-MM-dd') to $((Get-Date).AddDays(-7).ToString('yyyy-MM-dd'))"
    "SystemHealth" = "Run comprehensive health check"
    "AlertsSummary" = "Review alert frequency and accuracy"
    "CostAnalysis" = "Analyze resource costs and optimization opportunities"
}
```

2. **Update Alert Thresholds**
```powershell
# Review and adjust alert thresholds based on baseline performance
$alertRules = Get-AzScheduledQueryRule -ResourceGroupName "rg-apmp-prod"
# Analyze alert frequency and adjust thresholds to reduce noise
```

#### Monthly Tasks
1. **Capacity Planning Review**
```powershell
# Analyze resource utilization trends
$utilizationQuery = @"
Perf
| where TimeGenerated >= ago(30d)
| where ObjectName in ("Processor", "Memory", "LogicalDisk")
| summarize avg(CounterValue) by ObjectName, CounterName, bin(TimeGenerated, 1d)
| render timechart
"@
```

2. **Security Review**
```powershell
# Review access permissions
Get-AzRoleAssignment -ResourceGroupName "rg-apmp-prod" | Group-Object RoleDefinitionName

# Check Key Vault access logs
Get-AzLog -ResourceId $keyVault.ResourceId -StartTime (Get-Date).AddDays(-30)
```

#### Quarterly Tasks
1. **Disaster Recovery Testing**
```powershell
# Test backup and restore procedures
# Validate cross-region replication
# Test failover scenarios
```

2. **Performance Optimization**
```powershell
# Review query performance
# Optimize data retention policies
# Analyze cost optimization opportunities
```

### Backup and Recovery

```powershell
# Export ARM templates for backup
Export-AzResourceGroup -ResourceGroupName "rg-apmp-prod" -Path ".\Backup\$(Get-Date -Format 'yyyyMMdd')"

# Backup Key Vault secrets
$secrets = Get-AzKeyVaultSecret -VaultName $keyVault.VaultName
foreach ($secret in $secrets) {
    $secretValue = Get-AzKeyVaultSecret -VaultName $keyVault.VaultName -Name $secret.Name -AsPlainText
    # Store in secure backup location
}

# Backup automation runbooks
$runbooks = Get-AzAutomationRunbook -ResourceGroupName "rg-apmp-prod" -AutomationAccountName $automationAccount.AutomationAccountName
foreach ($runbook in $runbooks) {
    Export-AzAutomationRunbook -ResourceGroupName "rg-apmp-prod" -AutomationAccountName $automationAccount.AutomationAccountName -Name $runbook.Name -OutputFolder ".\Backup\Runbooks"
}
```

---

## 📞 Support and Documentation

### Getting Help
- **Documentation**: [Azure Monitor Documentation](https://docs.microsoft.com/en-us/azure/azure-monitor/)
- **Community**: [Azure Monitor Community](https://techcommunity.microsoft.com/t5/azure-monitor/ct-p/AzureMonitor)
- **Support**: [Azure Support](https://azure.microsoft.com/en-us/support/)

### Additional Resources
- **Best Practices**: [Azure Monitor Best Practices](https://docs.microsoft.com/en-us/azure/azure-monitor/best-practices)
- **Cost Optimization**: [Azure Monitor Cost Optimization](https://docs.microsoft.com/en-us/azure/azure-monitor/usage-estimated-costs)
- **Security**: [Azure Monitor Security](https://docs.microsoft.com/en-us/azure/azure-monitor/logs/security)

---

## 📝 Deployment Checklist

- [ ] Prerequisites verified
- [ ] Resource group created
- [ ] Infrastructure deployed successfully
- [ ] Alert rules configured and enabled
- [ ] Dashboard deployed and accessible
- [ ] Automation runbooks deployed and scheduled
- [ ] Data sources configured
- [ ] Notification channels set up
- [ ] RBAC configured
- [ ] Initial health check completed
- [ ] Documentation updated
- [ ] Team training completed
- [ ] Go-live approval obtained

---

**🎉 Congratulations! Your Azure Performance Monitoring Platform is now deployed and ready for production use.**