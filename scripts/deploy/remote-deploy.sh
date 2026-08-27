#!/usr/bin/env bash
set -Eeuo pipefail

APP_ROOT="${APP_ROOT:-/srv/web/kate-tron.com}"
DEPLOY_ROOT="${DEPLOY_ROOT:-/srv/web/kate-tron}"
RELEASES_DIR="${RELEASES_DIR:-$DEPLOY_ROOT/releases}"
SHARED_DIR="${SHARED_DIR:-$DEPLOY_ROOT/shared}"
BACKUPS_DIR="${BACKUPS_DIR:-$DEPLOY_ROOT/backups}"
CURRENT_LINK="${CURRENT_LINK:-$DEPLOY_ROOT/current}"
RELEASE_ID="${RELEASE_ID:?RELEASE_ID is required}"
RELEASE_SHA="${RELEASE_SHA:-unknown}"
RUN_NUMBER="${RUN_NUMBER:-unknown}"
RUN_ATTEMPT="${RUN_ATTEMPT:-unknown}"
HEALTHCHECK_URL="${HEALTHCHECK_URL:-https://kate-tron.com/}"
ORIGIN_HOST="${ORIGIN_HOST:-kate-tron.com}"
AUTO_RESTORE_DB_ON_FAIL="${AUTO_RESTORE_DB_ON_FAIL:-true}"
KEEP_RELEASES="${KEEP_RELEASES:-5}"
KEEP_BACKUPS="${KEEP_BACKUPS:-5}"
WP_CLI_BIN="${WP_CLI_BIN:-wp}"
WP_CLI_PHP="${WP_CLI_PHP:-php8.5}"

RELEASE_DIR="$RELEASES_DIR/$RELEASE_ID"
DB_BEFORE_BACKUP="$BACKUPS_DIR/db/db-before-$RELEASE_ID.sql"
DB_AFTER_BACKUP="$BACKUPS_DIR/db/db-after-$RELEASE_ID.sql"
PREVIOUS_RELEASE_DIR=""
LEGACY_BACKUP_DIR=""
SWITCHED=0

die() {
	printf 'ERROR: %s\n' "$*" >&2
	exit 1
}

require_numeric_release_id() {
	[[ "$RELEASE_ID" =~ ^[0-9]+$ ]] || die "release id must be the numeric GitHub run id: $RELEASE_ID"
}

wp_cmd() {
	"$WP_CLI_PHP" "$(command -v "$WP_CLI_BIN")" --allow-root --path="$APP_ROOT/wordpress" "$@"
}

release_wp_cmd() {
	"$WP_CLI_PHP" "$(command -v "$WP_CLI_BIN")" --allow-root --path="$RELEASE_DIR/wordpress" "$@"
}

detect_owner() {
	if [ -n "${APP_OWNER:-}" ]; then
		printf '%s\n' "$APP_OWNER"
	elif [ -e "$APP_ROOT" ]; then
		stat -c '%U:%G' "$APP_ROOT"
	else
		printf '%s:%s\n' "$(id -un)" "$(id -gn)"
	fi
}

set_owner() {
	local owner="$1"
	if [ "$(id -u)" = "0" ]; then
		chown -hR "$owner" "$DEPLOY_ROOT"
		if [ -e "$APP_ROOT" ] || [ -L "$APP_ROOT" ]; then
			chown -h "$owner" "$APP_ROOT"
		fi
	fi
}

remove_file_if_exists() {
	local path="$1"
	if [ -e "$path" ] || [ -L "$path" ]; then
		unlink "$path"
	fi
}

remove_tree_if_exists() {
	local path="$1"
	if [ ! -e "$path" ] && [ ! -L "$path" ]; then
		return 0
	fi

	if [ -L "$path" ] || [ -f "$path" ]; then
		unlink "$path"
		return 0
	fi

	find "$path" -depth -mindepth 1 -delete
	rmdir "$path"
}

app_root_resolves_to_current() {
	[ -L "$APP_ROOT" ] || return 1
	[ "$(readlink -f "$APP_ROOT" 2>/dev/null)" = "$(readlink -f "$CURRENT_LINK" 2>/dev/null)" ]
}

ensure_app_root_symlink() {
	if app_root_resolves_to_current; then
		return 0
	fi

	ln -sfn "$CURRENT_LINK" "$APP_ROOT.next"
	mv -Tf "$APP_ROOT.next" "$APP_ROOT"
}

ensure_shared_runtime() {
	mkdir -p "$RELEASES_DIR" "$SHARED_DIR/wp-content" "$BACKUPS_DIR/db" "$BACKUPS_DIR/code"

	if [ -e "$APP_ROOT/wp-config.php" ] && [ ! -e "$SHARED_DIR/wp-config.php" ]; then
		cp -a "$APP_ROOT/wp-config.php" "$SHARED_DIR/wp-config.php"
	fi

	if [ -e "$APP_ROOT/.env" ] && [ ! -e "$SHARED_DIR/.env" ]; then
		cp -a "$APP_ROOT/.env" "$SHARED_DIR/.env"
	fi

	if [ -d "$APP_ROOT/wp-content/uploads" ] && [ ! -e "$SHARED_DIR/wp-content/uploads" ]; then
		cp -a "$APP_ROOT/wp-content/uploads" "$SHARED_DIR/wp-content/uploads"
	fi

	mkdir -p "$SHARED_DIR/wp-content/uploads"
	[ -f "$SHARED_DIR/wp-config.php" ] || die "shared wp-config.php is missing at $SHARED_DIR/wp-config.php"
}

prepare_release_runtime() {
	[ -d "$RELEASE_DIR" ] || die "release directory does not exist: $RELEASE_DIR"

	mkdir -p "$RELEASE_DIR/wp-content"
	cp -a "$SHARED_DIR/wp-config.php" "$RELEASE_DIR/wp-config.php"

	if [ -f "$SHARED_DIR/.env" ]; then
		cp -a "$SHARED_DIR/.env" "$RELEASE_DIR/.env"
	fi

	if [ -e "$RELEASE_DIR/wp-content/uploads" ] || [ -L "$RELEASE_DIR/wp-content/uploads" ]; then
		remove_tree_if_exists "$RELEASE_DIR/wp-content/uploads"
	fi
	ln -s "$SHARED_DIR/wp-content/uploads" "$RELEASE_DIR/wp-content/uploads"

	if [ ! -f "$RELEASE_DIR/index.php" ]; then
cat > "$RELEASE_DIR/index.php" <<'PHP'
<?php
define( 'WP_USE_THEMES', true );
require __DIR__ . '/wordpress/wp-blog-header.php';
PHP
	fi

	cat > "$RELEASE_DIR/.deploy-release" <<EOF
release_id=$RELEASE_ID
release_sha=$RELEASE_SHA
run_number=$RUN_NUMBER
run_attempt=$RUN_ATTEMPT
deployed_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF
}

preflight_release() {
	command -v "$WP_CLI_BIN" >/dev/null || die "wp-cli is not installed on the server"
	command -v "$WP_CLI_PHP" >/dev/null || die "$WP_CLI_PHP is not installed on the server"
	command -v curl >/dev/null || die "curl is not installed on the server"
	command -v rsync >/dev/null || die "rsync is not installed on the server"
	[ -d "$RELEASE_DIR/wordpress" ] || die "WordPress core directory is missing in release"
	[ -d "$RELEASE_DIR/vendor" ] || die "Composer vendor directory is missing in release"
	[ -d "$RELEASE_DIR/wp-content/themes/cate-theme" ] || die "active theme is missing in release"
	release_wp_cmd core is-installed >/dev/null
	release_wp_cmd core version >/dev/null
}

backup_database() {
	if wp_cmd core is-installed >/dev/null 2>&1; then
		wp_cmd db export "$DB_BEFORE_BACKUP" --add-drop-table
	fi
}

maintenance_on() {
	printf '<?php $upgrading = %s;\n' "$(date +%s)" > "$RELEASE_DIR/.maintenance"
	if [ -e "$APP_ROOT" ] || [ -L "$APP_ROOT" ]; then
		wp_cmd maintenance-mode activate >/dev/null 2>&1 || true
	fi
}

maintenance_off() {
	remove_file_if_exists "$RELEASE_DIR/.maintenance" 2>/dev/null || true
	if [ -e "$APP_ROOT" ] || [ -L "$APP_ROOT" ]; then
		remove_file_if_exists "$APP_ROOT/.maintenance" 2>/dev/null || true
		wp_cmd maintenance-mode deactivate >/dev/null 2>&1 || true
	fi
}

switch_release() {
	PREVIOUS_RELEASE_DIR="$(readlink -f "$CURRENT_LINK" 2>/dev/null || true)"

	ln -sfn "$RELEASE_DIR" "$CURRENT_LINK.next"
	mv -Tf "$CURRENT_LINK.next" "$CURRENT_LINK"

	if [ -L "$APP_ROOT" ]; then
		ensure_app_root_symlink
	elif [ -e "$APP_ROOT" ]; then
		LEGACY_BACKUP_DIR="$BACKUPS_DIR/code/live-root-before-release-$RELEASE_ID"
		[ ! -e "$LEGACY_BACKUP_DIR" ] || die "legacy backup already exists: $LEGACY_BACKUP_DIR"
		mv "$APP_ROOT" "$LEGACY_BACKUP_DIR"
		ln -s "$CURRENT_LINK" "$APP_ROOT"
	else
		ensure_app_root_symlink
	fi

	SWITCHED=1
}

rollback_switch_on_error() {
	local exit_code=$?
	set +e
	maintenance_off
	if [ "$SWITCHED" = "1" ]; then
		if [ -n "$PREVIOUS_RELEASE_DIR" ] && [ -d "$PREVIOUS_RELEASE_DIR" ]; then
			ln -sfn "$PREVIOUS_RELEASE_DIR" "$CURRENT_LINK.next"
			mv -Tf "$CURRENT_LINK.next" "$CURRENT_LINK"
			ensure_app_root_symlink
			printf 'Rolled active release back to %s after deployment failure.\n' "$PREVIOUS_RELEASE_DIR" >&2
		elif [ -n "$LEGACY_BACKUP_DIR" ] && [ -d "$LEGACY_BACKUP_DIR" ]; then
			if [ -L "$APP_ROOT" ]; then
				unlink "$APP_ROOT"
			fi
			mv "$LEGACY_BACKUP_DIR" "$APP_ROOT"
			printf 'Restored legacy live root after first deployment failure.\n' >&2
		fi

		if [ "$AUTO_RESTORE_DB_ON_FAIL" = "true" ] && [ -f "$DB_BEFORE_BACKUP" ]; then
			wp_cmd db import "$DB_BEFORE_BACKUP" || true
			printf 'Restored pre-deploy database backup after deployment failure.\n' >&2
		fi
	fi
	exit "$exit_code"
}

run_post_switch_tasks() {
	wp_cmd core update-db
	wp_cmd rewrite flush
	wp_cmd cache flush || true
	wp_cmd db export "$DB_AFTER_BACKUP" --add-drop-table || true
}

healthcheck() {
	local base="${HEALTHCHECK_URL%/}"
	curl -fsS --retry 3 --retry-delay 3 --max-time 20 --resolve "$ORIGIN_HOST:443:127.0.0.1" "$base/?deploy_check=$RELEASE_ID" >/dev/null
	curl -fsS --retry 3 --retry-delay 3 --max-time 20 --resolve "$ORIGIN_HOST:443:127.0.0.1" "$base/wp-json/?deploy_check=$RELEASE_ID" >/dev/null
}

prune_numbered_entries() {
	local dir="$1"
	local keep="$2"
	[ -d "$dir" ] || return 0
	find "$dir" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' \
		| awk '/^[0-9]+$/ { print }' \
		| sort -nr \
		| tail -n +"$(( keep + 1 ))" \
		| while IFS= read -r entry; do
			[ -n "$entry" ] || continue
			[ "$entry" != "$RELEASE_ID" ] || continue
			remove_tree_if_exists "$dir/$entry"
		done
}

prune_backup_files() {
	local pattern="$1"
	local keep="$2"
	find "$BACKUPS_DIR/db" -maxdepth 1 -type f -name "$pattern" -printf '%T@ %p\n' \
		| sort -nr \
		| tail -n +"$(( keep + 1 ))" \
		| cut -d' ' -f2- \
		| while IFS= read -r file; do
			[ -n "$file" ] || continue
			remove_file_if_exists "$file"
		done
}

main() {
	require_numeric_release_id
	local owner
	owner="$(detect_owner)"
	ensure_shared_runtime
	prepare_release_runtime
	set_owner "$owner"
	preflight_release
	backup_database
	maintenance_on

	trap rollback_switch_on_error ERR
	trap maintenance_off EXIT

	switch_release
	set_owner "$owner"
	run_post_switch_tasks
	healthcheck
	maintenance_off
	trap - ERR EXIT

	prune_numbered_entries "$RELEASES_DIR" "$KEEP_RELEASES"
	prune_backup_files 'db-before-*.sql' "$KEEP_BACKUPS"
	prune_backup_files 'db-after-*.sql' "$KEEP_BACKUPS"

	printf 'Deployment completed: release %s (%s)\n' "$RELEASE_ID" "$RELEASE_SHA"
}

main "$@"
