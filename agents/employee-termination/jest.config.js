/**
 * Jest Configuration for Employee Termination Agent
 *
 * Run tests with: npm test
 * Run with coverage: npm run test:coverage
 */

module.exports = {
  // Test environment
  testEnvironment: 'node',

  // Test file patterns
  testMatch: [
    '**/tests/**/*.test.js'
  ],

  // Ignore patterns
  testPathIgnorePatterns: [
    '/node_modules/',
    '/coverage/'
  ],

  // Coverage configuration
  collectCoverage: false, // Enable with --coverage flag
  collectCoverageFrom: [
    'server.js',
    '!**/node_modules/**',
    '!**/tests/**',
    '!jest.config.js'
  ],
  coverageDirectory: 'coverage',
  coverageReporters: ['text', 'text-summary', 'lcov', 'html'],
  coverageThreshold: {
    global: {
      branches: 80,
      functions: 80,
      lines: 80,
      statements: 80
    }
  },

  // Setup files
  setupFilesAfterEnv: ['./jest.setup.js'],

  // Timeout for async tests (5 minutes for n8n integration tests)
  testTimeout: 300000,

  // Verbose output
  verbose: true,

  // Force exit after tests complete
  forceExit: true,

  // Detect open handles
  detectOpenHandles: true,

  // Clear mocks between tests
  clearMocks: true,

  // Restore mocks after each test
  restoreMocks: true,

  // Module name mapper for aliases (if needed)
  moduleNameMapper: {},

  // Transform files (use default for ES modules)
  transform: {},

  // Reporter configuration
  reporters: [
    'default',
    [
      'jest-junit',
      {
        outputDirectory: 'coverage',
        outputName: 'junit.xml',
        suiteName: 'Employee Termination Agent Tests'
      }
    ]
  ].filter(r => {
    // Only use jest-junit if installed
    if (Array.isArray(r) && r[0] === 'jest-junit') {
      try {
        require.resolve('jest-junit');
        return true;
      } catch {
        return false;
      }
    }
    return true;
  })
};
