#!/usr/bin/env bash
set -Eeuo pipefail

if [ ! -f .env ]; then
	cp install/.example/.env.example .env
fi

if ! grep -q '^PHP_TAG=' .env; then
	printf '\nPHP_TAG=8.3\n' >> .env
fi

bash install/setup-env.sh

docker compose up -d --build

for _ in $(seq 1 60); do
	if docker compose exec -T mysql sh -lc 'mariadb-admin ping -h 127.0.0.1 -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" --silent' >/dev/null 2>&1; then
		break
	fi
	sleep 2
done

docker compose exec -T mysql sh -lc 'mariadb-admin ping -h 127.0.0.1 -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" --silent'
composer install --no-interaction --no-progress
docker compose exec -T php bash -lc 'printf "n\n" | bash ./install/setup-wp.sh'
docker compose exec -T php bash -lc '
	. ./.env
	if ! wp core is-installed >/dev/null 2>&1; then
		wp core install \
			--url="$PROJECT_BASE_URL" \
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
