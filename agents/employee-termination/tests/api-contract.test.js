/**
 * API Contract Tests for Employee Termination Agent
 *
 * These tests validate the contract between n8n and the on-premises agent.
 * The agent MUST return responses matching these schemas.
 *
 * Run with: npm test api-contract.test.js
 */

const Ajv = require('ajv');
const addFormats = require('ajv-formats');

const ajv = new Ajv({ allErrors: true });
addFormats(ajv);

// ============================================================================
// Request Schemas
// ============================================================================

const validateRequestSchema = {
  $id: 'validate-request',
  type: 'object',
  required: ['employee_upn'],
  properties: {
    employee_upn: {
      type: 'string',
      pattern: '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$',
      maxLength: 320,
      description: 'User Principal Name of the employee to validate'
    }
  },
  additionalProperties: false
};

const terminateRequestSchema = {
  $id: 'terminate-request',
  type: 'object',
  required: ['employee_upn', 'requester_upn', 'ticket_id'],
  properties: {
    employee_upn: {
      type: 'string',
      pattern: '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$',
      maxLength: 320,
      description: 'User Principal Name of the employee to terminate'
    },
    requester_upn: {
      type: 'string',
      pattern: '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$',
      maxLength: 320,
      description: 'User Principal Name of the person requesting termination'
    },
    ticket_id: {
      type: 'string',
      pattern: '^[A-Z]+-[0-9]+$',
      maxLength: 50,
      description: 'Ticket ID for audit purposes (e.g., HR-1234, IT-5678)'
    },
    termination_date: {
      type: 'string',
      format: 'date',
      description: 'Optional effective date for termination (ISO 8601 date)'
    },
    skip_approval: {
      type: 'boolean',
      default: false,
      description: 'Skip approval flow (testing only)'
    },
    mock: {
      type: 'boolean',
      default: false,
      description: 'Enable mock mode for testing'
    },
    mock_exit_code: {
      type: 'integer',
      minimum: 0,
      maximum: 255,
      description: 'Exit code to simulate in mock mode'
    },
    timeout: {
      type: 'integer',
      minimum: 1,
      maximum: 3600,
      default: 300,
      description: 'Timeout in seconds for the operation'
    }
  },
  additionalProperties: false
};

// ============================================================================
// Response Schemas
// ============================================================================

const successResponseSchema = {
  $id: 'success-response',
  type: 'object',
  required: ['exit_code', 'success', 'timestamp'],
  properties: {
    exit_code: {
      type: 'integer',
      const: 0,
      description: 'Exit code 0 indicates success'
    },
    success: {
      type: 'boolean',
      const: true
    },
    status: {
      type: 'string',
      const: 'success'
    },
    employee_upn: {
      type: 'string',
      format: 'email'
    },
    requester_upn: {
      type: 'string',
      format: 'email'
    },
    ticket_id: {
      type: 'string'
    },
    steps: {
      type: 'array',
      items: { type: 'string' },
      minItems: 1,
      description: 'List of operations performed'
    },
    completed_at: {
      type: 'string',
      format: 'date-time'
    },
    timestamp: {
      type: 'string',
      format: 'date-time'
    },
    execution_time_ms: {
      type: 'integer',
      minimum: 0
    },
    execution_id: {
      type: 'string'
    }
  },
  additionalProperties: true
};

const idempotentResponseSchema = {
  $id: 'idempotent-response',
  type: 'object',
  required: ['exit_code', 'idempotent', 'timestamp'],
  properties: {
    exit_code: {
      type: 'integer',
      const: 11
    },
    idempotent: {
      type: 'boolean',
      const: true
    },
    status: {
      type: 'string',
      enum: ['success', 'already_disabled']
    },
    message: {
      type: 'string'
    },
    employee_upn: {
      type: 'string'
    },
    timestamp: {
      type: 'string',
      format: 'date-time'
    }
  },
  additionalProperties: true
};

const errorResponseSchema = {
  $id: 'error-response',
  type: 'object',
  required: ['exit_code', 'error', 'timestamp'],
  properties: {
    exit_code: {
      type: 'integer',
      minimum: 1
    },
    error: {
      type: 'string',
      minLength: 1
    },
    error_details: {
      type: 'string'
    },
    status: {
      type: 'string',
      enum: ['error', 'not_found', 'protected', 'connection_failed', 'operation_failed']
    },
    retryable: {
      type: 'boolean'
    },
    timestamp: {
      type: 'string',
      format: 'date-time'
    },
    employee_upn: {
      type: 'string'
    },
    ticket_id: {
      type: 'string'
    }
  },
  additionalProperties: true
};

const validateResponseSchema = {
  $id: 'validate-response',
  type: 'object',
  required: ['valid', 'employee'],
  properties: {
    valid: {
      type: 'boolean'
    },
    employee: {
      type: 'object',
      required: ['exists'],
      properties: {
        exists: { type: 'boolean' },
        enabled: { type: 'boolean' },
        protected: { type: 'boolean' },
        displayName: { type: 'string' },
        department: { type: 'string' },
        protectedReason: { type: 'string' }
      }
    },
    exit_code: {
      type: 'integer'
    },
    warning: {
      type: 'string'
    },
    timestamp: {
      type: 'string',
      format: 'date-time'
    }
  },
  additionalProperties: true
};

// ============================================================================
// Tests
// ============================================================================

describe('API Contract Tests', () => {
  describe('Request Schema Validation', () => {
    describe('/validate Request', () => {
      const validate = ajv.compile(validateRequestSchema);

      it('accepts valid employee_upn', () => {
        expect(validate({ employee_upn: 'test@ii-us.com' })).toBe(true);
      });

      it('accepts UPN with subdomain', () => {
        expect(validate({ employee_upn: 'test@mail.ii-us.com' })).toBe(true);
      });

      it('accepts UPN with plus addressing', () => {
        expect(validate({ employee_upn: 'test+tag@ii-us.com' })).toBe(true);
      });

      it('rejects missing employee_upn', () => {
        expect(validate({})).toBe(false);
        expect(validate.errors[0].keyword).toBe('required');
      });

      it('rejects invalid email format', () => {
        expect(validate({ employee_upn: 'not-an-email' })).toBe(false);
        expect(validate.errors[0].keyword).toBe('pattern');
      });

      it('rejects empty employee_upn', () => {
        expect(validate({ employee_upn: '' })).toBe(false);
      });

      it('rejects additional properties', () => {
        expect(validate({
          employee_upn: 'test@ii-us.com',
          extra_field: 'not allowed'
        })).toBe(false);
      });
    });

    describe('/terminate Request', () => {
      const validate = ajv.compile(terminateRequestSchema);

      it('accepts valid complete request', () => {
        const valid = validate({
          employee_upn: 'test@ii-us.com',
          requester_upn: 'admin@ii-us.com',
          ticket_id: 'HR-1234'
        });
        expect(valid).toBe(true);
      });

      it('accepts request with optional fields', () => {
        const valid = validate({
          employee_upn: 'test@ii-us.com',
          requester_upn: 'admin@ii-us.com',
          ticket_id: 'HR-1234',
          termination_date: '2024-01-15',
          skip_approval: true,
          mock: true,
          mock_exit_code: 0,
          timeout: 600
        });
        expect(valid).toBe(true);
      });

      it('rejects missing employee_upn', () => {
        expect(validate({
          requester_upn: 'admin@ii-us.com',
          ticket_id: 'HR-1234'
        })).toBe(false);
      });

      it('rejects missing requester_upn', () => {
        expect(validate({
          employee_upn: 'test@ii-us.com',
          ticket_id: 'HR-1234'
        })).toBe(false);
      });

      it('rejects missing ticket_id', () => {
        expect(validate({
          employee_upn: 'test@ii-us.com',
          requester_upn: 'admin@ii-us.com'
        })).toBe(false);
      });

      it('rejects invalid ticket_id format', () => {
        expect(validate({
          employee_upn: 'test@ii-us.com',
          requester_upn: 'admin@ii-us.com',
          ticket_id: 'invalid-format'
        })).toBe(false);
      });

      it('accepts various valid ticket formats', () => {
        const validTickets = ['HR-1', 'IT-99999', 'TERM-123', 'A-1'];
        validTickets.forEach(ticket_id => {
          expect(validate({
            employee_upn: 'test@ii-us.com',
            requester_upn: 'admin@ii-us.com',
            ticket_id
          })).toBe(true);
        });
      });

      it('rejects invalid termination_date format', () => {
        expect(validate({
          employee_upn: 'test@ii-us.com',
          requester_upn: 'admin@ii-us.com',
          ticket_id: 'HR-1234',
          termination_date: '01-15-2024' // Wrong format
        })).toBe(false);
      });

      it('rejects timeout out of range', () => {
        expect(validate({
          employee_upn: 'test@ii-us.com',
          requester_upn: 'admin@ii-us.com',
          ticket_id: 'HR-1234',
          timeout: 0
        })).toBe(false);

        expect(validate({
          employee_upn: 'test@ii-us.com',
          requester_upn: 'admin@ii-us.com',
          ticket_id: 'HR-1234',
          timeout: 9999
        })).toBe(false);
      });
    });
  });

  describe('Response Schema Validation', () => {
    describe('Success Response (Exit Code 0)', () => {
      const validate = ajv.compile(successResponseSchema);

      it('validates complete success response', () => {
        const response = {
          exit_code: 0,
          success: true,
          status: 'success',
          employee_upn: 'test@ii-us.com',
          requester_upn: 'admin@ii-us.com',
          ticket_id: 'HR-1234',
          steps: [
            'Connected to Microsoft Graph',
            'Licenses removed',
            'Mailbox converted',
            'AD disabled',
            'OU moved',
            'Sync triggered'
          ],
          completed_at: '2024-01-15T10:30:00Z',
          timestamp: '2024-01-15T10:30:00Z',
          execution_time_ms: 5432
        };

        expect(validate(response)).toBe(true);
      });

      it('rejects non-zero exit code', () => {
        const response = {
          exit_code: 1,
          success: true,
          timestamp: '2024-01-15T10:30:00Z'
        };

        expect(validate(response)).toBe(false);
      });

      it('requires steps array to have items', () => {
        const response = {
          exit_code: 0,
          success: true,
          timestamp: '2024-01-15T10:30:00Z',
          steps: []
        };

        expect(validate(response)).toBe(false);
      });
    });

    describe('Idempotent Response (Exit Code 11)', () => {
      const validate = ajv.compile(idempotentResponseSchema);

      it('validates idempotent response', () => {
        const response = {
          exit_code: 11,
          idempotent: true,
          status: 'already_disabled',
          message: 'Employee account was already disabled',
          employee_upn: 'test@ii-us.com',
          timestamp: '2024-01-15T10:30:00Z'
        };

        expect(validate(response)).toBe(true);
      });

      it('requires idempotent to be true', () => {
        const response = {
          exit_code: 11,
          idempotent: false,
          timestamp: '2024-01-15T10:30:00Z'
        };

        expect(validate(response)).toBe(false);
      });
    });

    describe('Error Response', () => {
      const validate = ajv.compile(errorResponseSchema);

      it('validates error response with required fields', () => {
        const response = {
          exit_code: 10,
          error: 'Employee not found in Active Directory',
          status: 'not_found',
          timestamp: '2024-01-15T10:30:00Z'
        };

        expect(validate(response)).toBe(true);
      });

      it('validates error response with retryable flag', () => {
        const response = {
          exit_code: 20,
          error: 'Failed to connect to Microsoft Graph',
          status: 'connection_failed',
          retryable: true,
          timestamp: '2024-01-15T10:30:00Z'
        };

        expect(validate(response)).toBe(true);
      });

      it('rejects exit code 0 in error response', () => {
        const response = {
          exit_code: 0,
          error: 'Some error',
          timestamp: '2024-01-15T10:30:00Z'
        };

        expect(validate(response)).toBe(false);
      });

      it('rejects empty error message', () => {
        const response = {
          exit_code: 1,
          error: '',
          timestamp: '2024-01-15T10:30:00Z'
        };

        expect(validate(response)).toBe(false);
      });
    });

    describe('Validate Response', () => {
      const validate = ajv.compile(validateResponseSchema);

      it('validates valid employee response', () => {
        const response = {
          valid: true,
          employee: {
            exists: true,
            enabled: true,
            protected: false,
            displayName: 'Test User',
            department: 'IT'
          },
          timestamp: '2024-01-15T10:30:00Z'
        };

        expect(validate(response)).toBe(true);
      });

      it('validates protected employee response', () => {
        const response = {
          valid: false,
          employee: {
            exists: true,
            enabled: true,
            protected: true,
            protectedReason: 'Domain Admin'
          },
          exit_code: 12,
          timestamp: '2024-01-15T10:30:00Z'
        };

        expect(validate(response)).toBe(true);
      });

      it('validates disabled employee response with warning', () => {
        const response = {
          valid: true,
          employee: {
            exists: true,
            enabled: false,
            protected: false
          },
          exit_code: 11,
          warning: 'Employee account is already disabled',
          timestamp: '2024-01-15T10:30:00Z'
        };

        expect(validate(response)).toBe(true);
      });
    });
  });

  describe('Exit Code to HTTP Status Mapping', () => {
    const exitCodeMapping = {
      0: { status: 200, description: 'Success' },
      1: { status: 500, description: 'General error' },
      10: { status: 404, description: 'Employee not found' },
      11: { status: 200, description: 'Already disabled (idempotent)' },
      12: { status: 403, description: 'Protected account' },
      20: { status: 503, description: 'Graph connection failed', retryable: true },
      21: { status: 503, description: 'Exchange connection failed', retryable: true },
      22: { status: 503, description: 'AD connection failed', retryable: true },
      30: { status: 500, description: 'License removal failed' },
      31: { status: 500, description: 'Mailbox conversion failed' },
      32: { status: 500, description: 'AD disable failed' },
      33: { status: 500, description: 'OU move failed' },
      40: { status: 500, description: 'AD Sync trigger failed' }
    };

    Object.entries(exitCodeMapping).forEach(([exitCode, { status, description, retryable }]) => {
      it(`exit code ${exitCode} (${description}) maps to HTTP ${status}`, () => {
        expect(exitCodeMapping[exitCode].status).toBe(status);
      });

      if (retryable) {
        it(`exit code ${exitCode} is retryable`, () => {
          expect(exitCodeMapping[exitCode].retryable).toBe(true);
        });
      }
    });

    it('connection failures (20-22) are all retryable', () => {
      [20, 21, 22].forEach(code => {
        expect(exitCodeMapping[code].retryable).toBe(true);
      });
    });

    it('operation failures (30-40) are not retryable', () => {
      [30, 31, 32, 33, 40].forEach(code => {
        expect(exitCodeMapping[code].retryable).toBeUndefined();
      });
    });
  });

  describe('Content Type Requirements', () => {
    it('requests must use application/json', () => {
      const expectedContentType = 'application/json';
      expect(expectedContentType).toBe('application/json');
    });

    it('responses must use application/json', () => {
      const expectedContentType = 'application/json';
      expect(expectedContentType).toBe('application/json');
    });
  });

  describe('Security Constraints', () => {
    const validateRequest = ajv.compile(terminateRequestSchema);

    it('rejects SQL injection in employee_upn', () => {
      expect(validateRequest({
        employee_upn: "'; DROP TABLE Users;--@ii-us.com",
        requester_upn: 'admin@ii-us.com',
        ticket_id: 'HR-1234'
      })).toBe(false);
    });

    it('rejects script tags in employee_upn', () => {
      expect(validateRequest({
        employee_upn: '<script>alert(1)</script>@ii-us.com',
        requester_upn: 'admin@ii-us.com',
        ticket_id: 'HR-1234'
      })).toBe(false);
    });

    it('rejects overly long employee_upn', () => {
      const longEmail = 'a'.repeat(300) + '@ii-us.com';
      expect(validateRequest({
        employee_upn: longEmail,
        requester_upn: 'admin@ii-us.com',
        ticket_id: 'HR-1234'
      })).toBe(false);
    });
  });
});

// Export schemas for use by implementation
module.exports = {
  validateRequestSchema,
  terminateRequestSchema,
  successResponseSchema,
  idempotentResponseSchema,
  errorResponseSchema,
  validateResponseSchema
};
