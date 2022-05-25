#!/bin/bash
echo -n "Script will remove all configs and generated folders. Sure? (y/n) "

read item
case "$item" in
    y|Y)
    rm -rf ./vendor
    rm -rf ./wp
    rm -f ./wp-config.php
    rm -rf ./install/nginx
    rm -f ./install/php-fpm/error.log
    rm -f ./.env
      ;;

    *)
      echo "Nothing has been done."
      ;;
esac
