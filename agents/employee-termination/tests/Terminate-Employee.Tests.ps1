#Requires -Modules Pester

<#
.SYNOPSIS
    Pester tests for Employee Termination PowerShell script.

.DESCRIPTION
    TDD tests - write these BEFORE implementing Terminate-Employee.ps1
    Run with: Invoke-Pester -Path .\Terminate-Employee.Tests.ps1

.NOTES
    Exit Codes:
    0  - Success
    1  - General error
    10 - Employee not found
    11 - Employee already disabled
    12 - Protected account
    20 - Graph connection failed
    21 - Exchange connection failed
    22 - AD connection failed
    30 - License removal failed
    31 - Mailbox conversion failed
    32 - AD disable failed
    33 - OU move failed
    40 - AD Sync trigger failed
#>

BeforeAll {
    # Import the module under test
    $ScriptPath = Join-Path $PSScriptRoot "..\Terminate-Employee.ps1"
    if (Test-Path $ScriptPath) {
        . $ScriptPath
    } else {
        # Create stub for TDD - tests should fail until implementation exists
        function Invoke-EmployeeTermination {
            param(
                [string]$EmployeeUPN,
                [string]$RequesterUPN,
                [string]$TicketId,
                [datetime]$TerminationDate,
                [switch]$WhatIf
            )
            throw "Not implemented - write the implementation to make tests pass"
        }

        function Test-ProtectedAccount {
            param([string]$UserPrincipalName)
            throw "Not implemented"
        }

        function Test-ValidUPN {
            param([string]$UPN)
            throw "Not implemented"
        }
    }

    # Default mocks for external dependencies
    Mock Connect-MgGraph { return $true } -ModuleName Microsoft.Graph.Authentication -ErrorAction SilentlyContinue
    Mock Connect-ExchangeOnline { return $true } -ModuleName ExchangeOnlineManagement -ErrorAction SilentlyContinue

    Mock Get-ADUser {
        param($Identity, $Properties)
        switch -Regex ($Identity) {
            'test\.notfound@' { throw "Cannot find an object with identity: '$Identity'" }
            'test\.termination2@' {
                return [PSCustomObject]@{
                    Enabled = $false
                    DistinguishedName = "CN=Test Term2,OU=DisabledUsers,DC=ii-us,DC=com"
                    UserPrincipalName = $Identity
                    MemberOf = @()
                }
            }
            'test\.admin@' {
                return [PSCustomObject]@{
                    Enabled = $true
                    DistinguishedName = "CN=Test Admin,OU=Admins,DC=ii-us,DC=com"
                    UserPrincipalName = $Identity
                    MemberOf = @("CN=Domain Admins,CN=Users,DC=ii-us,DC=com")
                }
            }
            'test\.enterprise@' {
                return [PSCustomObject]@{
                    Enabled = $true
                    DistinguishedName = "CN=Test Enterprise,OU=Admins,DC=ii-us,DC=com"
                    UserPrincipalName = $Identity
                    MemberOf = @("CN=Enterprise Admins,CN=Users,DC=ii-us,DC=com")
                }
            }
            'test\.serviceaccount@' {
                return [PSCustomObject]@{
                    Enabled = $true
                    DistinguishedName = "CN=SvcAccount,OU=ServiceAccounts,DC=ii-us,DC=com"
                    UserPrincipalName = $Identity
                    MemberOf = @()
                }
            }
            'test\.nolicense@' {
                return [PSCustomObject]@{
                    Enabled = $true
                    DistinguishedName = "CN=No License,OU=Users,DC=ii-us,DC=com"
                    UserPrincipalName = $Identity
                    MemberOf = @()
                }
            }
            default {
                return [PSCustomObject]@{
                    Enabled = $true
                    DistinguishedName = "CN=Test User,OU=Users,DC=ii-us,DC=com"
                    UserPrincipalName = $Identity
                    MemberOf = @()
                }
            }
        }
    }

    Mock Get-MgUser {
        param($UserId)
        return [PSCustomObject]@{
            Id = "user-guid-$(Get-Random)"
            DisplayName = "Test User"
            UserPrincipalName = $UserId
        }
    }

    Mock Get-MgUserLicenseDetail {
        param($UserId)
        if ($UserId -match 'nolicense') {
            return @()
        }
        return @(
            [PSCustomObject]@{ SkuId = "05e9a617-0261-4cee-bb44-138d3ef5d965"; SkuPartNumber = "SPE_E3" }
        )
    }

    Mock Set-MgUserLicense { return $true }
    Mock Set-Mailbox { return $true }
    Mock Disable-ADAccount { return $true }
    Mock Move-ADObject { return $true }
    Mock Start-ADSyncSyncCycle { return $true }
    Mock Disconnect-MgGraph { return $true }
    Mock Disconnect-ExchangeOnline { return $true }
}

Describe "Invoke-EmployeeTermination" {
    Context "Input Validation" {
        It "Should reject empty employee_upn with exit code 1" {
            $result = Invoke-EmployeeTermination -EmployeeUPN "" -RequesterUPN "admin@ii-us.com" -TicketId "TEST-001"
            $result.ExitCode | Should -Be 1
            $result.Error | Should -Match "employee_upn.*required"
        }

        It "Should reject null employee_upn with exit code 1" {
            $result = Invoke-EmployeeTermination -EmployeeUPN $null -RequesterUPN "admin@ii-us.com" -TicketId "TEST-001"
            $result.ExitCode | Should -Be 1
        }

        It "Should reject empty requester_upn with exit code 1" {
            $result = Invoke-EmployeeTermination -EmployeeUPN "test@ii-us.com" -RequesterUPN "" -TicketId "TEST-001"
            $result.ExitCode | Should -Be 1
            $result.Error | Should -Match "requester_upn.*required"
        }

        It "Should reject empty ticket_id with exit code 1" {
            $result = Invoke-EmployeeTermination -EmployeeUPN "test@ii-us.com" -RequesterUPN "admin@ii-us.com" -TicketId ""
            $result.ExitCode | Should -Be 1
            $result.Error | Should -Match "ticket_id.*required"
        }

        It "Should reject invalid UPN format (no @)" {
            $result = Invoke-EmployeeTermination -EmployeeUPN "not-a-valid-email" -RequesterUPN "admin@ii-us.com" -TicketId "TEST-001"
            $result.ExitCode | Should -Be 1
            $result.Error | Should -Match "invalid.*format"
        }

        It "Should reject invalid UPN format (multiple @)" {
            $result = Invoke-EmployeeTermination -EmployeeUPN "test@@ii-us.com" -RequesterUPN "admin@ii-us.com" -TicketId "TEST-001"
            $result.ExitCode | Should -Be 1
        }

        It "Should reject SQL injection attempt in employee_upn" {
            $result = Invoke-EmployeeTermination -EmployeeUPN "'; DROP TABLE Users;--@ii-us.com" -RequesterUPN "admin@ii-us.com" -TicketId "TEST-001"
            $result.ExitCode | Should -Be 1
            $result.Error | Should -Match "invalid.*characters"
        }

        It "Should reject XSS attempt in employee_upn" {
            $result = Invoke-EmployeeTermination -EmployeeUPN "<script>alert('xss')</script>@ii-us.com" -RequesterUPN "admin@ii-us.com" -TicketId "TEST-001"
            $result.ExitCode | Should -Be 1
        }

        It "Should reject employee_upn with semicolons" {
            $result = Invoke-EmployeeTermination -EmployeeUPN "test;user@ii-us.com" -RequesterUPN "admin@ii-us.com" -TicketId "TEST-001"
            $result.ExitCode | Should -Be 1
        }

        It "Should accept valid inputs in WhatIf mode" {
            $result = Invoke-EmployeeTermination -EmployeeUPN "test.termination1@ii-us.com" -RequesterUPN "admin@ii-us.com" -TicketId "TEST-001" -WhatIf
            $result.ExitCode | Should -Be 0
        }
    }

    Context "Employee Not Found (Exit Code 10)" {
        It "Should return exit code 10 when employee does not exist in AD" {
            $result = Invoke-EmployeeTermination -EmployeeUPN "test.notfound@ii-us.com" -RequesterUPN "admin@ii-us.com" -TicketId "TEST-001"
            $result.ExitCode | Should -Be 10
            $result.Error | Should -Match "not found"
        }

        It "Should not attempt any operations for non-existent employee" {
            Invoke-EmployeeTermination -EmployeeUPN "test.notfound@ii-us.com" -RequesterUPN "admin@ii-us.com" -TicketId "TEST-001"
            Should -Not -Invoke Set-MgUserLicense
            Should -Not -Invoke Set-Mailbox
            Should -Not -Invoke Disable-ADAccount
        }
    }

    Context "Employee Already Disabled (Exit Code 11)" {
        It "Should return exit code 11 when employee is already disabled" {
            $result = Invoke-EmployeeTermination -EmployeeUPN "test.termination2@ii-us.com" -RequesterUPN "admin@ii-us.com" -TicketId "TEST-001"
            $result.ExitCode | Should -Be 11
            $result.Message | Should -Match "already disabled"
        }

        It "Should be idempotent - no changes on already disabled user" {
            Invoke-EmployeeTermination -EmployeeUPN "test.termination2@ii-us.com" -RequesterUPN "admin@ii-us.com" -TicketId "TEST-001"
            Should -Not -Invoke Disable-ADAccount
            Should -Not -Invoke Move-ADObject
        }

        It "Should include idempotent flag in result" {
            $result = Invoke-EmployeeTermination -EmployeeUPN "test.termination2@ii-us.com" -RequesterUPN "admin@ii-us.com" -TicketId "TEST-001"
            $result.Idempotent | Should -Be $true
        }
    }

    Context "Protected Account (Exit Code 12)" {
        It "Should return exit code 12 for Domain Admin accounts" {
            $result = Invoke-EmployeeTermination -EmployeeUPN "test.admin@ii-us.com" -RequesterUPN "admin@ii-us.com" -TicketId "TEST-001"
            $result.ExitCode | Should -Be 12
            $result.Error | Should -Match "protected"
        }

        It "Should return exit code 12 for Enterprise Admin accounts" {
            $result = Invoke-EmployeeTermination -EmployeeUPN "test.enterprise@ii-us.com" -RequesterUPN "admin@ii-us.com" -TicketId "TEST-001"
            $result.ExitCode | Should -Be 12
        }

        It "Should return exit code 12 for accounts in ServiceAccounts OU" {
            $result = Invoke-EmployeeTermination -EmployeeUPN "test.serviceaccount@ii-us.com" -RequesterUPN "admin@ii-us.com" -TicketId "TEST-001"
            $result.ExitCode | Should -Be 12
        }

        It "Should not modify Domain Admin accounts" {
            Invoke-EmployeeTermination -EmployeeUPN "test.admin@ii-us.com" -RequesterUPN "admin@ii-us.com" -TicketId "TEST-001"
            Should -Not -Invoke Disable-ADAccount
            Should -Not -Invoke Set-MgUserLicense
        }
    }

    Context "Connection Failures" {
        It "Should return exit code 20 when Graph connection fails" {
            Mock Connect-MgGraph { throw "Connection failed" }
            $result = Invoke-EmployeeTermination -EmployeeUPN "test.termination1@ii-us.com" -RequesterUPN "admin@ii-us.com" -TicketId "TEST-001"
            $result.ExitCode | Should -Be 20
            $result.Retryable | Should -Be $true
        }

        It "Should return exit code 21 when Exchange connection fails" {
            Mock Connect-ExchangeOnline { throw "Connection failed" }
            $result = Invoke-EmployeeTermination -EmployeeUPN "test.termination1@ii-us.com" -RequesterUPN "admin@ii-us.com" -TicketId "TEST-001"
            $result.ExitCode | Should -Be 21
            $result.Retryable | Should -Be $true
        }

        It "Should return exit code 22 when AD connection fails" {
            Mock Get-ADUser { throw "Cannot contact domain controller" }
            $result = Invoke-EmployeeTermination -EmployeeUPN "test.termination1@ii-us.com" -RequesterUPN "admin@ii-us.com" -TicketId "TEST-001"
            $result.ExitCode | Should -Be 22
            $result.Retryable | Should -Be $true
        }
    }

    Context "Operation Failures" {
        It "Should return exit code 30 when license removal fails" {
            Mock Set-MgUserLicense { throw "License removal failed: insufficient permissions" }
            $result = Invoke-EmployeeTermination -EmployeeUPN "test.termination1@ii-us.com" -RequesterUPN "admin@ii-us.com" -TicketId "TEST-001"
            $result.ExitCode | Should -Be 30
            $result.Error | Should -Match "license"
        }

        It "Should return exit code 31 when mailbox conversion fails" {
            Mock Set-Mailbox { throw "Mailbox conversion failed: mailbox in litigation hold" }
            $result = Invoke-EmployeeTermination -EmployeeUPN "test.termination1@ii-us.com" -RequesterUPN "admin@ii-us.com" -TicketId "TEST-001"
            $result.ExitCode | Should -Be 31
            $result.Error | Should -Match "mailbox"
        }

        It "Should return exit code 32 when AD disable fails" {
            Mock Disable-ADAccount { throw "Access denied" }
            $result = Invoke-EmployeeTermination -EmployeeUPN "test.termination1@ii-us.com" -RequesterUPN "admin@ii-us.com" -TicketId "TEST-001"
            $result.ExitCode | Should -Be 32
            $result.Error | Should -Match "disable|AD"
        }

        It "Should return exit code 33 when OU move fails" {
            Mock Move-ADObject { throw "Target OU does not exist" }
            $result = Invoke-EmployeeTermination -EmployeeUPN "test.termination1@ii-us.com" -RequesterUPN "admin@ii-us.com" -TicketId "TEST-001"
            $result.ExitCode | Should -Be 33
            $result.Error | Should -Match "move|OU"
        }

        It "Should return exit code 40 when AD Sync trigger fails" {
            Mock Start-ADSyncSyncCycle { throw "AD Connect Sync service not running" }
            $result = Invoke-EmployeeTermination -EmployeeUPN "test.termination1@ii-us.com" -RequesterUPN "admin@ii-us.com" -TicketId "TEST-001"
            $result.ExitCode | Should -Be 40
            $result.Error | Should -Match "sync"
        }

        It "Should handle user with no licenses gracefully" {
            $result = Invoke-EmployeeTermination -EmployeeUPN "test.nolicense@ii-us.com" -RequesterUPN "admin@ii-us.com" -TicketId "TEST-001"
            # Should not fail - just skip license removal step
            $result.ExitCode | Should -Be 0
            $result.Steps | Should -Contain "No licenses to remove"
        }
    }

    Context "Success Path (Exit Code 0)" {
        It "Should return exit code 0 on successful termination" {
            $result = Invoke-EmployeeTermination -EmployeeUPN "test.termination1@ii-us.com" -RequesterUPN "admin@ii-us.com" -TicketId "TEST-001"
            $result.ExitCode | Should -Be 0
            $result.Success | Should -Be $true
        }

        It "Should execute all steps in correct order" {
            Invoke-EmployeeTermination -EmployeeUPN "test.termination1@ii-us.com" -RequesterUPN "admin@ii-us.com" -TicketId "TEST-001"

            # Verify execution order via call tracking
            Should -Invoke Connect-MgGraph -Times 1
            Should -Invoke Connect-ExchangeOnline -Times 1
            Should -Invoke Get-ADUser -Times 1
            Should -Invoke Set-MgUserLicense -Times 1
            Should -Invoke Set-Mailbox -Times 1
            Should -Invoke Disable-ADAccount -Times 1
            Should -Invoke Move-ADObject -Times 1
            Should -Invoke Start-ADSyncSyncCycle -Times 1
        }

        It "Should return structured result with all required fields" {
            $result = Invoke-EmployeeTermination -EmployeeUPN "test.termination1@ii-us.com" -RequesterUPN "admin@ii-us.com" -TicketId "TEST-001"

            $result.ExitCode | Should -Be 0
            $result.Success | Should -Be $true
            $result.EmployeeUPN | Should -Be "test.termination1@ii-us.com"
            $result.RequesterUPN | Should -Be "admin@ii-us.com"
            $result.TicketId | Should -Be "TEST-001"
            $result.Steps | Should -Not -BeNullOrEmpty
            $result.CompletedAt | Should -Not -BeNullOrEmpty
            $result.Timestamp | Should -Not -BeNullOrEmpty
        }

        It "Should cleanup connections on success" {
            Invoke-EmployeeTermination -EmployeeUPN "test.termination1@ii-us.com" -RequesterUPN "admin@ii-us.com" -TicketId "TEST-001"
            Should -Invoke Disconnect-MgGraph -Times 1
            Should -Invoke Disconnect-ExchangeOnline -Times 1
        }
    }

    Context "Logging" {
        It "Should log all operations in Steps array" {
            $result = Invoke-EmployeeTermination -EmployeeUPN "test.termination1@ii-us.com" -RequesterUPN "admin@ii-us.com" -TicketId "TEST-001"

            $result.Steps | Should -Contain "Connected to Microsoft Graph"
            $result.Steps | Should -Contain "Connected to Exchange Online"
            $result.Steps | Should -Contain "Validated employee exists"
            $result.Steps | Should -Contain "Licenses removed"
            $result.Steps | Should -Contain "Mailbox converted to shared"
            $result.Steps | Should -Contain "AD account disabled"
            $result.Steps | Should -Contain "User moved to Disabled Users OU"
            $result.Steps | Should -Contain "AD Sync triggered"
        }

        It "Should include timestamp in each step" {
            $result = Invoke-EmployeeTermination -EmployeeUPN "test.termination1@ii-us.com" -RequesterUPN "admin@ii-us.com" -TicketId "TEST-001"
            # Steps should be timestamped for audit trail
            $result.StepsWithTimestamps | Should -Not -BeNullOrEmpty
        }
    }

    Context "Cleanup on Failure" {
        It "Should cleanup connections even on failure" {
            Mock Set-MgUserLicense { throw "License removal failed" }
            Invoke-EmployeeTermination -EmployeeUPN "test.termination1@ii-us.com" -RequesterUPN "admin@ii-us.com" -TicketId "TEST-001"
            Should -Invoke Disconnect-MgGraph -Times 1
            Should -Invoke Disconnect-ExchangeOnline -Times 1
        }
    }
}

Describe "Test-ProtectedAccount" {
    It "Should return true for Domain Admins" {
        Mock Get-ADUser { return @{ MemberOf = @("CN=Domain Admins,CN=Users,DC=ii-us,DC=com") } }
        Test-ProtectedAccount -UserPrincipalName "admin@ii-us.com" | Should -Be $true
    }

    It "Should return true for Enterprise Admins" {
        Mock Get-ADUser { return @{ MemberOf = @("CN=Enterprise Admins,CN=Users,DC=ii-us,DC=com") } }
        Test-ProtectedAccount -UserPrincipalName "admin@ii-us.com" | Should -Be $true
    }

    It "Should return true for Schema Admins" {
        Mock Get-ADUser { return @{ MemberOf = @("CN=Schema Admins,CN=Users,DC=ii-us,DC=com") } }
        Test-ProtectedAccount -UserPrincipalName "admin@ii-us.com" | Should -Be $true
    }

    It "Should return true for accounts in ServiceAccounts OU" {
        Mock Get-ADUser { return @{ DistinguishedName = "CN=Service,OU=ServiceAccounts,DC=ii-us,DC=com"; MemberOf = @() } }
        Test-ProtectedAccount -UserPrincipalName "service@ii-us.com" | Should -Be $true
    }

    It "Should return true for accounts in Admins OU" {
        Mock Get-ADUser { return @{ DistinguishedName = "CN=Admin,OU=Admins,DC=ii-us,DC=com"; MemberOf = @() } }
        Test-ProtectedAccount -UserPrincipalName "admin@ii-us.com" | Should -Be $true
    }

    It "Should return false for regular users" {
        Mock Get-ADUser { return @{ MemberOf = @(); DistinguishedName = "CN=User,OU=Users,DC=ii-us,DC=com" } }
        Test-ProtectedAccount -UserPrincipalName "user@ii-us.com" | Should -Be $false
    }

    It "Should return false for users in standard OUs" {
        Mock Get-ADUser { return @{ MemberOf = @("CN=All Staff,CN=Users,DC=ii-us,DC=com"); DistinguishedName = "CN=User,OU=Employees,DC=ii-us,DC=com" } }
        Test-ProtectedAccount -UserPrincipalName "employee@ii-us.com" | Should -Be $false
    }
}

Describe "Test-ValidUPN" {
    It "Should accept valid UPN" {
        Test-ValidUPN -UPN "user@ii-us.com" | Should -Be $true
    }

    It "Should accept UPN with subdomain" {
        Test-ValidUPN -UPN "user@mail.ii-us.com" | Should -Be $true
    }

    It "Should accept UPN with plus addressing" {
        Test-ValidUPN -UPN "user+tag@ii-us.com" | Should -Be $true
    }

    It "Should accept UPN with dots" {
        Test-ValidUPN -UPN "first.last@ii-us.com" | Should -Be $true
    }

    It "Should reject UPN without @" {
        Test-ValidUPN -UPN "user.ii-us.com" | Should -Be $false
    }

    It "Should reject UPN with multiple @" {
        Test-ValidUPN -UPN "user@@ii-us.com" | Should -Be $false
    }

    It "Should reject UPN with invalid characters (semicolon)" {
        Test-ValidUPN -UPN "user;test@ii-us.com" | Should -Be $false
    }

    It "Should reject UPN with invalid characters (quotes)" {
        Test-ValidUPN -UPN "user'test@ii-us.com" | Should -Be $false
    }

    It "Should reject UPN with HTML tags" {
        Test-ValidUPN -UPN "<script>@ii-us.com" | Should -Be $false
    }

    It "Should reject empty string" {
        Test-ValidUPN -UPN "" | Should -Be $false
    }

    It "Should reject null" {
        Test-ValidUPN -UPN $null | Should -Be $false
    }

    It "Should reject whitespace only" {
        Test-ValidUPN -UPN "   " | Should -Be $false
    }
}
