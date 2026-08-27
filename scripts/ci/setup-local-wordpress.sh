#!/usr/bin/env bash
set -Eeuo pipefail

if [ ! -f .env ]; then
	cp install/.example/.env.example .env
fi

if ! grep -q '^PHP_TAG=' .env; then
	printf '\nPHP_TAG=8.3\n' >> .env
fi

. ./.env

bash install/setup-env.sh

composer install --no-interaction --no-progress

if [ ! -f ./index.php ]; then
	printf '%s\n' \
		'<?php' \
		"define( 'WP_USE_THEMES', true );" \
		"require __DIR__ . '/wordpress/wp-blog-header.php';" > ./index.php
fi

if [ ! -f ./wp-config.php ]; then
	WPCONFIG=$(< ./install/.example/wp-config.php.template)
	printf "$WPCONFIG" "$DB_NAME" "$DB_USER" "$DB_PASSWORD" "$DB_HOST" "$PROJECT_BASE_URL" > ./wp-config.php
fi

docker compose up -d --build

for _ in $(seq 1 60); do
	if docker compose exec -T mysql sh -lc 'mariadb-admin ping -h 127.0.0.1 -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" --silent' >/dev/null 2>&1; then
		break
	fi
	sleep 2
done

docker compose exec -T mysql sh -lc 'mariadb-admin ping -h 127.0.0.1 -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" --silent'
docker compose exec -T php bash -lc '
	. ./.env
	if ! wp core is-installed >/dev/null 2>&1; then
		wp core install \
			--url="http://cate.loc" \
			--title="$WP_TITLE" \
			--admin_user="$WP_ADMIN" \
			--admin_password="$WP_ADMIN_PASS" \
			--admin_email="$WP_ADMIN_EMAIL" \
			--skip-email
	fi
'
docker compose exec -T php wp option update home http://cate.loc
docker compose exec -T php wp option update siteurl http://cate.loc
docker compose exec -T php wp core update-db
docker compose exec -T php wp rewrite flush
