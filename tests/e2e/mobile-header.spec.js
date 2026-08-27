const { test, expect } = require( '@playwright/test' );

async function getHeaderState( page ) {
	return page.evaluate( () => {
		const header = document.querySelector( '#site-header' );
		const navToggle = document.querySelector( '.mobile-nav-toggle' );
		const menuText = document.querySelector( '.mobile-nav-toggle .toggle-text' );
		const menuIcon = document.querySelector( '.mobile-nav-toggle svg' );
		const title = document.querySelector( '.header-titles .site-title, .header-titles .faux-heading' );
		const firstContent = document.querySelector( '.entry-content, main, #site-content' );
		const headerRect = header.getBoundingClientRect();
		const contentRect = firstContent.getBoundingClientRect();
		const menuIconRect = menuIcon.getBoundingClientRect();
		const headerStyles = getComputedStyle( header );
		const menuTextStyles = getComputedStyle( menuText );
		const titleStyles = title ? getComputedStyle( title ) : null;

		return {
			bodyPaddingTop: parseFloat( getComputedStyle( document.body ).paddingTop ),
			contentTop: contentRect.top,
			headerHeight: headerRect.height,
			headerTop: headerRect.top,
			iconHeight: menuIconRect.height,
			iconWidth: menuIconRect.width,
			isCompact: document.body.classList.contains( 'cate-mobile-header-compact' ),
			menuTextOpacity: parseFloat( menuTextStyles.opacity ),
			menuTextVisibility: menuTextStyles.visibility,
			navToggleVisible: !! navToggle && getComputedStyle( navToggle ).display !== 'none',
			position: headerStyles.position,
			titleFontSize: titleStyles ? parseFloat( titleStyles.fontSize ) : null,
			zIndex: Number( headerStyles.zIndex ),
		};
	} );
}

test.describe( 'mobile fixed header', () => {
	test.beforeEach( async ( { page } ) => {
		await page.setViewportSize( { width: 390, height: 844 } );
		await page.goto( '/', { waitUntil: 'networkidle' } );
		await page.waitForSelector( '#site-header .mobile-nav-toggle' );
	} );

	test( 'stays fixed and reserves content offset', async ( { page } ) => {
		const state = await getHeaderState( page );

		expect( state.position ).toBe( 'fixed' );
		expect( state.zIndex ).toBeGreaterThanOrEqual( 90 );
		expect( state.headerTop ).toBe( 0 );
		expect( state.navToggleVisible ).toBe( true );
		expect( Math.abs( state.bodyPaddingTop - state.headerHeight ) ).toBeLessThanOrEqual( 1 );
		expect( state.contentTop ).toBeGreaterThanOrEqual( state.headerHeight );
	} );

	test( 'shrinks on downward scroll and expands on upward scroll', async ( { page } ) => {
		const expanded = await getHeaderState( page );

		await page.evaluate( () => window.scrollTo( 0, 600 ) );
		await expect.poll( async () => ( await getHeaderState( page ) ).isCompact ).toBe( true );
		await page.waitForTimeout( 300 );

		const compact = await getHeaderState( page );

		expect( compact.headerHeight ).toBeLessThanOrEqual( expanded.headerHeight * 0.65 );
		expect( Math.abs( compact.bodyPaddingTop - compact.headerHeight ) ).toBeLessThanOrEqual( 1 );
		expect( compact.menuTextOpacity ).toBeLessThanOrEqual( 0.05 );
		expect( compact.menuTextVisibility ).toBe( 'hidden' );
		expect( compact.iconHeight ).toBeGreaterThan( compact.iconWidth );

		if ( expanded.titleFontSize !== null && compact.titleFontSize !== null ) {
			expect( compact.titleFontSize ).toBeLessThan( expanded.titleFontSize );
		}

		await page.evaluate( () => window.scrollTo( 0, 50 ) );
		await expect.poll( async () => ( await getHeaderState( page ) ).isCompact ).toBe( false );
		await page.waitForTimeout( 300 );

		const restored = await getHeaderState( page );

		expect( restored.headerHeight ).toBeGreaterThanOrEqual( expanded.headerHeight * 0.95 );
		expect( restored.menuTextOpacity ).toBeGreaterThanOrEqual( 0.95 );
		expect( restored.menuTextVisibility ).toBe( 'visible' );
		expect( restored.iconWidth ).toBeGreaterThan( restored.iconHeight );
	} );
} );

test.describe( 'desktop header', () => {
	test( 'keeps the parent theme desktop positioning', async ( { page } ) => {
		await page.setViewportSize( { width: 1000, height: 844 } );
		await page.goto( '/', { waitUntil: 'networkidle' } );
		await page.waitForSelector( '#site-header .mobile-nav-toggle', { state: 'attached' } );

		const initial = await getHeaderState( page );

		expect( initial.position ).toBe( 'relative' );
		expect( initial.bodyPaddingTop ).toBe( 0 );
		expect( initial.isCompact ).toBe( false );
		expect( initial.navToggleVisible ).toBe( false );

		await page.evaluate( () => window.scrollTo( 0, 600 ) );
		await page.waitForTimeout( 300 );

		const scrolled = await getHeaderState( page );

		expect( scrolled.position ).toBe( 'relative' );
		expect( scrolled.bodyPaddingTop ).toBe( 0 );
		expect( scrolled.isCompact ).toBe( false );
	} );
} );
