#!/bin/bash

echo "WP setup preparing..."

# import variables from .env file
. ./.env

# prepare file structure
[ ! -d ./wp-content/ ] && mkdir -p ./wp-content/
cp -r ./wordpress/wp-content/* ./wp-content

[ ! -f ./index.php ] && echo "<?php
// WordPress view bootstrapper
define( 'WP_USE_THEMES', true );
require( './wordpress/wp-blog-header.php' );" > index.php

if [ ! -f wp-config.php ]; then
  WPCONFIG=$(< ./install/.example/wp-config.php.template)
  printf "$WPCONFIG" $DB_NAME $DB_USER $DB_PASSWORD $DB_HOST $PROJECT_BASE_URL > ./wp-config.php
fi

# install WP
echo -n "Would you import database from db.sql (y), init new instance (i), or do nothing (n)? (y/n/i)"

read item
case "$item" in
    y|Y)
    echo "WP database import..."
    wp db import db.sql
      ;;

    i|I)
    echo "WP database init new instance..."
    wp core install --url=$PROJECT_BASE_URL --title="$WP_TITLE" --admin_user=$WP_ADMIN --admin_password=$WP_ADMIN_PASS --admin_email=$WP_ADMIN_EMAIL --skip-email
    printf "WP User Admin: %s \nWP User Pass: %s\n" $WP_ADMIN $WP_ADMIN_PASS
      ;;

    *)
      echo "WP database has not been touched."
      ;;
esac

echo "Do not forget renew your hosts file 127.0.0.1 domain.loc"
echo "Done."

