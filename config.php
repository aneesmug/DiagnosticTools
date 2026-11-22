<?php
/**
 * IT Tools access settings.
 *
 * This file runs ON THE SERVER and is NEVER sent to users, so the password
 * here is not exposed. index.php reads these settings and only sends
 * Tools.bat after the password is correct.
 *
 * To turn the password on:
 *   1) set 'require_password' => true
 *   2) set a 'password' (or a 'password_sha256' hash - see below)
 *   3) upload this file next to index.php
 *
 * SECURITY TIP - store a hash instead of the plain password:
 *   Run this once (any PC with PHP) to get the hash of your password:
 *     php -r "echo hash('sha256','YOUR-PASSWORD');"
 *   Put the result in 'password_sha256' and leave 'password' empty.
 */
return [

    // Require a password before Tools.bat is delivered?  true / false
    'require_password' => false,

    // Plain-text password. Used only if 'password_sha256' is empty.
    'password' => '@DmiN56539306#',

    // SHA-256 hash of the password (preferred). Overrides 'password' when set.
    'password_sha256' => '',

    // Text shown on the password prompt.
    'prompt_message' => 'IT Tools - enter the access password',

    // Message shown when the password is wrong.
    'denied_message' => 'Wrong password - access denied.',

    // How many tries the prompt allows before giving up.
    'max_tries' => 3,

    // Seconds the server waits after a wrong password (slows guessing).
    'wrong_delay' => 2,
];
