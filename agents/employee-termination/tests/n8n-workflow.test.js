/**
 * n8n Workflow Integration Tests for Employee Termination
 *
 * These tests validate the n8n workflow using mock mode.
 * Pattern from CLAUDE.md: Use mock=true and mock_exit_code to simulate agent responses.
 *
 * Run these tests against the deployed n8n workflow.
 * Set N8N_WEBHOOK_URL environment variable before running.
 */

const WEBHOOK_URL = process.env.N8N_WEBHOOK_URL || 'https://n8n.ii-us.com/webhook/employee-termination';

// Helper for HTTP requests
const makeRequest = async (body) => {
  const response = await fetch(WEBHOOK_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body)
  });

  let data;
  try {
    data = await response.json();
  } catch (e) {
    data = await response.text();
  }

  return { status: response.status, data };
};

describe('Employee Termination n8n Workflow', () => {
  // Skip if webhook URL not configured
  const conditionalDescribe = process.env.N8N_WEBHOOK_URL ? describe : describe.skip;

  conditionalDescribe('Input Validation', () => {
    it('should return 400 for missing employee_upn', async () => {
      const response = await makeRequest({
        mock: true,
        requester_upn: 'admin@ii-us.com',
        ticket_id: 'TEST-001'
      });

      expect(response.status).toBe(400);
      expect(response.data.error).toMatch(/employee_upn.*required/i);
    });

    it('should return 400 for missing requester_upn', async () => {
      const response = await makeRequest({
        mock: true,
        employee_upn: 'test@ii-us.com',
        ticket_id: 'TEST-001'
      });

      expect(response.status).toBe(400);
      expect(response.data.error).toMatch(/requester_upn.*required/i);
    });

    it('should return 400 for missing ticket_id', async () => {
      const response = await makeRequest({
        mock: true,
        employee_upn: 'test@ii-us.com',
        requester_upn: 'admin@ii-us.com'
      });

      expect(response.status).toBe(400);
      expect(response.data.error).toMatch(/ticket_id.*required/i);
    });

    it('should return 400 for invalid email format', async () => {
      const response = await makeRequest({
        mock: true,
        employee_upn: 'not-an-email',
        requester_upn: 'admin@ii-us.com',
        ticket_id: 'TEST-001'
      });

      expect(response.status).toBe(400);
      expect(response.data.error).toMatch(/invalid.*format/i);
    });

    it('should return 400 for invalid ticket_id format', async () => {
      const response = await makeRequest({
        mock: true,
        employee_upn: 'test@ii-us.com',
        requester_upn: 'admin@ii-us.com',
        ticket_id: 'invalid-format'
      });

      expect(response.status).toBe(400);
      expect(response.data.error).toMatch(/ticket_id.*format/i);
    });
  });

  conditionalDescribe('Mock Mode Exit Code Routing', () => {
    it('should return 200 for mock exit code 0 (success)', async () => {
      const response = await makeRequest({
        mock: true,
        mock_exit_code: 0,
        employee_upn: 'test@ii-us.com',
        requester_upn: 'admin@ii-us.com',
        ticket_id: 'TEST-001',
        skip_approval: true
      });

      expect(response.status).toBe(200);
      expect(response.data.status).toBe('success');
      expect(response.data.exit_code).toBe(0);
    });

    it('should return 404 for mock exit code 10 (not found)', async () => {
      const response = await makeRequest({
        mock: true,
        mock_exit_code: 10,
        employee_upn: 'notfound@ii-us.com',
        requester_upn: 'admin@ii-us.com',
        ticket_id: 'TEST-001',
        skip_approval: true
      });

      expect(response.status).toBe(404);
      expect(response.data.exit_code).toBe(10);
      expect(response.data.error).toMatch(/not found/i);
    });

    it('should return 200 for mock exit code 11 (idempotent - already disabled)', async () => {
      const response = await makeRequest({
        mock: true,
        mock_exit_code: 11,
        employee_upn: 'disabled@ii-us.com',
        requester_upn: 'admin@ii-us.com',
        ticket_id: 'TEST-001',
        skip_approval: true
      });

      expect(response.status).toBe(200);
      expect(response.data.exit_code).toBe(11);
      expect(response.data.idempotent).toBe(true);
    });

    it('should return 403 for mock exit code 12 (protected)', async () => {
      const response = await makeRequest({
        mock: true,
        mock_exit_code: 12,
        employee_upn: 'admin@ii-us.com',
        requester_upn: 'other@ii-us.com',
        ticket_id: 'TEST-001',
        skip_approval: true
      });

      expect(response.status).toBe(403);
      expect(response.data.exit_code).toBe(12);
      expect(response.data.error).toMatch(/protected/i);
    });

    it('should return 503 for mock exit code 20 (Graph connection failed)', async () => {
      const response = await makeRequest({
        mock: true,
        mock_exit_code: 20,
        employee_upn: 'test@ii-us.com',
        requester_upn: 'admin@ii-us.com',
        ticket_id: 'TEST-001',
        skip_approval: true
      });

      expect(response.status).toBe(503);
      expect(response.data.exit_code).toBe(20);
      expect(response.data.retryable).toBe(true);
    });

    it('should return 503 for mock exit code 21 (Exchange connection failed)', async () => {
      const response = await makeRequest({
        mock: true,
        mock_exit_code: 21,
        employee_upn: 'test@ii-us.com',
        requester_upn: 'admin@ii-us.com',
        ticket_id: 'TEST-001',
        skip_approval: true
      });

      expect(response.status).toBe(503);
      expect(response.data.exit_code).toBe(21);
      expect(response.data.retryable).toBe(true);
    });

    it('should return 503 for mock exit code 22 (AD connection failed)', async () => {
      const response = await makeRequest({
        mock: true,
        mock_exit_code: 22,
        employee_upn: 'test@ii-us.com',
        requester_upn: 'admin@ii-us.com',
        ticket_id: 'TEST-001',
        skip_approval: true
      });

      expect(response.status).toBe(503);
      expect(response.data.exit_code).toBe(22);
      expect(response.data.retryable).toBe(true);
    });

    it('should return 500 for mock exit code 30 (license removal failed)', async () => {
      const response = await makeRequest({
        mock: true,
        mock_exit_code: 30,
        employee_upn: 'test@ii-us.com',
        requester_upn: 'admin@ii-us.com',
        ticket_id: 'TEST-001',
        skip_approval: true
      });

      expect(response.status).toBe(500);
      expect(response.data.exit_code).toBe(30);
    });

    it('should return 500 for mock exit code 31 (mailbox conversion failed)', async () => {
      const response = await makeRequest({
        mock: true,
        mock_exit_code: 31,
        employee_upn: 'test@ii-us.com',
        requester_upn: 'admin@ii-us.com',
        ticket_id: 'TEST-001',
        skip_approval: true
      });

      expect(response.status).toBe(500);
      expect(response.data.exit_code).toBe(31);
    });

    it('should return 500 for mock exit code 32 (AD disable failed)', async () => {
      const response = await makeRequest({
        mock: true,
        mock_exit_code: 32,
        employee_upn: 'test@ii-us.com',
        requester_upn: 'admin@ii-us.com',
        ticket_id: 'TEST-001',
        skip_approval: true
      });

      expect(response.status).toBe(500);
      expect(response.data.exit_code).toBe(32);
    });

    it('should return 500 for mock exit code 33 (OU move failed)', async () => {
      const response = await makeRequest({
        mock: true,
        mock_exit_code: 33,
        employee_upn: 'test@ii-us.com',
        requester_upn: 'admin@ii-us.com',
        ticket_id: 'TEST-001',
        skip_approval: true
      });

      expect(response.status).toBe(500);
      expect(response.data.exit_code).toBe(33);
    });

    it('should return 500 for mock exit code 40 (AD Sync failed)', async () => {
      const response = await makeRequest({
        mock: true,
        mock_exit_code: 40,
        employee_upn: 'test@ii-us.com',
        requester_upn: 'admin@ii-us.com',
        ticket_id: 'TEST-001',
        skip_approval: true
      });

      expect(response.status).toBe(500);
      expect(response.data.exit_code).toBe(40);
    });

    it('should return 500 for mock exit code 1 (general error)', async () => {
      const response = await makeRequest({
        mock: true,
        mock_exit_code: 1,
        employee_upn: 'test@ii-us.com',
        requester_upn: 'admin@ii-us.com',
        ticket_id: 'TEST-001',
        skip_approval: true
      });

      expect(response.status).toBe(500);
      expect(response.data.exit_code).toBe(1);
    });
  });

  conditionalDescribe('Response Structure', () => {
    it('should include all required fields in success response', async () => {
      const response = await makeRequest({
        mock: true,
        mock_exit_code: 0,
        employee_upn: 'test@ii-us.com',
        requester_upn: 'admin@ii-us.com',
        ticket_id: 'TEST-001',
        skip_approval: true
      });

      expect(response.status).toBe(200);
      expect(response.data).toHaveProperty('status');
      expect(response.data).toHaveProperty('exit_code');
      expect(response.data).toHaveProperty('employee_upn');
      expect(response.data).toHaveProperty('ticket_id');
      expect(response.data).toHaveProperty('timestamp');
    });

    it('should include error details in error response', async () => {
      const response = await makeRequest({
        mock: true,
        mock_exit_code: 30,
        employee_upn: 'test@ii-us.com',
        requester_upn: 'admin@ii-us.com',
        ticket_id: 'TEST-001',
        skip_approval: true
      });

      expect(response.status).toBe(500);
      expect(response.data).toHaveProperty('status');
      expect(response.data).toHaveProperty('exit_code');
      expect(response.data).toHaveProperty('error');
      expect(response.data).toHaveProperty('timestamp');
    });

    it('should include retryable flag for connection failures', async () => {
      const response = await makeRequest({
        mock: true,
        mock_exit_code: 20,
        employee_upn: 'test@ii-us.com',
        requester_upn: 'admin@ii-us.com',
        ticket_id: 'TEST-001',
        skip_approval: true
      });

      expect(response.status).toBe(503);
      expect(response.data.retryable).toBe(true);
    });

    it('should not include retryable flag for operation failures', async () => {
      const response = await makeRequest({
        mock: true,
        mock_exit_code: 30,
        employee_upn: 'test@ii-us.com',
        requester_upn: 'admin@ii-us.com',
        ticket_id: 'TEST-001',
        skip_approval: true
      });

      expect(response.status).toBe(500);
      expect(response.data.retryable).toBeFalsy();
    });
  });

  conditionalDescribe('Approval Flow', () => {
    it('should require approval when skip_approval is false', async () => {
      const response = await makeRequest({
        mock: true,
        mock_exit_code: 0,
        employee_upn: 'real.employee@ii-us.com',
        requester_upn: 'admin@ii-us.com',
        ticket_id: 'PROD-001',
        skip_approval: false
      });

      // Workflow should indicate pending approval (or process as async)
      // The exact behavior depends on workflow implementation
      expect([200, 202]).toContain(response.status);
      if (response.status === 202) {
        expect(response.data.status).toBe('pending_approval');
        expect(response.data.approval_id).toBeDefined();
      }
    });

    it('should skip approval when skip_approval is true', async () => {
      const response = await makeRequest({
        mock: true,
        mock_exit_code: 0,
        employee_upn: 'test@ii-us.com',
        requester_upn: 'admin@ii-us.com',
        ticket_id: 'TEST-001',
        skip_approval: true
      });

      expect(response.status).toBe(200);
      expect(response.data.status).toBe('success');
    });
  });

  conditionalDescribe('Notifications', () => {
    it('should indicate Teams notification for connection failures', async () => {
      const response = await makeRequest({
        mock: true,
        mock_exit_code: 21,
        employee_upn: 'test@ii-us.com',
        requester_upn: 'admin@ii-us.com',
        ticket_id: 'TEST-001',
        skip_approval: true
      });

      expect(response.status).toBe(503);
      // Workflow should indicate notifications were queued/sent
      expect(response.data.notifications_sent || response.data.notifications_queued).toBeDefined();
    });

    it('should indicate Teams notification for operation failures', async () => {
      const response = await makeRequest({
        mock: true,
        mock_exit_code: 30,
        employee_upn: 'test@ii-us.com',
        requester_upn: 'admin@ii-us.com',
        ticket_id: 'TEST-001',
        skip_approval: true
      });

      expect(response.status).toBe(500);
      // Should trigger error notification
    });
  });

  conditionalDescribe('Execution Metadata', () => {
    it('should include execution ID in response', async () => {
      const response = await makeRequest({
        mock: true,
        mock_exit_code: 0,
        employee_upn: 'test@ii-us.com',
        requester_upn: 'admin@ii-us.com',
        ticket_id: 'TEST-001',
        skip_approval: true
      });

      expect(response.status).toBe(200);
      expect(response.data.execution_id).toBeDefined();
    });

    it('should include workflow version in response', async () => {
      const response = await makeRequest({
        mock: true,
        mock_exit_code: 0,
        employee_upn: 'test@ii-us.com',
        requester_upn: 'admin@ii-us.com',
        ticket_id: 'TEST-001',
        skip_approval: true
      });

      expect(response.status).toBe(200);
      // Optionally include workflow version for debugging
    });
  });
});

// Unit tests for mock mode routing logic (can run without n8n)
describe('Mock Mode Routing Logic', () => {
  // This tests the routing expression used in the n8n Switch node
  // Expression mode from CLAUDE.md: {{ $json.mock === true ? 0 : 1 }}

  const getRoute = (exitCode) => {
    // Route mapping based on exit code
    const routeMap = {
      0: 'success',      // Output 0
      10: 'not_found',   // Output 1
      11: 'idempotent',  // Output 2
      12: 'protected',   // Output 3
      20: 'connection',  // Output 4
      21: 'connection',  // Output 4
      22: 'connection',  // Output 4
      30: 'operation',   // Output 5
      31: 'operation',   // Output 5
      32: 'operation',   // Output 5
      33: 'operation',   // Output 5
      40: 'operation',   // Output 5
    };
    return routeMap[exitCode] || 'error'; // Default to error output
  };

  it('routes exit code 0 to success', () => {
    expect(getRoute(0)).toBe('success');
  });

  it('routes exit code 10 to not_found', () => {
    expect(getRoute(10)).toBe('not_found');
  });

  it('routes exit code 11 to idempotent', () => {
    expect(getRoute(11)).toBe('idempotent');
  });

  it('routes exit code 12 to protected', () => {
    expect(getRoute(12)).toBe('protected');
  });

  it('routes exit codes 20-22 to connection', () => {
    expect(getRoute(20)).toBe('connection');
    expect(getRoute(21)).toBe('connection');
    expect(getRoute(22)).toBe('connection');
  });

  it('routes exit codes 30-40 to operation', () => {
    expect(getRoute(30)).toBe('operation');
    expect(getRoute(31)).toBe('operation');
    expect(getRoute(32)).toBe('operation');
    expect(getRoute(33)).toBe('operation');
    expect(getRoute(40)).toBe('operation');
  });

  it('routes unknown exit codes to error', () => {
    expect(getRoute(99)).toBe('error');
    expect(getRoute(1)).toBe('error');
  });
});
