( function() {
	var breakpoint = window.matchMedia( '(max-width: 999px)' );
	var root = document.documentElement;
	var header;
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

	function requestUpdate() {
		if ( rafId ) {
			return;
		}

		rafId = window.requestAnimationFrame( function() {
			rafId = null;
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

	if ( breakpoint.addEventListener ) {
		breakpoint.addEventListener( 'change', requestUpdate );
	} else if ( breakpoint.addListener ) {
		breakpoint.addListener( requestUpdate );
	}
}() );
