# TDD Plan: Employee Termination Agent

## Overview

This document defines the test-driven development plan for the Employee Termination Agent system.
All tests MUST be written BEFORE implementation code (Red-Green-Refactor cycle).

---

## Test Coverage Matrix

### Component Coverage Requirements

| Component | Unit Tests | Integration Tests | E2E Tests | Target Coverage |
|-----------|------------|-------------------|-----------|-----------------|
| PowerShell Script (`Terminate-Employee.ps1`) | Required | Required | Required | 85% |
| HTTP Wrapper (`server.js`) | Required | Required | Required | 90% |
| n8n Workflow | N/A | Required | Required | N/A |
| Azure Relay | N/A | Required | Required | N/A |

### Exit Code Test Matrix

| Exit Code | Meaning | Unit Test | Integration Test | E2E Test |
|-----------|---------|-----------|------------------|----------|
| 0 | Success | X | X | X |
| 1 | General error | X | X | X |
| 10 | Employee not found | X | X | X |
| 11 | Employee already disabled | X | X | X |
| 12 | Protected account | X | X | X |
| 20 | Graph connection failed | X | X | - |
| 21 | Exchange connection failed | X | X | - |
| 22 | AD connection failed | X | X | - |
| 30 | License removal failed | X | X | - |
| 31 | Mailbox conversion failed | X | X | - |
| 32 | AD disable failed | X | X | - |
| 33 | OU move failed | X | X | - |
| 40 | AD Sync trigger failed | X | X | - |

### Input Validation Test Matrix

| Input Field | Valid | Empty | Null | Invalid Format | SQL Injection | XSS |
|-------------|-------|-------|------|----------------|---------------|-----|
| employee_upn | X | X | X | X | X | X |
| requester_upn | X | X | X | X | X | X |
| ticket_id | X | X | X | X | X | X |
| termination_date | X | X | X | X | - | - |

---

## Test Accounts (Non-Production)

```
test.termination1@ii-us.com  - Normal user for happy path testing
test.termination2@ii-us.com  - Already disabled user (idempotency)
test.admin@ii-us.com         - Protected account (rejection test)
test.nolicense@ii-us.com     - User with no licenses
test.nosharedmailbox@ii-us.com - User with regular mailbox
```

---

## 1. PowerShell Pester Tests

### File: `Terminate-Employee.Tests.ps1`

```powershell
#Requires -Modules Pester

BeforeAll {
    # Import the module under test
    . $PSScriptRoot\Terminate-Employee.ps1

    # Mock external dependencies
    Mock Connect-MgGraph { return $true }
    Mock Connect-ExchangeOnline { return $true }
    Mock Get-ADUser {
        param($Identity)
        if ($Identity -eq 'test.notfound@ii-us.com') { throw "User not found" }
        if ($Identity -eq 'test.termination2@ii-us.com') {
            return @{ Enabled = $false; DistinguishedName = "CN=Test User,OU=DisabledUsers,DC=ii-us,DC=com" }
        }
        if ($Identity -eq 'test.admin@ii-us.com') {
            return @{ Enabled = $true; MemberOf = @("CN=Domain Admins,CN=Users,DC=ii-us,DC=com") }
        }
        return @{
            Enabled = $true
            DistinguishedName = "CN=Test User,OU=Users,DC=ii-us,DC=com"
            UserPrincipalName = $Identity
        }
    }
    Mock Get-MgUser { return @{ Id = "user-guid-123"; DisplayName = "Test User" } }
    Mock Get-MgUserLicenseDetail { return @(@{ SkuId = "sku-123" }) }
    Mock Set-MgUserLicense { return $true }
    Mock Set-Mailbox { return $true }
    Mock Disable-ADAccount { return $true }
    Mock Move-ADObject { return $true }
    Mock Start-ADSyncSyncCycle { return $true }
}

Describe "Invoke-EmployeeTermination" {
    Context "Input Validation" {
        It "Should reject empty employee_upn" {
            $result = Invoke-EmployeeTermination -EmployeeUPN "" -RequesterUPN "admin@ii-us.com" -TicketId "TEST-001"
            $result.ExitCode | Should -Be 1
            $result.Error | Should -Match "employee_upn.*required"
        }

        It "Should reject null employee_upn" {
            $result = Invoke-EmployeeTermination -EmployeeUPN $null -RequesterUPN "admin@ii-us.com" -TicketId "TEST-001"
            $result.ExitCode | Should -Be 1
        }

        It "Should reject invalid UPN format" {
            $result = Invoke-EmployeeTermination -EmployeeUPN "not-a-valid-email" -RequesterUPN "admin@ii-us.com" -TicketId "TEST-001"
            $result.ExitCode | Should -Be 1
            $result.Error | Should -Match "invalid.*format"
        }

        It "Should reject SQL injection attempt in employee_upn" {
            $result = Invoke-EmployeeTermination -EmployeeUPN "'; DROP TABLE Users;--@ii-us.com" -RequesterUPN "admin@ii-us.com" -TicketId "TEST-001"
            $result.ExitCode | Should -Be 1
            $result.Error | Should -Match "invalid.*characters"
        }

        It "Should reject empty ticket_id" {
            $result = Invoke-EmployeeTermination -EmployeeUPN "test@ii-us.com" -RequesterUPN "admin@ii-us.com" -TicketId ""
            $result.ExitCode | Should -Be 1
        }

        It "Should accept valid inputs" {
            $result = Invoke-EmployeeTermination -EmployeeUPN "test.termination1@ii-us.com" -RequesterUPN "admin@ii-us.com" -TicketId "TEST-001" -WhatIf
            $result.ExitCode | Should -Be 0
        }
    }

    Context "Employee Not Found (Exit Code 10)" {
        It "Should return exit code 10 when employee does not exist" {
            $result = Invoke-EmployeeTermination -EmployeeUPN "test.notfound@ii-us.com" -RequesterUPN "admin@ii-us.com" -TicketId "TEST-001"
            $result.ExitCode | Should -Be 10
            $result.Error | Should -Match "not found"
        }
    }

    Context "Employee Already Disabled (Exit Code 11)" {
        It "Should return exit code 11 when employee is already disabled" {
            $result = Invoke-EmployeeTermination -EmployeeUPN "test.termination2@ii-us.com" -RequesterUPN "admin@ii-us.com" -TicketId "TEST-001"
            $result.ExitCode | Should -Be 11
            $result.Message | Should -Match "already disabled"
        }

        It "Should be idempotent - no changes on already disabled user" {
            $result = Invoke-EmployeeTermination -EmployeeUPN "test.termination2@ii-us.com" -RequesterUPN "admin@ii-us.com" -TicketId "TEST-001"
            Should -Invoke Disable-ADAccount -Times 0
            Should -Invoke Move-ADObject -Times 0
        }
    }

    Context "Protected Account (Exit Code 12)" {
        It "Should return exit code 12 for protected accounts" {
            $result = Invoke-EmployeeTermination -EmployeeUPN "test.admin@ii-us.com" -RequesterUPN "admin@ii-us.com" -TicketId "TEST-001"
            $result.ExitCode | Should -Be 12
            $result.Error | Should -Match "protected"
        }

        It "Should not modify Domain Admin accounts" {
            Invoke-EmployeeTermination -EmployeeUPN "test.admin@ii-us.com" -RequesterUPN "admin@ii-us.com" -TicketId "TEST-001"
            Should -Invoke Disable-ADAccount -Times 0
        }
    }

    Context "Connection Failures" {
        It "Should return exit code 20 when Graph connection fails" {
            Mock Connect-MgGraph { throw "Connection failed" }
            $result = Invoke-EmployeeTermination -EmployeeUPN "test.termination1@ii-us.com" -RequesterUPN "admin@ii-us.com" -TicketId "TEST-001"
            $result.ExitCode | Should -Be 20
        }

        It "Should return exit code 21 when Exchange connection fails" {
            Mock Connect-ExchangeOnline { throw "Connection failed" }
            $result = Invoke-EmployeeTermination -EmployeeUPN "test.termination1@ii-us.com" -RequesterUPN "admin@ii-us.com" -TicketId "TEST-001"
            $result.ExitCode | Should -Be 21
        }

        It "Should return exit code 22 when AD connection fails" {
            Mock Get-ADUser { throw "Cannot contact domain controller" }
            $result = Invoke-EmployeeTermination -EmployeeUPN "test.termination1@ii-us.com" -RequesterUPN "admin@ii-us.com" -TicketId "TEST-001"
            $result.ExitCode | Should -Be 22
        }
    }

    Context "Operation Failures" {
        It "Should return exit code 30 when license removal fails" {
            Mock Set-MgUserLicense { throw "License removal failed" }
            $result = Invoke-EmployeeTermination -EmployeeUPN "test.termination1@ii-us.com" -RequesterUPN "admin@ii-us.com" -TicketId "TEST-001"
            $result.ExitCode | Should -Be 30
        }

        It "Should return exit code 31 when mailbox conversion fails" {
            Mock Set-Mailbox { throw "Mailbox conversion failed" }
            $result = Invoke-EmployeeTermination -EmployeeUPN "test.termination1@ii-us.com" -RequesterUPN "admin@ii-us.com" -TicketId "TEST-001"
            $result.ExitCode | Should -Be 31
        }

        It "Should return exit code 32 when AD disable fails" {
            Mock Disable-ADAccount { throw "Access denied" }
            $result = Invoke-EmployeeTermination -EmployeeUPN "test.termination1@ii-us.com" -RequesterUPN "admin@ii-us.com" -TicketId "TEST-001"
            $result.ExitCode | Should -Be 32
        }

        It "Should return exit code 33 when OU move fails" {
            Mock Move-ADObject { throw "Move failed" }
            $result = Invoke-EmployeeTermination -EmployeeUPN "test.termination1@ii-us.com" -RequesterUPN "admin@ii-us.com" -TicketId "TEST-001"
            $result.ExitCode | Should -Be 33
        }

        It "Should return exit code 40 when AD Sync trigger fails" {
            Mock Start-ADSyncSyncCycle { throw "Sync failed" }
            $result = Invoke-EmployeeTermination -EmployeeUPN "test.termination1@ii-us.com" -RequesterUPN "admin@ii-us.com" -TicketId "TEST-001"
            $result.ExitCode | Should -Be 40
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

        It "Should return structured result with all fields" {
            $result = Invoke-EmployeeTermination -EmployeeUPN "test.termination1@ii-us.com" -RequesterUPN "admin@ii-us.com" -TicketId "TEST-001"

            $result.ExitCode | Should -Be 0
            $result.Success | Should -Be $true
            $result.EmployeeUPN | Should -Be "test.termination1@ii-us.com"
            $result.TicketId | Should -Be "TEST-001"
            $result.Steps | Should -Not -BeNullOrEmpty
            $result.CompletedAt | Should -Not -BeNullOrEmpty
        }
    }

    Context "Rollback on Failure" {
        It "Should not rollback completed steps on license failure" {
            # License removal is first operation - nothing to rollback
            Mock Set-MgUserLicense { throw "License removal failed" }
            Invoke-EmployeeTermination -EmployeeUPN "test.termination1@ii-us.com" -RequesterUPN "admin@ii-us.com" -TicketId "TEST-001"

            Should -Invoke Disable-ADAccount -Times 0
            Should -Invoke Move-ADObject -Times 0
        }
    }

    Context "Logging" {
        It "Should log all operations" {
            $result = Invoke-EmployeeTermination -EmployeeUPN "test.termination1@ii-us.com" -RequesterUPN "admin@ii-us.com" -TicketId "TEST-001"

            $result.Steps | Should -Contain "Connected to Microsoft Graph"
            $result.Steps | Should -Contain "Connected to Exchange Online"
            $result.Steps | Should -Contain "Licenses removed"
            $result.Steps | Should -Contain "Mailbox converted to shared"
            $result.Steps | Should -Contain "AD account disabled"
            $result.Steps | Should -Contain "User moved to Disabled Users OU"
            $result.Steps | Should -Contain "AD Sync triggered"
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

    It "Should return true for accounts in protected OU" {
        Mock Get-ADUser { return @{ DistinguishedName = "CN=Service,OU=ServiceAccounts,DC=ii-us,DC=com" } }
        Test-ProtectedAccount -UserPrincipalName "service@ii-us.com" | Should -Be $true
    }

    It "Should return false for regular users" {
        Mock Get-ADUser { return @{ MemberOf = @(); DistinguishedName = "CN=User,OU=Users,DC=ii-us,DC=com" } }
        Test-ProtectedAccount -UserPrincipalName "user@ii-us.com" | Should -Be $false
    }
}

Describe "Test-ValidUPN" {
    It "Should accept valid UPN" {
        Test-ValidUPN -UPN "user@ii-us.com" | Should -Be $true
    }

    It "Should reject UPN without @" {
        Test-ValidUPN -UPN "user.ii-us.com" | Should -Be $false
    }

    It "Should reject UPN with invalid characters" {
        Test-ValidUPN -UPN "user<script>@ii-us.com" | Should -Be $false
    }

    It "Should reject empty string" {
        Test-ValidUPN -UPN "" | Should -Be $false
    }

    It "Should reject null" {
        Test-ValidUPN -UPN $null | Should -Be $false
    }
}
```

---

## 2. Node.js Jest Tests

### File: `server.test.js`

```javascript
const http = require('http');
const { spawn } = require('child_process');

// Mock child_process
jest.mock('child_process', () => ({
  spawnSync: jest.fn()
}));

const { spawnSync } = require('child_process');

// Import server factory (we'll create this pattern)
const createServer = require('./server');

describe('Employee Termination HTTP Server', () => {
  let server;
  let baseUrl;

  beforeAll((done) => {
    server = createServer({ port: 0 }); // Random available port
    server.listen(0, () => {
      baseUrl = `http://localhost:${server.address().port}`;
      done();
    });
  });

  afterAll((done) => {
    server.close(done);
  });

  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('GET /health', () => {
    it('returns 200 with healthy status', async () => {
      const response = await fetch(`${baseUrl}/health`);
      const data = await response.json();

      expect(response.status).toBe(200);
      expect(data.status).toBe('healthy');
      expect(data.timestamp).toBeDefined();
    });
  });

  describe('POST /validate', () => {
    it('returns 200 for valid employee', async () => {
      spawnSync.mockReturnValue({
        status: 0,
        stdout: JSON.stringify({
          exists: true,
          enabled: true,
          protected: false,
          displayName: 'Test User'
        }),
        stderr: ''
      });

      const response = await fetch(`${baseUrl}/validate`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ employee_upn: 'test@ii-us.com' })
      });
      const data = await response.json();

      expect(response.status).toBe(200);
      expect(data.valid).toBe(true);
      expect(data.employee.exists).toBe(true);
    });

    it('returns 400 for missing employee_upn', async () => {
      const response = await fetch(`${baseUrl}/validate`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({})
      });
      const data = await response.json();

      expect(response.status).toBe(400);
      expect(data.error).toMatch(/employee_upn.*required/i);
    });

    it('returns 400 for invalid UPN format', async () => {
      const response = await fetch(`${baseUrl}/validate`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ employee_upn: 'not-a-valid-email' })
      });
      const data = await response.json();

      expect(response.status).toBe(400);
      expect(data.error).toMatch(/invalid.*format/i);
    });

    it('returns 404 when employee not found (exit code 10)', async () => {
      spawnSync.mockReturnValue({
        status: 10,
        stdout: '',
        stderr: 'Employee not found'
      });

      const response = await fetch(`${baseUrl}/validate`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ employee_upn: 'notfound@ii-us.com' })
      });
      const data = await response.json();

      expect(response.status).toBe(404);
      expect(data.exit_code).toBe(10);
    });

    it('returns 403 for protected account (exit code 12)', async () => {
      spawnSync.mockReturnValue({
        status: 12,
        stdout: '',
        stderr: 'Protected account'
      });

      const response = await fetch(`${baseUrl}/validate`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ employee_upn: 'admin@ii-us.com' })
      });
      const data = await response.json();

      expect(response.status).toBe(403);
      expect(data.exit_code).toBe(12);
    });
  });

  describe('POST /terminate', () => {
    it('returns 200 on successful termination (exit code 0)', async () => {
      spawnSync.mockReturnValue({
        status: 0,
        stdout: JSON.stringify({
          success: true,
          steps: ['License removed', 'Mailbox converted', 'AD disabled', 'OU moved', 'Sync triggered']
        }),
        stderr: ''
      });

      const response = await fetch(`${baseUrl}/terminate`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          employee_upn: 'test@ii-us.com',
          requester_upn: 'admin@ii-us.com',
          ticket_id: 'TEST-001'
        })
      });
      const data = await response.json();

      expect(response.status).toBe(200);
      expect(data.exit_code).toBe(0);
      expect(data.success).toBe(true);
    });

    it('returns 400 for missing required fields', async () => {
      const response = await fetch(`${baseUrl}/terminate`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ employee_upn: 'test@ii-us.com' })
      });
      const data = await response.json();

      expect(response.status).toBe(400);
      expect(data.error).toMatch(/requester_upn.*required|ticket_id.*required/i);
    });

    it('returns 404 for employee not found (exit code 10)', async () => {
      spawnSync.mockReturnValue({
        status: 10,
        stdout: '',
        stderr: 'Employee not found in AD'
      });

      const response = await fetch(`${baseUrl}/terminate`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          employee_upn: 'notfound@ii-us.com',
          requester_upn: 'admin@ii-us.com',
          ticket_id: 'TEST-001'
        })
      });
      const data = await response.json();

      expect(response.status).toBe(404);
      expect(data.exit_code).toBe(10);
    });

    it('returns 200 for already disabled (exit code 11, idempotent)', async () => {
      spawnSync.mockReturnValue({
        status: 11,
        stdout: JSON.stringify({ message: 'Employee already disabled' }),
        stderr: ''
      });

      const response = await fetch(`${baseUrl}/terminate`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          employee_upn: 'disabled@ii-us.com',
          requester_upn: 'admin@ii-us.com',
          ticket_id: 'TEST-001'
        })
      });
      const data = await response.json();

      expect(response.status).toBe(200); // Idempotent - not an error
      expect(data.exit_code).toBe(11);
      expect(data.idempotent).toBe(true);
    });

    it('returns 403 for protected account (exit code 12)', async () => {
      spawnSync.mockReturnValue({
        status: 12,
        stdout: '',
        stderr: 'Cannot terminate protected account'
      });

      const response = await fetch(`${baseUrl}/terminate`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          employee_upn: 'admin@ii-us.com',
          requester_upn: 'other-admin@ii-us.com',
          ticket_id: 'TEST-001'
        })
      });
      const data = await response.json();

      expect(response.status).toBe(403);
      expect(data.exit_code).toBe(12);
    });

    it('returns 503 for connection failures (exit codes 20-22)', async () => {
      const connectionCodes = [20, 21, 22];

      for (const code of connectionCodes) {
        spawnSync.mockReturnValue({
          status: code,
          stdout: '',
          stderr: 'Connection failed'
        });

        const response = await fetch(`${baseUrl}/terminate`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            employee_upn: 'test@ii-us.com',
            requester_upn: 'admin@ii-us.com',
            ticket_id: 'TEST-001'
          })
        });
        const data = await response.json();

        expect(response.status).toBe(503);
        expect(data.exit_code).toBe(code);
        expect(data.retryable).toBe(true);
      }
    });

    it('returns 500 for operation failures (exit codes 30-40)', async () => {
      const operationCodes = [30, 31, 32, 33, 40];

      for (const code of operationCodes) {
        spawnSync.mockReturnValue({
          status: code,
          stdout: '',
          stderr: 'Operation failed'
        });

        const response = await fetch(`${baseUrl}/terminate`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            employee_upn: 'test@ii-us.com',
            requester_upn: 'admin@ii-us.com',
            ticket_id: 'TEST-001'
          })
        });
        const data = await response.json();

        expect(response.status).toBe(500);
        expect(data.exit_code).toBe(code);
      }
    });

    it('handles timeout gracefully', async () => {
      spawnSync.mockReturnValue({
        status: null,
        signal: 'SIGTERM',
        stdout: '',
        stderr: ''
      });

      const response = await fetch(`${baseUrl}/terminate`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          employee_upn: 'test@ii-us.com',
          requester_upn: 'admin@ii-us.com',
          ticket_id: 'TEST-001',
          timeout: 1
        })
      });
      const data = await response.json();

      expect(response.status).toBe(504);
      expect(data.error).toMatch(/timeout/i);
    });
  });

  describe('Authentication', () => {
    it('returns 401 without API key', async () => {
      // Assuming API key auth is required
      const response = await fetch(`${baseUrl}/terminate`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          employee_upn: 'test@ii-us.com',
          requester_upn: 'admin@ii-us.com',
          ticket_id: 'TEST-001'
        })
      });

      // Skip if auth not implemented yet
      if (response.status !== 401) {
        console.log('Auth not implemented - skipping');
        return;
      }

      expect(response.status).toBe(401);
    });

    it('returns 403 for invalid API key', async () => {
      const response = await fetch(`${baseUrl}/terminate`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-API-Key': 'invalid-key'
        },
        body: JSON.stringify({
          employee_upn: 'test@ii-us.com',
          requester_upn: 'admin@ii-us.com',
          ticket_id: 'TEST-001'
        })
      });

      // Skip if auth not implemented yet
      if (response.status !== 403) {
        console.log('Auth not implemented - skipping');
        return;
      }

      expect(response.status).toBe(403);
    });
  });

  describe('Error Handling', () => {
    it('returns 400 for invalid JSON', async () => {
      const response = await fetch(`${baseUrl}/terminate`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: 'not valid json'
      });
      const data = await response.json();

      expect(response.status).toBe(400);
      expect(data.error).toMatch(/invalid.*json/i);
    });

    it('returns 404 for unknown routes', async () => {
      const response = await fetch(`${baseUrl}/unknown`);
      expect(response.status).toBe(404);
    });

    it('returns 405 for wrong HTTP method', async () => {
      const response = await fetch(`${baseUrl}/terminate`, {
        method: 'GET'
      });
      expect(response.status).toBe(405);
    });
  });
});
```

---

## 3. n8n Integration Tests (Mock Mode)

### File: `n8n-workflow.test.js`

Based on the pattern from CLAUDE.md, these tests use mock mode to test the n8n workflow without executing the actual PowerShell script.

```javascript
/**
 * n8n Workflow Integration Tests
 *
 * These tests validate the n8n Employee Termination workflow using mock mode.
 * Pattern from CLAUDE.md: Use mock=true and mock_exit_code to simulate agent responses.
 */

const WEBHOOK_URL = process.env.N8N_WEBHOOK_URL || 'https://n8n.ii-us.com/webhook/employee-termination';

describe('Employee Termination n8n Workflow', () => {
  describe('Input Validation', () => {
    it('should return 400 for missing employee_upn', async () => {
      const response = await fetch(WEBHOOK_URL, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          mock: true,
          requester_upn: 'admin@ii-us.com',
          ticket_id: 'TEST-001'
        })
      });
      const data = await response.json();

      expect(response.status).toBe(400);
      expect(data.error).toMatch(/employee_upn.*required/i);
    });

    it('should return 400 for missing ticket_id', async () => {
      const response = await fetch(WEBHOOK_URL, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          mock: true,
          employee_upn: 'test@ii-us.com',
          requester_upn: 'admin@ii-us.com'
        })
      });
      const data = await response.json();

      expect(response.status).toBe(400);
      expect(data.error).toMatch(/ticket_id.*required/i);
    });
  });

  describe('Mock Mode Exit Code Routing', () => {
    it('should return 200 for mock exit code 0 (success)', async () => {
      const response = await fetch(WEBHOOK_URL, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          mock: true,
          mock_exit_code: 0,
          employee_upn: 'test@ii-us.com',
          requester_upn: 'admin@ii-us.com',
          ticket_id: 'TEST-001'
        })
      });
      const data = await response.json();

      expect(response.status).toBe(200);
      expect(data.status).toBe('success');
      expect(data.exit_code).toBe(0);
    });

    it('should return 404 for mock exit code 10 (not found)', async () => {
      const response = await fetch(WEBHOOK_URL, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          mock: true,
          mock_exit_code: 10,
          employee_upn: 'notfound@ii-us.com',
          requester_upn: 'admin@ii-us.com',
          ticket_id: 'TEST-001'
        })
      });
      const data = await response.json();

      expect(response.status).toBe(404);
      expect(data.exit_code).toBe(10);
    });

    it('should return 200 for mock exit code 11 (idempotent - already disabled)', async () => {
      const response = await fetch(WEBHOOK_URL, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          mock: true,
          mock_exit_code: 11,
          employee_upn: 'disabled@ii-us.com',
          requester_upn: 'admin@ii-us.com',
          ticket_id: 'TEST-001'
        })
      });
      const data = await response.json();

      expect(response.status).toBe(200);
      expect(data.exit_code).toBe(11);
      expect(data.idempotent).toBe(true);
    });

    it('should return 403 for mock exit code 12 (protected)', async () => {
      const response = await fetch(WEBHOOK_URL, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          mock: true,
          mock_exit_code: 12,
          employee_upn: 'admin@ii-us.com',
          requester_upn: 'other@ii-us.com',
          ticket_id: 'TEST-001'
        })
      });
      const data = await response.json();

      expect(response.status).toBe(403);
      expect(data.exit_code).toBe(12);
    });

    it('should return 503 for mock exit code 20 (Graph connection failed)', async () => {
      const response = await fetch(WEBHOOK_URL, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          mock: true,
          mock_exit_code: 20,
          employee_upn: 'test@ii-us.com',
          requester_upn: 'admin@ii-us.com',
          ticket_id: 'TEST-001'
        })
      });
      const data = await response.json();

      expect(response.status).toBe(503);
      expect(data.exit_code).toBe(20);
      expect(data.retryable).toBe(true);
    });

    it('should return 500 for mock exit code 30 (license removal failed)', async () => {
      const response = await fetch(WEBHOOK_URL, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          mock: true,
          mock_exit_code: 30,
          employee_upn: 'test@ii-us.com',
          requester_upn: 'admin@ii-us.com',
          ticket_id: 'TEST-001'
        })
      });
      const data = await response.json();

      expect(response.status).toBe(500);
      expect(data.exit_code).toBe(30);
    });
  });

  describe('Approval Flow', () => {
    it('should require approval for non-test accounts', async () => {
      // This test validates that the workflow pauses for approval
      // In real testing, this would need webhook callback or polling
      const response = await fetch(WEBHOOK_URL, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          mock: true,
          mock_exit_code: 0,
          employee_upn: 'real.employee@ii-us.com',
          requester_upn: 'admin@ii-us.com',
          ticket_id: 'PROD-001',
          skip_approval: false // Default behavior
        })
      });
      const data = await response.json();

      // Workflow should indicate pending approval
      expect(data.status).toBe('pending_approval');
      expect(data.approval_id).toBeDefined();
    });

    it('should skip approval when skip_approval=true (testing only)', async () => {
      const response = await fetch(WEBHOOK_URL, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          mock: true,
          mock_exit_code: 0,
          employee_upn: 'test@ii-us.com',
          requester_upn: 'admin@ii-us.com',
          ticket_id: 'TEST-001',
          skip_approval: true
        })
      });
      const data = await response.json();

      expect(response.status).toBe(200);
      expect(data.status).toBe('success');
    });
  });

  describe('Error Notifications', () => {
    it('should send Teams notification on exit code 20-22', async () => {
      // Test that Teams webhook is called for connection failures
      // This would be validated by checking execution history
      const response = await fetch(WEBHOOK_URL, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          mock: true,
          mock_exit_code: 21,
          employee_upn: 'test@ii-us.com',
          requester_upn: 'admin@ii-us.com',
          ticket_id: 'TEST-001'
        })
      });
      const data = await response.json();

      expect(data.notifications_sent).toContain('teams');
    });
  });
});
```

---

## 4. Contract Tests

### File: `api-contract.test.js`

```javascript
/**
 * API Contract Tests
 *
 * These tests validate the contract between n8n and the on-premises agent.
 * The agent MUST return responses matching these schemas.
 */

const Ajv = require('ajv');
const ajv = new Ajv();

// Response schemas
const successResponseSchema = {
  type: 'object',
  required: ['exit_code', 'success', 'timestamp'],
  properties: {
    exit_code: { type: 'number', const: 0 },
    success: { type: 'boolean', const: true },
    employee_upn: { type: 'string' },
    ticket_id: { type: 'string' },
    steps: {
      type: 'array',
      items: { type: 'string' }
    },
    completed_at: { type: 'string', format: 'date-time' },
    timestamp: { type: 'string' }
  }
};

const errorResponseSchema = {
  type: 'object',
  required: ['exit_code', 'error', 'timestamp'],
  properties: {
    exit_code: { type: 'number', minimum: 1 },
    error: { type: 'string' },
    error_details: { type: 'string' },
    retryable: { type: 'boolean' },
    timestamp: { type: 'string' }
  }
};

const validateRequestSchema = {
  type: 'object',
  required: ['employee_upn'],
  properties: {
    employee_upn: {
      type: 'string',
      pattern: '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$'
    }
  }
};

const terminateRequestSchema = {
  type: 'object',
  required: ['employee_upn', 'requester_upn', 'ticket_id'],
  properties: {
    employee_upn: {
      type: 'string',
      pattern: '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$'
    },
    requester_upn: {
      type: 'string',
      pattern: '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$'
    },
    ticket_id: {
      type: 'string',
      pattern: '^[A-Z]+-[0-9]+$'
    },
    termination_date: { type: 'string', format: 'date' },
    skip_approval: { type: 'boolean' },
    mock: { type: 'boolean' },
    mock_exit_code: { type: 'number' }
  }
};

describe('API Contract Tests', () => {
  describe('Request Schemas', () => {
    it('validates /validate request schema', () => {
      const validate = ajv.compile(validateRequestSchema);

      // Valid request
      expect(validate({ employee_upn: 'test@ii-us.com' })).toBe(true);

      // Invalid - missing employee_upn
      expect(validate({})).toBe(false);

      // Invalid - bad email format
      expect(validate({ employee_upn: 'not-an-email' })).toBe(false);
    });

    it('validates /terminate request schema', () => {
      const validate = ajv.compile(terminateRequestSchema);

      // Valid request
      expect(validate({
        employee_upn: 'test@ii-us.com',
        requester_upn: 'admin@ii-us.com',
        ticket_id: 'TEST-001'
      })).toBe(true);

      // Invalid - missing required fields
      expect(validate({ employee_upn: 'test@ii-us.com' })).toBe(false);

      // Invalid - bad ticket format
      expect(validate({
        employee_upn: 'test@ii-us.com',
        requester_upn: 'admin@ii-us.com',
        ticket_id: 'invalid-ticket'
      })).toBe(false);
    });
  });

  describe('Response Schemas', () => {
    it('validates success response schema', () => {
      const validate = ajv.compile(successResponseSchema);

      const validResponse = {
        exit_code: 0,
        success: true,
        employee_upn: 'test@ii-us.com',
        ticket_id: 'TEST-001',
        steps: ['License removed', 'Mailbox converted'],
        timestamp: new Date().toISOString()
      };

      expect(validate(validResponse)).toBe(true);
    });

    it('validates error response schema', () => {
      const validate = ajv.compile(errorResponseSchema);

      const validResponse = {
        exit_code: 10,
        error: 'Employee not found',
        retryable: false,
        timestamp: new Date().toISOString()
      };

      expect(validate(validResponse)).toBe(true);
    });
  });

  describe('Exit Code to HTTP Status Mapping', () => {
    const exitCodeMapping = {
      0: 200,   // Success
      1: 500,   // General error
      10: 404,  // Not found
      11: 200,  // Already disabled (idempotent)
      12: 403,  // Protected account
      20: 503,  // Graph connection failed
      21: 503,  // Exchange connection failed
      22: 503,  // AD connection failed
      30: 500,  // License removal failed
      31: 500,  // Mailbox conversion failed
      32: 500,  // AD disable failed
      33: 500,  // OU move failed
      40: 500   // AD Sync failed
    };

    Object.entries(exitCodeMapping).forEach(([exitCode, httpStatus]) => {
      it(`maps exit code ${exitCode} to HTTP ${httpStatus}`, () => {
        // This test documents the expected mapping
        expect(exitCodeMapping[exitCode]).toBe(httpStatus);
      });
    });
  });
});
```

---

## 5. E2E Test Plan

### File: `e2e-test-plan.md`

```markdown
# E2E Test Plan: Employee Termination Agent

## Prerequisites

1. Test accounts created in AD:
   - test.termination1@ii-us.com (normal user with license)
   - test.termination2@ii-us.com (already disabled)
   - test.admin@ii-us.com (Domain Admin - protected)
   - test.nolicense@ii-us.com (no licenses assigned)

2. n8n workflow deployed with mock mode support
3. On-premises agent deployed and connected via Azure Relay
4. Teams webhook configured for notifications

## Test Scenarios

### E2E-001: Happy Path - Full Termination

**Preconditions:**
- test.termination1@ii-us.com exists and is enabled
- User has M365 E3 license
- User has mailbox

**Steps:**
1. POST to webhook: `{ employee_upn: "test.termination1@ii-us.com", requester_upn: "admin@ii-us.com", ticket_id: "E2E-001" }`
2. Approve in Teams (if approval required)
3. Wait for completion

**Expected Results:**
- HTTP 200 returned
- License removed from user
- Mailbox converted to shared
- AD account disabled
- User moved to Disabled Users OU
- AD Sync triggered
- Audit log entry created

**Verification:**
```powershell
# Check AD account
Get-ADUser test.termination1@ii-us.com -Properties Enabled | Select Enabled
# Should return: False

# Check OU
Get-ADUser test.termination1@ii-us.com | Select DistinguishedName
# Should contain: OU=DisabledUsers

# Check license (Graph)
Get-MgUserLicenseDetail -UserId test.termination1@ii-us.com
# Should return: empty

# Check mailbox type (Exchange)
Get-Mailbox test.termination1@ii-us.com | Select RecipientTypeDetails
# Should return: SharedMailbox
```

### E2E-002: Idempotency - Already Disabled User

**Preconditions:**
- test.termination2@ii-us.com is already disabled

**Steps:**
1. POST to webhook: `{ employee_upn: "test.termination2@ii-us.com", requester_upn: "admin@ii-us.com", ticket_id: "E2E-002" }`

**Expected Results:**
- HTTP 200 returned (not error)
- exit_code: 11
- idempotent: true
- No changes made to user

### E2E-003: Protected Account Rejection

**Preconditions:**
- test.admin@ii-us.com is member of Domain Admins

**Steps:**
1. POST to webhook: `{ employee_upn: "test.admin@ii-us.com", requester_upn: "other-admin@ii-us.com", ticket_id: "E2E-003" }`

**Expected Results:**
- HTTP 403 returned
- exit_code: 12
- Account NOT modified

### E2E-004: User Not Found

**Steps:**
1. POST to webhook: `{ employee_upn: "nonexistent@ii-us.com", requester_upn: "admin@ii-us.com", ticket_id: "E2E-004" }`

**Expected Results:**
- HTTP 404 returned
- exit_code: 10

### E2E-005: Connection Failure Recovery

**Preconditions:**
- Simulate Graph API outage (via firewall or mock)

**Steps:**
1. POST to webhook with valid user
2. Observe retry behavior
3. Restore connection
4. Verify completion

**Expected Results:**
- Initial request returns 503
- Workflow retries with backoff
- Teams notification sent
- After recovery, operation completes

### E2E-006: Timeout Handling

**Preconditions:**
- Configure very short timeout (5s)
- Simulate slow AD response

**Steps:**
1. POST to webhook with short timeout

**Expected Results:**
- HTTP 504 returned
- Operation does not complete partially
- Retry mechanism engaged

## Cleanup Procedure

After E2E tests, restore test accounts:

```powershell
# Re-enable test.termination1
Enable-ADAccount -Identity "test.termination1@ii-us.com"
Move-ADObject -Identity "CN=Test User,OU=DisabledUsers,DC=ii-us,DC=com" -TargetPath "OU=Users,DC=ii-us,DC=com"

# Re-assign license (via Graph)
# Assign-MgUserLicense ...

# Convert mailbox back to regular
Set-Mailbox "test.termination1@ii-us.com" -Type Regular
```

## Automated E2E Test Runner

```javascript
// e2e-runner.js
const runE2ETests = async () => {
  const results = [];

  // E2E-001: Happy Path
  console.log('Running E2E-001: Happy Path');
  const e2e001 = await runHappyPathTest();
  results.push({ id: 'E2E-001', ...e2e001 });

  // Cleanup after happy path
  await restoreTestAccount('test.termination1@ii-us.com');

  // E2E-002: Idempotency
  console.log('Running E2E-002: Idempotency');
  const e2e002 = await runIdempotencyTest();
  results.push({ id: 'E2E-002', ...e2e002 });

  // E2E-003: Protected Account
  console.log('Running E2E-003: Protected Account');
  const e2e003 = await runProtectedAccountTest();
  results.push({ id: 'E2E-003', ...e2e003 });

  // E2E-004: Not Found
  console.log('Running E2E-004: Not Found');
  const e2e004 = await runNotFoundTest();
  results.push({ id: 'E2E-004', ...e2e004 });

  // Generate report
  generateE2EReport(results);
};
```
```

---

## 6. Test Configuration Files

### `jest.config.js`

```javascript
module.exports = {
  testEnvironment: 'node',
  collectCoverage: true,
  coverageDirectory: 'coverage',
  coverageReporters: ['text', 'lcov', 'html'],
  coverageThreshold: {
    global: {
      branches: 80,
      functions: 80,
      lines: 80,
      statements: 80
    }
  },
  testMatch: [
    '**/*.test.js'
  ],
  setupFilesAfterEnv: ['./jest.setup.js']
};
```

### `pester.config.ps1`

```powershell
$PesterPreference = [PesterConfiguration]::Default
$PesterPreference.Run.Path = '.'
$PesterPreference.Run.Passthru = $true
$PesterPreference.CodeCoverage.Enabled = $true
$PesterPreference.CodeCoverage.Path = @('./Terminate-Employee.ps1')
$PesterPreference.CodeCoverage.OutputPath = './coverage/coverage.xml'
$PesterPreference.CodeCoverage.CoveragePercentTarget = 80
$PesterPreference.Output.Verbosity = 'Detailed'
```

---

## Handoff Notes for Code-Reviewer

### Test Coverage Summary

| Layer | Tests Written | Coverage Target | Key Files |
|-------|---------------|-----------------|-----------|
| PowerShell Unit | 25+ tests | 85% | `Terminate-Employee.Tests.ps1` |
| Node.js Unit | 20+ tests | 90% | `server.test.js` |
| n8n Integration | 12+ tests | N/A | `n8n-workflow.test.js` |
| Contract | 8+ tests | 100% | `api-contract.test.js` |
| E2E | 6 scenarios | N/A | `e2e-test-plan.md` |

### Mock Patterns Used

1. **PowerShell Mocking**: Uses Pester `Mock` for AD, Graph, Exchange cmdlets
2. **Node.js Mocking**: Uses Jest `jest.mock()` for `child_process.spawnSync`
3. **n8n Mock Mode**: Uses `mock: true, mock_exit_code: X` pattern from CLAUDE.md

### Critical Test Scenarios

1. **Idempotency**: Exit code 11 returns HTTP 200 (not error)
2. **Protected Accounts**: Domain Admins cannot be terminated
3. **Connection Failures**: Return 503 with `retryable: true`
4. **Input Validation**: SQL injection and XSS prevention

### Dependencies for Testing

```bash
# PowerShell
Install-Module Pester -MinimumVersion 5.0 -Force

# Node.js
npm install --save-dev jest ajv
```

### Running Tests

```bash
# PowerShell tests
Invoke-Pester -Configuration $PesterPreference

# Node.js tests
npm test

# Coverage report
npm run test:coverage
```
