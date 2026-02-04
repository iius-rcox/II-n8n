# HANDOFF: tdd-guide -> code-reviewer

## Context

The TDD-GUIDE agent has completed the test-first development plan for the Employee Termination Agent system. All test specifications and sample implementations are ready for review.

## Workflow Position

```
planner -> [tdd-guide] -> code-reviewer -> security-reviewer
            ^^^^^^^^^
            COMPLETED
```

---

## Deliverables Created

### 1. TDD Plan Document

**File:** `C:\Users\rcox\OneDrive - INSULATIONS, INC\Documents\Cursor Projects\II-n8n\agents\employee-termination\TDD-PLAN.md`

Contains:
- Complete test coverage matrix
- Exit code test scenarios
- Input validation test scenarios
- Test account requirements
- E2E test plan

### 2. PowerShell Pester Tests

**File:** `C:\Users\rcox\OneDrive - INSULATIONS, INC\Documents\Cursor Projects\II-n8n\agents\employee-termination\tests\Terminate-Employee.Tests.ps1`

**Test Count:** 45+ test cases

**Coverage Areas:**
- Input validation (empty, null, invalid format, SQL injection, XSS)
- Exit code handling (0, 1, 10, 11, 12, 20-22, 30-33, 40)
- Protected account detection (Domain Admins, Enterprise Admins, ServiceAccounts OU)
- Connection failure handling
- Operation failure handling
- Idempotency verification
- Cleanup/disconnect behavior
- Logging verification

### 3. Node.js Jest Tests

**File:** `C:\Users\rcox\OneDrive - INSULATIONS, INC\Documents\Cursor Projects\II-n8n\agents\employee-termination\tests\server.test.js`

**Test Count:** 40+ test cases

**Coverage Areas:**
- Health endpoint
- Validate endpoint (all exit codes)
- Terminate endpoint (all exit codes)
- HTTP status mapping
- Error handling (invalid JSON, 404, 405)
- CORS headers
- Request logging
- Input sanitization

### 4. n8n Integration Tests

**File:** `C:\Users\rcox\OneDrive - INSULATIONS, INC\Documents\Cursor Projects\II-n8n\agents\employee-termination\tests\n8n-workflow.test.js`

**Test Count:** 25+ test cases

**Coverage Areas:**
- Input validation via webhook
- Mock mode exit code routing
- Response structure validation
- Approval flow testing
- Notification verification
- Execution metadata

### 5. API Contract Tests

**File:** `C:\Users\rcox\OneDrive - INSULATIONS, INC\Documents\Cursor Projects\II-n8n\agents\employee-termination\tests\api-contract.test.js`

**Test Count:** 30+ test cases

**Coverage Areas:**
- Request schema validation (validate, terminate)
- Response schema validation (success, error, idempotent)
- Exit code to HTTP status mapping
- Security constraints (SQL injection, XSS, length limits)
- Content type requirements

### 6. Configuration Files

| File | Purpose |
|------|---------|
| `package.json` | Node.js dependencies and test scripts |
| `jest.config.js` | Jest configuration with 80% coverage threshold |
| `jest.setup.js` | Global test utilities and custom matchers |
| `tests/pester.config.ps1` | Pester configuration with 80% coverage target |

---

## Test Coverage Matrix Summary

| Component | Unit Tests | Integration | E2E | Target |
|-----------|------------|-------------|-----|--------|
| `Terminate-Employee.ps1` | 45+ | Via HTTP | Yes | 85% |
| `server.js` | 40+ | 25+ | Yes | 90% |
| n8n Workflow | N/A | 25+ | Yes | N/A |

## Exit Code Coverage

All exit codes have corresponding tests:

| Code | Meaning | PS Test | Node Test | n8n Test |
|------|---------|---------|-----------|----------|
| 0 | Success | Y | Y | Y |
| 1 | General error | Y | Y | Y |
| 10 | Not found | Y | Y | Y |
| 11 | Already disabled | Y | Y | Y |
| 12 | Protected | Y | Y | Y |
| 20 | Graph failed | Y | Y | Y |
| 21 | Exchange failed | Y | Y | Y |
| 22 | AD failed | Y | Y | Y |
| 30 | License failed | Y | Y | Y |
| 31 | Mailbox failed | Y | Y | Y |
| 32 | AD disable failed | Y | Y | Y |
| 33 | OU move failed | Y | Y | Y |
| 40 | Sync failed | Y | Y | Y |

---

## Mock Patterns Used

### 1. PowerShell Mocking (Pester)

```powershell
Mock Get-ADUser {
    param($Identity)
    switch -Regex ($Identity) {
        'test\.notfound@' { throw "Cannot find user" }
        'test\.admin@' { return @{ MemberOf = @("CN=Domain Admins,...") } }
        default { return @{ Enabled = $true; ... } }
    }
}
```

### 2. Node.js Mocking (Jest)

```javascript
jest.mock('child_process', () => ({
  spawnSync: jest.fn()
}));

spawnSync.mockReturnValue({
  status: 0,
  stdout: JSON.stringify({ success: true }),
  stderr: ''
});
```

### 3. n8n Mock Mode (from CLAUDE.md pattern)

```json
{
  "mock": true,
  "mock_exit_code": 12,
  "employee_upn": "admin@ii-us.com",
  "skip_approval": true
}
```

---

## Review Checklist for Code-Reviewer

### Test Quality

- [ ] Tests are independent (no shared state between tests)
- [ ] Tests have descriptive names that explain what is being tested
- [ ] Each test has a single assertion focus
- [ ] Edge cases are covered (null, empty, invalid, boundary)
- [ ] Error paths are tested, not just happy paths
- [ ] Mocks are properly scoped and reset

### Coverage

- [ ] All public functions have unit tests
- [ ] All API endpoints have integration tests
- [ ] All exit codes are tested
- [ ] Input validation covers security concerns
- [ ] Idempotency is properly tested

### Schema Compliance

- [ ] Request schemas match API contract
- [ ] Response schemas match API contract
- [ ] Exit code to HTTP status mapping is correct
- [ ] Content-Type headers are validated

### Security Tests

- [ ] SQL injection attempts are rejected
- [ ] XSS attempts are rejected
- [ ] Shell metacharacter injection is prevented
- [ ] Protected accounts cannot be terminated
- [ ] Input length limits are enforced

### n8n Integration

- [ ] Mock mode pattern follows CLAUDE.md conventions
- [ ] Switch node routing uses expression mode (not rules)
- [ ] Approval flow is tested
- [ ] Error notifications are verified

---

## Commands to Run Tests

### PowerShell (Pester)

```powershell
# From project root
cd "C:\Users\rcox\OneDrive - INSULATIONS, INC\Documents\Cursor Projects\II-n8n\agents\employee-termination"

# Run all Pester tests
Invoke-Pester -Path .\tests -Output Detailed

# Run with coverage
$config = . .\tests\pester.config.ps1
Invoke-Pester -Configuration $config

# Run specific test file
Invoke-Pester -Path .\tests\Terminate-Employee.Tests.ps1
```

### Node.js (Jest)

```bash
cd "C:/Users/rcox/OneDrive - INSULATIONS, INC/Documents/Cursor Projects/II-n8n/agents/employee-termination"

# Install dependencies
npm install

# Run all tests
npm test

# Run with coverage
npm run test:coverage

# Run specific test suite
npm run test:contract
npm run test:unit
npm run test:n8n
```

### Combined

```bash
# Run both PowerShell and Node.js tests
npm run test:all
```

---

## Known Limitations

1. **n8n Tests Require Deployed Workflow**: The `n8n-workflow.test.js` tests require `N8N_WEBHOOK_URL` to be set. They will skip if not configured.

2. **Pester Tests Need Module Stubs**: Until `Terminate-Employee.ps1` is implemented, tests will fail with "Not implemented" errors. This is expected TDD behavior.

3. **E2E Tests Require Test Accounts**: The E2E test plan requires specific test accounts in AD. These need to be created before E2E testing.

4. **Azure Relay Not Tested**: Tests mock the HTTP layer but do not test Azure Relay connectivity. That requires integration testing.

---

## Next Steps for Code-Reviewer

1. **Review Test Quality**: Ensure tests follow best practices
2. **Verify Coverage Goals**: Confirm 80%+ coverage targets are achievable
3. **Check Mock Patterns**: Verify mocks accurately represent dependencies
4. **Validate Security Tests**: Ensure all injection vectors are tested
5. **Approve for Implementation**: Sign off on test specifications

Once approved, the implementation team can proceed with RED-GREEN-REFACTOR:
1. Run tests (should all FAIL - RED)
2. Implement code to make tests pass (GREEN)
3. Refactor while keeping tests green

---

## Files Summary

```
agents/employee-termination/
|-- TDD-PLAN.md                    # Comprehensive TDD plan
|-- HANDOFF-CODE-REVIEWER.md       # This document
|-- package.json                   # Node.js configuration
|-- jest.config.js                 # Jest configuration
|-- jest.setup.js                  # Jest setup/utilities
|-- tests/
    |-- Terminate-Employee.Tests.ps1  # PowerShell Pester tests
    |-- server.test.js                # Node.js HTTP server tests
    |-- n8n-workflow.test.js          # n8n integration tests
    |-- api-contract.test.js          # API contract tests
    |-- pester.config.ps1             # Pester configuration
```

---

**TDD-GUIDE Agent Status:** COMPLETE
**Ready for:** Code Review
**Blocking:** Implementation cannot begin until tests are approved
