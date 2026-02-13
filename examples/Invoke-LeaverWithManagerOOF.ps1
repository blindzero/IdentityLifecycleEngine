<#
.SYNOPSIS
Host example showing request enrichment with manager data for OOF templates.

.DESCRIPTION
This script demonstrates how to enrich a lifecycle request with manager information
from Active Directory or Entra ID before executing a leaver workflow that uses
template variables in Out of Office messages.

Key concepts:
- Manager lookup is performed HOST-SIDE, not inside workflow steps
- Request enrichment happens before calling New-IdlePlan
- Templates like {{Request.DesiredState.Manager.DisplayName}} are resolved during planning

.NOTES
This is an example only. Adapt authentication, provider setup, and directory queries
to your environment.
#>

[CmdletBinding()]
param(
    # User principal name of the leaver
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string] $UserPrincipalName,
    
    # Directory source for manager lookup
    [Parameter()]
    [ValidateSet('AD', 'EntraID')]
    [string] $DirectorySource = 'AD',
    
    # Path to the leaver workflow
    [Parameter()]
    [string] $WorkflowPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Resolve paths relative to script location for portability
if ([string]::IsNullOrWhiteSpace($WorkflowPath)) {
    $WorkflowPath = Join-Path $PSScriptRoot 'workflows' 'templates' 'exo-leaver-mailbox-offboarding.psd1'
    $WorkflowPath = (Resolve-Path -LiteralPath $WorkflowPath -ErrorAction Stop).Path
}

# Import IdLE module
$idleModulePath = Join-Path $PSScriptRoot '..' 'src' 'IdLE' 'IdLE.psd1'
$idleModulePath = (Resolve-Path -LiteralPath $idleModulePath -ErrorAction Stop).Path
Import-Module $idleModulePath -Force

Write-Host "==> Enriching request with manager data from $DirectorySource..." -ForegroundColor Cyan

# 1. Retrieve manager information (host-side lookup)
$managerInfo = $null

switch ($DirectorySource) {
    'AD' {
        # Active Directory example
        Write-Host "Querying Active Directory for user: $UserPrincipalName"
        
        # Extract sAMAccountName from UPN if needed
        $samAccountName = $UserPrincipalName.Split('@')[0]
        
        $user = Get-ADUser -Identity $samAccountName -Properties Manager -ErrorAction Stop
        
        if ($user.Manager) {
            Write-Host "  Found manager DN: $($user.Manager)"
            $mgr = Get-ADUser -Identity $user.Manager -Properties DisplayName, Mail -ErrorAction Stop
            
            $managerInfo = @{
                DisplayName = $mgr.DisplayName
                Mail        = $mgr.Mail
            }
            
            Write-Host "  Manager: $($managerInfo.DisplayName) <$($managerInfo.Mail)>" -ForegroundColor Green
        }
        else {
            Write-Warning "  No manager found for user $UserPrincipalName in AD."
        }
    }
    
    'EntraID' {
        # Microsoft Graph / Entra ID example
        Write-Host "Querying Entra ID for user: $UserPrincipalName"
        
        # Ensure Microsoft.Graph module is available
        if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Users)) {
            throw "Microsoft.Graph.Users module is required. Install with: Install-Module Microsoft.Graph.Users"
        }
        
        Import-Module Microsoft.Graph.Users
        
        # Connect to Graph (assumes already authenticated or will prompt)
        $null = Connect-MgGraph -Scopes 'User.Read.All' -NoWelcome -ErrorAction Stop
        
        $user = Get-MgUser -UserId $UserPrincipalName -Property 'Manager' -ErrorAction Stop
        
        if ($user.Manager.Id) {
            Write-Host "  Found manager ID: $($user.Manager.Id)"
            $mgr = Get-MgUser -UserId $user.Manager.Id -Property 'DisplayName', 'Mail' -ErrorAction Stop
            
            $managerInfo = @{
                DisplayName = $mgr.DisplayName
                Mail        = $mgr.Mail
            }
            
            Write-Host "  Manager: $($managerInfo.DisplayName) <$($managerInfo.Mail)>" -ForegroundColor Green
        }
        else {
            Write-Warning "  No manager found for user $UserPrincipalName in Entra ID."
        }
    }
}

# 2. Build lifecycle request with enriched DesiredState
Write-Host "==> Building lifecycle request..." -ForegroundColor Cyan

$desiredState = @{}

if ($managerInfo) {
    $desiredState['Manager'] = $managerInfo
}
else {
    # Fallback: use generic support contact
    Write-Warning "No manager found; using generic support contact in OOF message."
    $desiredState['Manager'] = @{
        DisplayName = 'IT Support'
        Mail        = 'support@contoso.com'
    }
}

$request = New-IdleRequest `
    -LifecycleEvent 'Leaver' `
    -Actor $env:USERNAME `
    -Input @{
        UserPrincipalName = $UserPrincipalName
    } `
    -DesiredState $desiredState

Write-Host "  Request CorrelationId: $($request.CorrelationId)" -ForegroundColor Gray

# 3. Set up providers
Write-Host "==> Setting up providers..." -ForegroundColor Cyan

# For this example, we'll use mock providers (replace with real providers in production)
Import-Module ./src/IdLE.Steps.Mailbox/IdLE.Steps.Mailbox.psd1 -Force
Import-Module ./src/IdLE.Provider.Mock/IdLE.Provider.Mock.psd1 -Force

$exoProvider = New-IdleMockProvider -Name 'ExchangeOnline' -Capabilities @(
    'IdLE.Mailbox.Info.Read'
    'IdLE.Mailbox.Type.Ensure'
    'IdLE.Mailbox.OutOfOffice.Ensure'
)

$authBroker = New-IdleAuthSessionBroker `
    -AuthSessionType 'OAuth' `
    -DefaultAuthSession ([pscustomobject]@{ Token = 'mock-token' })

$providers = @{
    ExchangeOnline    = $exoProvider
    AuthSessionBroker = $authBroker
}

# 4. Build plan (templates are resolved here)
Write-Host "==> Building execution plan..." -ForegroundColor Cyan

$plan = New-IdlePlan `
    -WorkflowPath $WorkflowPath `
    -Request $request `
    -Providers $providers

Write-Host "  Plan Name: $($plan.WorkflowName)"
Write-Host "  Steps: $($plan.Steps.Count)"

# Show resolved template values
$oofStep = $plan.Steps | Where-Object { $_.Type -like '*OutOfOffice*' } | Select-Object -First 1
if ($oofStep) {
    Write-Host ""
    Write-Host "  OOF Internal Message (template resolved):" -ForegroundColor Yellow
    Write-Host "    $($oofStep.With.Config.InternalMessage)" -ForegroundColor Gray
    Write-Host "  OOF External Message (template resolved):" -ForegroundColor Yellow
    Write-Host "    $($oofStep.With.Config.ExternalMessage)" -ForegroundColor Gray
}

# 5. Execute plan
Write-Host ""
Write-Host "==> Executing plan..." -ForegroundColor Cyan

$result = Invoke-IdlePlan `
    -Plan $plan `
    -Providers $providers

Write-Host "  Status: $($result.Status)" -ForegroundColor $(if ($result.Status -eq 'Completed') { 'Green' } else { 'Red' })
Write-Host "  Steps executed: $($result.Steps.Count)"

foreach ($step in $result.Steps) {
    $statusColor = switch ($step.Status) {
        'Completed' { 'Green' }
        'Skipped'   { 'Yellow' }
        default     { 'Red' }
    }
    Write-Host "    - $($step.Name): $($step.Status)" -ForegroundColor $statusColor
}

Write-Host ""
Write-Host "==> Done." -ForegroundColor Cyan

