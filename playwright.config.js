const { defineConfig } = require( '@playwright/test' );

const baseURL = process.env.E2E_BASE_URL || 'http://cate.loc/';
const shouldStartServer = process.env.E2E_START_SERVER === '1';

module.exports = defineConfig( {
	testDir: './tests/e2e',
	timeout: 30000,
	expect: {
		timeout: 5000,
	},
	forbidOnly: !! process.env.CI,
	retries: process.env.CI ? 2 : 0,
	workers: process.env.CI ? 1 : undefined,
	reporter: process.env.CI
		? [
			[ 'list' ],
			[ 'html', { open: 'never' } ],
		]
		: 'list',
	use: {
		baseURL,
		browserName: 'chromium',
		screenshot: 'only-on-failure',
		trace: 'on-first-retry',
	},
	webServer: shouldStartServer
		? {
			command: 'docker-compose up -d',
			reuseExistingServer: true,
			timeout: 120000,
			url: baseURL,
		}
		: undefined,
} );
