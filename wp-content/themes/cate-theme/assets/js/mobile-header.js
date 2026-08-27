( function() {
	var breakpoint = window.matchMedia( '(max-width: 999px)' );
	var compactClass = 'cate-mobile-header-compact';
	var root = document.documentElement;
	var body;
	var header;
	var lastScrollY = window.pageYOffset || root.scrollTop || 0;
	var rafId;
	var resizeObserver;

	function getHeader() {
		if ( ! header ) {
			header = document.getElementById( 'site-header' );
		}

		return header;
	}

	function updateHeaderOffset() {
		var siteHeader = getHeader();

		if ( ! siteHeader ) {
			return;
		}

		if ( breakpoint.matches ) {
			root.style.setProperty( '--cate-mobile-header-height', siteHeader.offsetHeight + 'px' );
		} else {
			root.style.removeProperty( '--cate-mobile-header-height' );
		}
	}

	function setCompactState() {
		var currentScrollY = Math.max( 0, window.pageYOffset || root.scrollTop || 0 );
		var scrollDelta = currentScrollY - lastScrollY;

		if ( ! body ) {
			body = document.body;
		}

		if ( ! body ) {
			return;
		}

		if ( ! breakpoint.matches ) {
			body.classList.remove( compactClass );
			lastScrollY = currentScrollY;
			return;
		}

		if ( currentScrollY <= 8 ) {
			body.classList.remove( compactClass );
		} else if ( scrollDelta > 2 ) {
			body.classList.add( compactClass );
		} else if ( scrollDelta < -2 ) {
			body.classList.remove( compactClass );
		}

		lastScrollY = currentScrollY;
	}

	function requestUpdate() {
		if ( rafId ) {
			return;
		}

		rafId = window.requestAnimationFrame( function() {
			rafId = null;
			setCompactState();
			updateHeaderOffset();
		} );
	}

	function observeHeader() {
		var siteHeader = getHeader();

		if ( ! siteHeader || ! ( 'ResizeObserver' in window ) || resizeObserver ) {
			return;
		}

		resizeObserver = new ResizeObserver( requestUpdate );
		resizeObserver.observe( siteHeader );
	}

	function init() {
		observeHeader();
		requestUpdate();
	}

	if ( document.readyState === 'loading' ) {
		document.addEventListener( 'DOMContentLoaded', init );
	} else {
		init();
	}

	window.addEventListener( 'load', requestUpdate );
	window.addEventListener( 'resize', requestUpdate );
	window.addEventListener( 'scroll', requestUpdate, { passive: true } );

	if ( breakpoint.addEventListener ) {
		breakpoint.addEventListener( 'change', requestUpdate );
	} else if ( breakpoint.addListener ) {
		breakpoint.addListener( requestUpdate );
	}
}() );
