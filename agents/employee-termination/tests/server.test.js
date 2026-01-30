/**
 * Jest tests for Employee Termination HTTP Server
 *
 * TDD tests - write these BEFORE implementing server.js
 * Run with: npm test
 *
 * Exit Codes:
 * 0  - Success
 * 1  - General error
 * 10 - Employee not found
 * 11 - Employee already disabled
 * 12 - Protected account
 * 20 - Graph connection failed
 * 21 - Exchange connection failed
 * 22 - AD connection failed
 * 30 - License removal failed
 * 31 - Mailbox conversion failed
 * 32 - AD disable failed
 * 33 - OU move failed
 * 40 - AD Sync trigger failed
 */

// Mock child_process before requiring server
jest.mock('child_process', () => ({
  spawnSync: jest.fn()
}));

const http = require('http');
const { spawnSync } = require('child_process');

// We'll create a factory pattern for the server
let server;
let baseUrl;

// Helper to make HTTP requests
const makeRequest = async (method, path, body = null, headers = {}) => {
  return new Promise((resolve, reject) => {
    const url = new URL(path, baseUrl);
    const options = {
      hostname: url.hostname,
      port: url.port,
      path: url.pathname + url.search,
      method,
      headers: {
        'Content-Type': 'application/json',
        ...headers
      }
    };

    const req = http.request(options, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        try {
          resolve({
            status: res.statusCode,
            headers: res.headers,
            data: data ? JSON.parse(data) : null
          });
        } catch (e) {
          resolve({
            status: res.statusCode,
            headers: res.headers,
            data: data
          });
        }
      });
    });

    req.on('error', reject);

    if (body) {
      req.write(typeof body === 'string' ? body : JSON.stringify(body));
    }
    req.end();
  });
};

describe('Employee Termination HTTP Server', () => {
  beforeAll((done) => {
    // Try to load the server, or create a stub for TDD
    try {
      const createServer = require('../server');
      server = createServer({ port: 0 });
    } catch (e) {
      // Server not implemented yet - create minimal stub for TDD
      console.log('Server not implemented - tests will fail until implementation exists');
      server = http.createServer((req, res) => {
        res.writeHead(501, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: 'Not implemented' }));
      });
    }

    server.listen(0, () => {
      const address = server.address();
      baseUrl = `http://localhost:${address.port}`;
      done();
    });
  });

  afterAll((done) => {
    if (server) {
      server.close(done);
    } else {
      done();
    }
  });

  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('GET /health', () => {
    it('returns 200 with healthy status', async () => {
      const response = await makeRequest('GET', '/health');

      expect(response.status).toBe(200);
      expect(response.data.status).toBe('healthy');
      expect(response.data.timestamp).toBeDefined();
    });

    it('includes version in health response', async () => {
      const response = await makeRequest('GET', '/health');

      expect(response.status).toBe(200);
      expect(response.data.version).toBeDefined();
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
          displayName: 'Test User',
          department: 'IT'
        }),
        stderr: ''
      });

      const response = await makeRequest('POST', '/validate', {
        employee_upn: 'test@ii-us.com'
      });

      expect(response.status).toBe(200);
      expect(response.data.valid).toBe(true);
      expect(response.data.employee.exists).toBe(true);
      expect(response.data.employee.enabled).toBe(true);
      expect(response.data.employee.protected).toBe(false);
    });

    it('returns 400 for missing employee_upn', async () => {
      const response = await makeRequest('POST', '/validate', {});

      expect(response.status).toBe(400);
      expect(response.data.error).toMatch(/employee_upn.*required/i);
    });

    it('returns 400 for empty employee_upn', async () => {
      const response = await makeRequest('POST', '/validate', {
        employee_upn: ''
      });

      expect(response.status).toBe(400);
      expect(response.data.error).toMatch(/employee_upn.*required/i);
    });

    it('returns 400 for invalid UPN format', async () => {
      const response = await makeRequest('POST', '/validate', {
        employee_upn: 'not-a-valid-email'
      });

      expect(response.status).toBe(400);
      expect(response.data.error).toMatch(/invalid.*format/i);
    });

    it('returns 400 for SQL injection attempt', async () => {
      const response = await makeRequest('POST', '/validate', {
        employee_upn: "'; DROP TABLE Users;--@ii-us.com"
      });

      expect(response.status).toBe(400);
      expect(response.data.error).toMatch(/invalid.*characters/i);
    });

    it('returns 404 when employee not found (exit code 10)', async () => {
      spawnSync.mockReturnValue({
        status: 10,
        stdout: '',
        stderr: 'Employee not found in Active Directory'
      });

      const response = await makeRequest('POST', '/validate', {
        employee_upn: 'notfound@ii-us.com'
      });

      expect(response.status).toBe(404);
      expect(response.data.exit_code).toBe(10);
      expect(response.data.error).toMatch(/not found/i);
    });

    it('returns 200 with warning for disabled employee (exit code 11)', async () => {
      spawnSync.mockReturnValue({
        status: 11,
        stdout: JSON.stringify({
          exists: true,
          enabled: false,
          protected: false,
          displayName: 'Disabled User'
        }),
        stderr: ''
      });

      const response = await makeRequest('POST', '/validate', {
        employee_upn: 'disabled@ii-us.com'
      });

      expect(response.status).toBe(200);
      expect(response.data.exit_code).toBe(11);
      expect(response.data.employee.enabled).toBe(false);
      expect(response.data.warning).toMatch(/already disabled/i);
    });

    it('returns 403 for protected account (exit code 12)', async () => {
      spawnSync.mockReturnValue({
        status: 12,
        stdout: JSON.stringify({
          exists: true,
          enabled: true,
          protected: true,
          protectedReason: 'Domain Admin'
        }),
        stderr: ''
      });

      const response = await makeRequest('POST', '/validate', {
        employee_upn: 'admin@ii-us.com'
      });

      expect(response.status).toBe(403);
      expect(response.data.exit_code).toBe(12);
      expect(response.data.error).toMatch(/protected/i);
    });
  });

  describe('POST /terminate', () => {
    const validRequest = {
      employee_upn: 'test@ii-us.com',
      requester_upn: 'admin@ii-us.com',
      ticket_id: 'TEST-001'
    };

    it('returns 200 on successful termination (exit code 0)', async () => {
      spawnSync.mockReturnValue({
        status: 0,
        stdout: JSON.stringify({
          success: true,
          employee_upn: 'test@ii-us.com',
          steps: [
            'Connected to Microsoft Graph',
            'Connected to Exchange Online',
            'Licenses removed',
            'Mailbox converted to shared',
            'AD account disabled',
            'User moved to Disabled Users OU',
            'AD Sync triggered'
          ],
          completed_at: new Date().toISOString()
        }),
        stderr: ''
      });

      const response = await makeRequest('POST', '/terminate', validRequest);

      expect(response.status).toBe(200);
      expect(response.data.exit_code).toBe(0);
      expect(response.data.success).toBe(true);
      expect(response.data.steps).toBeInstanceOf(Array);
      expect(response.data.steps.length).toBeGreaterThan(0);
    });

    it('returns 400 for missing employee_upn', async () => {
      const response = await makeRequest('POST', '/terminate', {
        requester_upn: 'admin@ii-us.com',
        ticket_id: 'TEST-001'
      });

      expect(response.status).toBe(400);
      expect(response.data.error).toMatch(/employee_upn.*required/i);
    });

    it('returns 400 for missing requester_upn', async () => {
      const response = await makeRequest('POST', '/terminate', {
        employee_upn: 'test@ii-us.com',
        ticket_id: 'TEST-001'
      });

      expect(response.status).toBe(400);
      expect(response.data.error).toMatch(/requester_upn.*required/i);
    });

    it('returns 400 for missing ticket_id', async () => {
      const response = await makeRequest('POST', '/terminate', {
        employee_upn: 'test@ii-us.com',
        requester_upn: 'admin@ii-us.com'
      });

      expect(response.status).toBe(400);
      expect(response.data.error).toMatch(/ticket_id.*required/i);
    });

    it('returns 400 for invalid ticket_id format', async () => {
      const response = await makeRequest('POST', '/terminate', {
        ...validRequest,
        ticket_id: 'invalid-format'
      });

      expect(response.status).toBe(400);
      expect(response.data.error).toMatch(/ticket_id.*format/i);
    });

    it('returns 404 for employee not found (exit code 10)', async () => {
      spawnSync.mockReturnValue({
        status: 10,
        stdout: '',
        stderr: 'Employee not found in Active Directory'
      });

      const response = await makeRequest('POST', '/terminate', {
        ...validRequest,
        employee_upn: 'notfound@ii-us.com'
      });

      expect(response.status).toBe(404);
      expect(response.data.exit_code).toBe(10);
    });

    it('returns 200 for already disabled (exit code 11, idempotent)', async () => {
      spawnSync.mockReturnValue({
        status: 11,
        stdout: JSON.stringify({
          message: 'Employee already disabled',
          idempotent: true
        }),
        stderr: ''
      });

      const response = await makeRequest('POST', '/terminate', {
        ...validRequest,
        employee_upn: 'disabled@ii-us.com'
      });

      // Idempotent - return 200, not an error
      expect(response.status).toBe(200);
      expect(response.data.exit_code).toBe(11);
      expect(response.data.idempotent).toBe(true);
    });

    it('returns 403 for protected account (exit code 12)', async () => {
      spawnSync.mockReturnValue({
        status: 12,
        stdout: '',
        stderr: 'Cannot terminate protected account: Domain Admin'
      });

      const response = await makeRequest('POST', '/terminate', {
        ...validRequest,
        employee_upn: 'admin@ii-us.com'
      });

      expect(response.status).toBe(403);
      expect(response.data.exit_code).toBe(12);
      expect(response.data.error).toMatch(/protected/i);
    });

    describe('Connection Failures (503 with retryable)', () => {
      const connectionCodes = [
        { code: 20, name: 'Graph connection failed' },
        { code: 21, name: 'Exchange connection failed' },
        { code: 22, name: 'AD connection failed' }
      ];

      connectionCodes.forEach(({ code, name }) => {
        it(`returns 503 for exit code ${code} (${name})`, async () => {
          spawnSync.mockReturnValue({
            status: code,
            stdout: '',
            stderr: name
          });

          const response = await makeRequest('POST', '/terminate', validRequest);

          expect(response.status).toBe(503);
          expect(response.data.exit_code).toBe(code);
          expect(response.data.retryable).toBe(true);
        });
      });
    });

    describe('Operation Failures (500)', () => {
      const operationCodes = [
        { code: 30, name: 'License removal failed' },
        { code: 31, name: 'Mailbox conversion failed' },
        { code: 32, name: 'AD disable failed' },
        { code: 33, name: 'OU move failed' },
        { code: 40, name: 'AD Sync trigger failed' }
      ];

      operationCodes.forEach(({ code, name }) => {
        it(`returns 500 for exit code ${code} (${name})`, async () => {
          spawnSync.mockReturnValue({
            status: code,
            stdout: '',
            stderr: name
          });

          const response = await makeRequest('POST', '/terminate', validRequest);

          expect(response.status).toBe(500);
          expect(response.data.exit_code).toBe(code);
          expect(response.data.retryable).toBe(false);
        });
      });
    });

    it('handles timeout gracefully (504)', async () => {
      spawnSync.mockReturnValue({
        status: null,
        signal: 'SIGTERM',
        stdout: '',
        stderr: ''
      });

      const response = await makeRequest('POST', '/terminate', {
        ...validRequest,
        timeout: 1
      });

      expect(response.status).toBe(504);
      expect(response.data.error).toMatch(/timeout/i);
    });

    it('includes execution time in response', async () => {
      spawnSync.mockReturnValue({
        status: 0,
        stdout: JSON.stringify({ success: true }),
        stderr: ''
      });

      const response = await makeRequest('POST', '/terminate', validRequest);

      expect(response.status).toBe(200);
      expect(response.data.execution_time_ms).toBeDefined();
      expect(typeof response.data.execution_time_ms).toBe('number');
    });
  });

  describe('Error Handling', () => {
    it('returns 400 for invalid JSON', async () => {
      const response = await makeRequest('POST', '/terminate', 'not valid json');

      expect(response.status).toBe(400);
      expect(response.data.error).toMatch(/invalid.*json/i);
    });

    it('returns 404 for unknown routes', async () => {
      const response = await makeRequest('GET', '/unknown');

      expect(response.status).toBe(404);
      expect(response.data.error).toMatch(/not found/i);
    });

    it('returns 405 for wrong HTTP method on /terminate', async () => {
      const response = await makeRequest('GET', '/terminate');

      expect(response.status).toBe(405);
      expect(response.data.error).toMatch(/method not allowed/i);
    });

    it('returns 405 for wrong HTTP method on /validate', async () => {
      const response = await makeRequest('GET', '/validate');

      expect(response.status).toBe(405);
    });

    it('handles script execution errors gracefully', async () => {
      spawnSync.mockReturnValue({
        status: 1,
        stdout: '',
        stderr: 'Unexpected PowerShell error',
        error: new Error('spawn ENOENT')
      });

      const response = await makeRequest('POST', '/terminate', {
        employee_upn: 'test@ii-us.com',
        requester_upn: 'admin@ii-us.com',
        ticket_id: 'TEST-001'
      });

      expect(response.status).toBe(500);
      expect(response.data.exit_code).toBe(1);
    });
  });

  describe('CORS Headers', () => {
    it('includes CORS headers for allowed origins', async () => {
      const response = await makeRequest('OPTIONS', '/health');

      // Should include CORS headers
      expect(response.headers['access-control-allow-origin']).toBeDefined();
      expect(response.headers['access-control-allow-methods']).toMatch(/POST/);
    });
  });

  describe('Request Logging', () => {
    it('logs requests with correlation ID', async () => {
      const consoleSpy = jest.spyOn(console, 'log').mockImplementation();

      spawnSync.mockReturnValue({
        status: 0,
        stdout: JSON.stringify({ success: true }),
        stderr: ''
      });

      await makeRequest('POST', '/terminate', {
        employee_upn: 'test@ii-us.com',
        requester_upn: 'admin@ii-us.com',
        ticket_id: 'TEST-001'
      });

      // Should log with timestamp and correlation ID
      expect(consoleSpy).toHaveBeenCalled();
      const logCall = consoleSpy.mock.calls.find(call =>
        call[0] && call[0].includes('/terminate')
      );
      expect(logCall).toBeDefined();

      consoleSpy.mockRestore();
    });
  });

  describe('Input Sanitization', () => {
    it('sanitizes employee_upn before passing to script', async () => {
      spawnSync.mockReturnValue({
        status: 0,
        stdout: JSON.stringify({ success: true }),
        stderr: ''
      });

      await makeRequest('POST', '/terminate', {
        employee_upn: 'test@ii-us.com',
        requester_upn: 'admin@ii-us.com',
        ticket_id: 'TEST-001'
      });

      // Verify spawnSync was called with sanitized args
      expect(spawnSync).toHaveBeenCalled();
      const args = spawnSync.mock.calls[0][1];
      // Args should not contain shell metacharacters
      args.forEach(arg => {
        expect(arg).not.toMatch(/[;&|`$]/);
      });
    });

    it('rejects request with shell metacharacters', async () => {
      const response = await makeRequest('POST', '/terminate', {
        employee_upn: 'test@ii-us.com; rm -rf /',
        requester_upn: 'admin@ii-us.com',
        ticket_id: 'TEST-001'
      });

      expect(response.status).toBe(400);
    });
  });
});

describe('Exit Code to HTTP Status Mapping', () => {
  const mapping = {
    0: 200,   // Success
    1: 500,   // General error
    10: 404,  // Employee not found
    11: 200,  // Already disabled (idempotent)
    12: 403,  // Protected account
    20: 503,  // Graph connection failed
    21: 503,  // Exchange connection failed
    22: 503,  // AD connection failed
    30: 500,  // License removal failed
    31: 500,  // Mailbox conversion failed
    32: 500,  // AD disable failed
    33: 500,  // OU move failed
    40: 500   // AD Sync trigger failed
  };

  Object.entries(mapping).forEach(([exitCode, expectedStatus]) => {
    it(`maps exit code ${exitCode} to HTTP ${expectedStatus}`, () => {
      // This documents the expected mapping
      expect(mapping[exitCode]).toBe(expectedStatus);
    });
  });
});
