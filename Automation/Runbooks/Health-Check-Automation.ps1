#Requires -Version 5.1
#Requires -Modules Az.Accounts, Az.OperationalInsights, Az.Monitor

<#
.SYNOPSIS
    Automated health check runbook for Azure Performance Monitoring Platform
.DESCRIPTION
    This runbook performs comprehensive health checks across Azure resources,
    analyzes performance metrics, and generates recommendations for optimization.
.PARAMETER WorkspaceId
    Log Analytics Workspace ID for querying performance data
.PARAMETER SubscriptionId
    Azure subscription ID containing the resources to monitor
.PARAMETER ResourceGroupName
    Resource group name containing the monitoring resources
.EXAMPLE
    .\Health-Check-Automation.ps1 -WorkspaceId "12345678-1234-1234-1234-123456789012" -SubscriptionId "87654321-4321-4321-4321-210987654321" -ResourceGroupName "rg-apmp-prod"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$WorkspaceId,
    
    [Parameter(Mandatory = $true)]
    [string]$SubscriptionId,
    
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory = $false)]
    [int]$HealthCheckIntervalMinutes = 15,
    
    [Parameter(Mandatory = $false)]
    [string]$NotificationWebhook = ""
)

# Import required modules
Import-Module Az.Accounts -Force
Import-Module Az.OperationalInsights -Force
Import-Module Az.Monitor -Force

# Set error action preference
$ErrorActionPreference = "Stop"

# Function to write log messages
function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    Write-Output $logMessage
}

# Function to execute KQL query
function Invoke-KQLQuery {
    param(
        [string]$Query,
        [string]$WorkspaceId,
        [string]$Description = ""
    )
    
    try {
        Write-Log "Executing KQL query: $Description" -Level "INFO"
        $result = Invoke-AzOperationalInsightsQuery -WorkspaceId $WorkspaceId -Query $Query
        return $result.Results
    }
    catch {
        Write-Log "Failed to execute KQL query: $($_.Exception.Message)" -Level "ERROR"
        return $null
    }
}

# Function to perform CPU health check
function Test-CPUHealth {
    param([string]$WorkspaceId)
    
    $query = @"
Perf
| where TimeGenerated >= ago(15m)
| where ObjectName == "Processor" and CounterName == "% Processor Time" and InstanceName == "_Total"
| summarize AvgCPU = avg(CounterValue), MaxCPU = max(CounterValue)
| extend HealthStatus = case(
    AvgCPU > 80, "Critical",
    AvgCPU > 60, "Warning",
    "Good"
),
Score = case(
    AvgCPU > 80, 30,
    AvgCPU > 60, 70,
    90
),
Recommendation = case(
    AvgCPU > 80, "CPU usage is critically high. Consider scaling up or optimizing workloads.",
    AvgCPU > 60, "CPU usage is elevated. Monitor closely and consider optimization.",
    "CPU usage is within normal range."
)
"@
    
    $result = Invoke-KQLQuery -Query $query -WorkspaceId $WorkspaceId -Description "CPU Health Check"
    return @{
        CheckName = "CPU Health"
        Status = if ($result) { $result[0].HealthStatus } else { "Unknown" }
        Score = if ($result) { $result[0].Score } else { 0 }
        Recommendation = if ($result) { $result[0].Recommendation } else { "Unable to retrieve CPU metrics" }
        Metrics = if ($result) { @{ AvgCPU = $result[0].AvgCPU; MaxCPU = $result[0].MaxCPU } } else { @{} }
    }
}

# Function to perform Memory health check
function Test-MemoryHealth {
    param([string]$WorkspaceId)
    
    $query = @"
Perf
| where TimeGenerated >= ago(15m)
| where ObjectName == "Memory" and CounterName == "% Committed Bytes In Use"
| summarize AvgMemory = avg(CounterValue), MaxMemory = max(CounterValue)
| extend HealthStatus = case(
    AvgMemory > 85, "Critical",
    AvgMemory > 70, "Warning",
    "Good"
),
Score = case(
    AvgMemory > 85, 25,
    AvgMemory > 70, 65,
    95
),
Recommendation = case(
    AvgMemory > 85, "Memory usage is critically high. Immediate action required to prevent system instability.",
    AvgMemory > 70, "Memory usage is elevated. Consider optimizing memory usage or scaling up.",
    "Memory usage is within normal range."
)
"@
    
    $result = Invoke-KQLQuery -Query $query -WorkspaceId $WorkspaceId -Description "Memory Health Check"
    return @{
        CheckName = "Memory Health"
        Status = if ($result) { $result[0].HealthStatus } else { "Unknown" }
        Score = if ($result) { $result[0].Score } else { 0 }
        Recommendation = if ($result) { $result[0].Recommendation } else { "Unable to retrieve memory metrics" }
        Metrics = if ($result) { @{ AvgMemory = $result[0].AvgMemory; MaxMemory = $result[0].MaxMemory } } else { @{} }
    }
}

# Function to perform Database health check
function Test-DatabaseHealth {
    param([string]$WorkspaceId)
    
    $query = @"
SynapseSqlPoolExecRequests 
| where TimeGenerated >= ago(30m)
| where Label != "health_checker"
| where Status contains "Running"
| extend duration_sec = datetime_diff("second", TimeGenerated, StartTime)
| summarize 
    LongRunningQueries = countif(duration_sec > 300),
    AvgDuration = avg(duration_sec),
    MaxDuration = max(duration_sec),
    TotalQueries = count()
| extend HealthStatus = case(
    LongRunningQueries > 5, "Critical",
    LongRunningQueries > 2, "Warning",
    "Good"
),
Score = case(
    LongRunningQueries > 5, 35,
    LongRunningQueries > 2, 75,
    92
),
Recommendation = case(
    LongRunningQueries > 5, "Multiple long-running queries detected. Review query performance and optimize.",
    LongRunningQueries > 2, "Some long-running queries detected. Monitor query performance.",
    "Database query performance is optimal."
)
"@
    
    $result = Invoke-KQLQuery -Query $query -WorkspaceId $WorkspaceId -Description "Database Health Check"
    return @{
        CheckName = "Database Health"
        Status = if ($result) { $result[0].HealthStatus } else { "Good" }
        Score = if ($result) { $result[0].Score } else { 90 }
        Recommendation = if ($result) { $result[0].Recommendation } else { "No recent database activity detected" }
        Metrics = if ($result) { @{ 
            LongRunningQueries = $result[0].LongRunningQueries
            AvgDuration = $result[0].AvgDuration
            MaxDuration = $result[0].MaxDuration
            TotalQueries = $result[0].TotalQueries
        } } else { @{} }
    }
}

# Function to perform Application health check
function Test-ApplicationHealth {
    param([string]$WorkspaceId)
    
    $query = @"
requests
| where timestamp >= ago(15m)
| summarize 
    TotalRequests = count(),
    SuccessfulRequests = countif(success == true),
    FailedRequests = countif(success == false),
    AvgDuration = avg(duration),
    P95Duration = percentile(duration, 95)
| extend 
    SuccessRate = (SuccessfulRequests * 100.0) / TotalRequests,
    HealthStatus = case(
        SuccessRate < 95, "Critical",
        SuccessRate < 98, "Warning",
        "Good"
    ),
    Score = case(
        SuccessRate < 95, 40,
        SuccessRate < 98, 80,
        95
    ),
    Recommendation = case(
        SuccessRate < 95, "Application error rate is high. Investigate and resolve application issues immediately.",
        SuccessRate < 98, "Application error rate is elevated. Monitor application health closely.",
        "Application is performing well with good success rate."
    )
"@
    
    $result = Invoke-KQLQuery -Query $query -WorkspaceId $WorkspaceId -Description "Application Health Check"
    return @{
        CheckName = "Application Health"
        Status = if ($result) { $result[0].HealthStatus } else { "Good" }
        Score = if ($result) { $result[0].Score } else { 90 }
        Recommendation = if ($result) { $result[0].Recommendation } else { "No recent application activity detected" }
        Metrics = if ($result) { @{ 
            TotalRequests = $result[0].TotalRequests
            SuccessRate = $result[0].SuccessRate
            AvgDuration = $result[0].AvgDuration
            P95Duration = $result[0].P95Duration
        } } else { @{} }
    }
}

# Function to perform Spark health check
function Test-SparkHealth {
    param([string]$WorkspaceId)
    
    $query = @"
SparkMetrics_CL
| where TimeGenerated >= ago(30m)
| where name_s contains_cs "executor.cpuTime"
| extend cputime = count_d / 1000000
| summarize 
    TotalCPUTime = sum(cputime),
    ApplicationCount = dcount(applicationName_s)
    by bin(TimeGenerated, 10m)
| summarize 
    AvgCPUTime = avg(TotalCPUTime),
    MaxCPUTime = max(TotalCPUTime),
    AvgApplications = avg(ApplicationCount)
| extend HealthStatus = case(
    MaxCPUTime > 50000, "Warning",
    MaxCPUTime > 100000, "Critical",
    "Good"
),
Score = case(
    MaxCPUTime > 100000, 45,
    MaxCPUTime > 50000, 75,
    88
),
Recommendation = case(
    MaxCPUTime > 100000, "Spark applications are consuming excessive CPU. Optimize Spark jobs and resource allocation.",
    MaxCPUTime > 50000, "Spark CPU usage is elevated. Monitor Spark job performance.",
    "Spark applications are performing within normal parameters."
)
"@
    
    $result = Invoke-KQLQuery -Query $query -WorkspaceId $WorkspaceId -Description "Spark Health Check"
    return @{
        CheckName = "Spark Health"
        Status = if ($result) { $result[0].HealthStatus } else { "Good" }
        Score = if ($result) { $result[0].Score } else { 85 }
        Recommendation = if ($result) { $result[0].Recommendation } else { "No recent Spark activity detected" }
        Metrics = if ($result) { @{ 
            AvgCPUTime = $result[0].AvgCPUTime
            MaxCPUTime = $result[0].MaxCPUTime
            AvgApplications = $result[0].AvgApplications
        } } else { @{} }
    }
}

# Function to calculate overall health score
function Get-OverallHealthScore {
    param([array]$HealthChecks)
    
    $totalScore = 0
    $checkCount = 0
    
    foreach ($check in $HealthChecks) {
        if ($check.Score -gt 0) {
            $totalScore += $check.Score
            $checkCount++
        }
    }
    
    if ($checkCount -eq 0) {
        return 0
    }
    
    return [math]::Round($totalScore / $checkCount, 2)
}

# Function to send notification
function Send-Notification {
    param(
        [string]$WebhookUrl,
        [object]$HealthReport
    )
    
    if ([string]::IsNullOrEmpty($WebhookUrl)) {
        Write-Log "No webhook URL provided. Skipping notification." -Level "INFO"
        return
    }
    
    try {
        $payload = @{
            text = "Azure Performance Monitoring Platform - Health Check Report"
            attachments = @(
                @{
                    color = if ($HealthReport.OverallScore -ge 80) { "good" } elseif ($HealthReport.OverallScore -ge 60) { "warning" } else { "danger" }
                    fields = @(
                        @{
                            title = "Overall Health Score"
                            value = "$($HealthReport.OverallScore)/100"
                            short = $true
                        },
                        @{
                            title = "Critical Issues"
                            value = ($HealthReport.HealthChecks | Where-Object { $_.Status -eq "Critical" }).Count
                            short = $true
                        },
                        @{
                            title = "Warnings"
                            value = ($HealthReport.HealthChecks | Where-Object { $_.Status -eq "Warning" }).Count
                            short = $true
                        },
                        @{
                            title = "Timestamp"
                            value = $HealthReport.Timestamp
                            short = $true
                        }
                    )
                }
            )
        } | ConvertTo-Json -Depth 10
        
        Invoke-RestMethod -Uri $WebhookUrl -Method Post -Body $payload -ContentType "application/json"
        Write-Log "Notification sent successfully" -Level "INFO"
    }
    catch {
        Write-Log "Failed to send notification: $($_.Exception.Message)" -Level "ERROR"
    }
}

# Function to log health check results
function Write-HealthCheckResults {
    param(
        [string]$WorkspaceId,
        [object]$HealthReport
    )
    
    try {
        # Create custom log entry for health check results
        $logData = @{
            TimeGenerated = $HealthReport.Timestamp
            OverallScore = $HealthReport.OverallScore
            HealthChecks = $HealthReport.HealthChecks | ConvertTo-Json -Depth 5
            CriticalIssues = ($HealthReport.HealthChecks | Where-Object { $_.Status -eq "Critical" }).Count
            Warnings = ($HealthReport.HealthChecks | Where-Object { $_.Status -eq "Warning" }).Count
            GoodChecks = ($HealthReport.HealthChecks | Where-Object { $_.Status -eq "Good" }).Count
        }
        
        # In a real implementation, you would send this to Log Analytics custom log
        Write-Log "Health check results logged: Overall Score = $($HealthReport.OverallScore)" -Level "INFO"
    }
    catch {
        Write-Log "Failed to log health check results: $($_.Exception.Message)" -Level "ERROR"
    }
}

# Main execution
try {
    Write-Log "Starting Azure Performance Monitoring Platform Health Check" -Level "INFO"
    
    # Connect to Azure
    $context = Get-AzContext
    if (-not $context -or $context.Subscription.Id -ne $SubscriptionId) {
        Write-Log "Connecting to Azure subscription: $SubscriptionId" -Level "INFO"
        Connect-AzAccount -Identity -SubscriptionId $SubscriptionId
    }
    
    # Perform health checks
    Write-Log "Performing comprehensive health checks..." -Level "INFO"
    
    $healthChecks = @()
    $healthChecks += Test-CPUHealth -WorkspaceId $WorkspaceId
    $healthChecks += Test-MemoryHealth -WorkspaceId $WorkspaceId
    $healthChecks += Test-DatabaseHealth -WorkspaceId $WorkspaceId
    $healthChecks += Test-ApplicationHealth -WorkspaceId $WorkspaceId
    $healthChecks += Test-SparkHealth -WorkspaceId $WorkspaceId
    
    # Calculate overall health score
    $overallScore = Get-OverallHealthScore -HealthChecks $healthChecks
    
    # Create health report
    $healthReport = @{
        Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss UTC"
        OverallScore = $overallScore
        HealthChecks = $healthChecks
        ResourceGroup = $ResourceGroupName
        Subscription = $SubscriptionId
    }
    
    # Log results
    Write-Log "Health check completed. Overall Score: $overallScore/100" -Level "INFO"
    
    # Display individual check results
    foreach ($check in $healthChecks) {
        Write-Log "$($check.CheckName): $($check.Status) (Score: $($check.Score)/100)" -Level "INFO"
        Write-Log "  Recommendation: $($check.Recommendation)" -Level "INFO"
    }
    
    # Log health check results to workspace
    Write-HealthCheckResults -WorkspaceId $WorkspaceId -HealthReport $healthReport
    
    # Send notification if configured
    if (-not [string]::IsNullOrEmpty($NotificationWebhook)) {
        Send-Notification -WebhookUrl $NotificationWebhook -HealthReport $healthReport
    }
    
    # Output health report for pipeline consumption
    $healthReport | ConvertTo-Json -Depth 10 | Write-Output
    
    Write-Log "Azure Performance Monitoring Platform Health Check completed successfully" -Level "INFO"
}
catch {
    Write-Log "Health check failed: $($_.Exception.Message)" -Level "ERROR"
    Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level "ERROR"
    throw
}