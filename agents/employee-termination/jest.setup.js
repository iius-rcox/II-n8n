/**
 * Jest Setup File
 *
 * This file runs before each test file.
 */

// Increase timeout for integration tests
jest.setTimeout(30000);

// Global test utilities
global.sleep = (ms) => new Promise(resolve => setTimeout(resolve, ms));

// Environment variables for testing
process.env.NODE_ENV = 'test';

// Suppress console output during tests (optional)
if (process.env.SUPPRESS_CONSOLE) {
  global.console = {
    ...console,
    log: jest.fn(),
    debug: jest.fn(),
    info: jest.fn(),
    warn: jest.fn(),
    // Keep error for debugging
    error: console.error
  };
}

// Add custom matchers
expect.extend({
  toBeValidUPN(received) {
    const upnRegex = /^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$/;
    const pass = upnRegex.test(received);
    return {
      message: () =>
        pass
          ? `expected ${received} not to be a valid UPN`
          : `expected ${received} to be a valid UPN`,
      pass
    };
  },

  toBeValidTicketId(received) {
    const ticketRegex = /^[A-Z]+-[0-9]+$/;
    const pass = ticketRegex.test(received);
    return {
      message: () =>
        pass
          ? `expected ${received} not to be a valid ticket ID`
          : `expected ${received} to be a valid ticket ID (e.g., HR-1234)`,
      pass
    };
  },

  toHaveExitCode(received, expected) {
    const pass = received && received.exit_code === expected;
    return {
      message: () =>
        pass
          ? `expected response not to have exit_code ${expected}`
          : `expected response to have exit_code ${expected}, got ${received?.exit_code}`,
      pass
    };
  }
});

// Cleanup after all tests
afterAll(async () => {
  // Close any open handles
  await new Promise(resolve => setTimeout(resolve, 500));
});

// Log test file being run
beforeAll(() => {
  if (process.env.DEBUG_TESTS) {
    console.log(`\nRunning tests in: ${expect.getState().testPath}\n`);
  }
});
