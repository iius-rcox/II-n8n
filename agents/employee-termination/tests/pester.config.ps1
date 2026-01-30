<#
.SYNOPSIS
    Pester configuration for Employee Termination PowerShell tests

.DESCRIPTION
    Run with: Invoke-Pester -Configuration (. .\pester.config.ps1)

.EXAMPLE
    # Run all tests with coverage
    $config = . .\tests\pester.config.ps1
    Invoke-Pester -Configuration $config

.EXAMPLE
    # Run tests with verbose output
    Invoke-Pester -Path .\tests -Output Detailed
#>

$PesterConfig = New-PesterConfiguration

# Run configuration
$PesterConfig.Run.Path = $PSScriptRoot
$PesterConfig.Run.Exit = $true
$PesterConfig.Run.Throw = $true
$PesterConfig.Run.PassThru = $true

# Output configuration
$PesterConfig.Output.Verbosity = 'Detailed'
$PesterConfig.Output.StackTraceVerbosity = 'Full'
$PesterConfig.Output.CIFormat = 'Auto'

# Code coverage configuration
$PesterConfig.CodeCoverage.Enabled = $true
$PesterConfig.CodeCoverage.Path = @(
    (Join-Path $PSScriptRoot '..\Terminate-Employee.ps1')
)
$PesterConfig.CodeCoverage.OutputPath = (Join-Path $PSScriptRoot '..\coverage\coverage.xml')
$PesterConfig.CodeCoverage.OutputFormat = 'JaCoCo'
$PesterConfig.CodeCoverage.CoveragePercentTarget = 80

# Test result configuration
$PesterConfig.TestResult.Enabled = $true
$PesterConfig.TestResult.OutputPath = (Join-Path $PSScriptRoot '..\coverage\testResults.xml')
$PesterConfig.TestResult.OutputFormat = 'NUnitXml'

# Filter configuration (can be overridden at runtime)
$PesterConfig.Filter.Tag = @()
$PesterConfig.Filter.ExcludeTag = @('Integration', 'E2E')

# Should configuration
$PesterConfig.Should.ErrorAction = 'Continue'

# Debug configuration
$PesterConfig.Debug.ShowFullErrors = $true
$PesterConfig.Debug.WriteDebugMessages = $false
$PesterConfig.Debug.WriteDebugMessagesFrom = @('Discovery', 'Skip', 'Mock', 'CodeCoverage')

return $PesterConfig
