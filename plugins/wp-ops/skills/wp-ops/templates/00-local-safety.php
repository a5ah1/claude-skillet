<?php
/**
 * Plugin Name: Local Safety
 * Description: Kills outbound email and other prod-side effects. Drop into wp-content/mu-plugins/ on any non-prod WP install (local dev, staging, cloned test env). The `00-` filename prefix ensures it loads first among mu-plugins.
 * Version: 1.0
 */

// Defense-in-depth #1: short-circuit wp_mail() globally.
// `pre_wp_mail` is the officially documented hook for this. Returning non-null
// stops wp_mail() before it does anything.
add_filter( 'pre_wp_mail', '__return_false', 0 );

// Defense-in-depth #2: if some plugin bypasses wp_mail() and calls PHPMailer
// directly, corrupt the SMTP config so it physically can't connect.
add_action( 'phpmailer_init', function( $phpmailer ) {
    $phpmailer->Host     = 'localhost.invalid';
    $phpmailer->Port     = 25;
    $phpmailer->SMTPAuth = false;
    $phpmailer->Username = '';
    $phpmailer->Password = '';
} );

// Defense-in-depth #3: add a visible admin notice so anyone working on the
// clone sees that mail is disabled.
add_action( 'admin_notices', function() {
    echo '<div class="notice notice-warning"><p><strong>Local safety mu-plugin active:</strong> outbound email is disabled on this install.</p></div>';
} );

// Defense-in-depth #4: log any attempt to send mail (helpful for diagnosing
// which plugins are trying to phone home).
add_filter( 'pre_wp_mail', function( $null, $atts ) {
    error_log( sprintf(
        '[local-safety] wp_mail blocked — to=%s subject=%s',
        is_array( $atts['to'] ?? null ) ? implode( ',', $atts['to'] ) : ( $atts['to'] ?? '?' ),
        $atts['subject'] ?? '?'
    ) );
    return false;
}, 0, 2 );
