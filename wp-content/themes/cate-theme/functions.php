<?php
/**
 * Child theme functionality.
 *
 * @package Kate_Theme
 */

/**
 * Enqueues child theme scripts.
 */
function cate_theme_enqueue_scripts() {
	$theme_version = wp_get_theme()->get( 'Version' );

	wp_enqueue_script(
		'cate-theme-mobile-header',
		get_stylesheet_directory_uri() . '/assets/js/mobile-header.js',
		array( 'twentytwenty-js' ),
		$theme_version,
		true
	);
}

add_action( 'wp_enqueue_scripts', 'cate_theme_enqueue_scripts' );
