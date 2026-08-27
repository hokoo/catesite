#!/usr/bin/env bash
set -Eeuo pipefail

APP_ROOT="${APP_ROOT:-/srv/web/kate-tron.com}"
DEPLOY_ROOT="${DEPLOY_ROOT:-/srv/web/kate-tron}"
RELEASES_DIR="${RELEASES_DIR:-$DEPLOY_ROOT/releases}"
BACKUPS_DIR="${BACKUPS_DIR:-$DEPLOY_ROOT/backups}"
CURRENT_LINK="${CURRENT_LINK:-$DEPLOY_ROOT/current}"
ROLLBACK_RUN_ID="${ROLLBACK_RUN_ID:-}"
RESTORE_DB="${RESTORE_DB:-false}"
HEALTHCHECK_URL="${HEALTHCHECK_URL:-https://kate-tron.com/}"
ORIGIN_HOST="${ORIGIN_HOST:-kate-tron.com}"
AUTO_RESTORE_DB_ON_FAIL="${AUTO_RESTORE_DB_ON_FAIL:-true}"
WP_CLI_BIN="${WP_CLI_BIN:-wp}"
WP_CLI_PHP="${WP_CLI_PHP:-php8.5}"
PREVIOUS_RELEASE_DIR=""
SWITCHED=0

die() {
	printf 'ERROR: %s\n' "$*" >&2
	exit 1
}

wp_cmd() {
	"$WP_CLI_PHP" "$(command -v "$WP_CLI_BIN")" --allow-root --path="$APP_ROOT/wordpress" "$@"
}

remove_file_if_exists() {
	local path="$1"
	if [ -e "$path" ] || [ -L "$path" ]; then
		unlink "$path"
	fi
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

current_release_id() {
	local target
	target="$(readlink -f "$CURRENT_LINK" 2>/dev/null || true)"
	[ -n "$target" ] || die "current release link is missing: $CURRENT_LINK"
	basename "$target"
}

previous_release_id() {
	local current_id="$1"
	find "$RELEASES_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' \
		| awk -v current="$current_id" '/^[0-9]+$/ && $1 < current { print }' \
		| sort -n \
		| tail -1
}

next_release_after() {
	local target_id="$1"
	find "$RELEASES_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' \
		| awk -v target="$target_id" '/^[0-9]+$/ && $1 > target { print }' \
		| sort -n \
		| head -1
}

db_backup_for_target() {
	local target_id="$1"
	local next_id

	if [ -f "$BACKUPS_DIR/db/db-after-$target_id.sql" ]; then
		printf '%s\n' "$BACKUPS_DIR/db/db-after-$target_id.sql"
		return 0
	fi

	next_id="$(next_release_after "$target_id")"
	if [ -n "$next_id" ] && [ -f "$BACKUPS_DIR/db/db-before-$next_id.sql" ]; then
		printf '%s\n' "$BACKUPS_DIR/db/db-before-$next_id.sql"
		return 0
	fi

	return 1
}

require_target() {
	local target_id="$1"
	[[ "$target_id" =~ ^[0-9]+$ ]] || die "rollback target must be a numeric GitHub run id: $target_id"
	[ -d "$RELEASES_DIR/$target_id" ] || die "release does not exist: $RELEASES_DIR/$target_id"
}

maintenance_on() {
	wp_cmd maintenance-mode activate >/dev/null 2>&1 || true
}

maintenance_off() {
	if [ -e "$APP_ROOT" ] || [ -L "$APP_ROOT" ]; then
		remove_file_if_exists "$APP_ROOT/.maintenance" 2>/dev/null || true
		wp_cmd maintenance-mode deactivate >/dev/null 2>&1 || true
	fi
}

switch_to_release() {
	local target_id="$1"
	local target_dir="$RELEASES_DIR/$target_id"
	PREVIOUS_RELEASE_DIR="$(readlink -f "$CURRENT_LINK" 2>/dev/null || true)"
	ln -sfn "$target_dir" "$CURRENT_LINK.next"
	mv -Tf "$CURRENT_LINK.next" "$CURRENT_LINK"
	ensure_app_root_symlink
	SWITCHED=1
}

healthcheck() {
	local target_id="$1"
	local base="${HEALTHCHECK_URL%/}"
	curl -fsS --retry 3 --retry-delay 3 --max-time 20 --resolve "$ORIGIN_HOST:443:127.0.0.1" "$base/?rollback_check=$target_id" >/dev/null
	curl -fsS --retry 3 --retry-delay 3 --max-time 20 --resolve "$ORIGIN_HOST:443:127.0.0.1" "$base/wp-json/?rollback_check=$target_id" >/dev/null
}

rollback_switch_on_error() {
	local exit_code=$?
	set +e
	maintenance_off

	if [ "$SWITCHED" = "1" ] && [ -n "$PREVIOUS_RELEASE_DIR" ] && [ -d "$PREVIOUS_RELEASE_DIR" ]; then
		ln -sfn "$PREVIOUS_RELEASE_DIR" "$CURRENT_LINK.next"
		mv -Tf "$CURRENT_LINK.next" "$CURRENT_LINK"
		ensure_app_root_symlink
		printf 'Restored previous release after rollback failure: %s\n' "$PREVIOUS_RELEASE_DIR" >&2
	fi

	if [ "$AUTO_RESTORE_DB_ON_FAIL" = "true" ] && [ -n "${rollback_db_snapshot:-}" ] && [ -f "$rollback_db_snapshot" ]; then
		wp_cmd db import "$rollback_db_snapshot" || true
		printf 'Restored pre-rollback database snapshot after rollback failure.\n' >&2
	fi

	exit "$exit_code"
}

main() {
	command -v "$WP_CLI_BIN" >/dev/null || die "wp-cli is not installed on the server"
	command -v "$WP_CLI_PHP" >/dev/null || die "$WP_CLI_PHP is not installed on the server"
	command -v curl >/dev/null || die "curl is not installed on the server"
	[ -L "$APP_ROOT" ] || die "$APP_ROOT is not a release symlink yet; rollback is available after the first release-directory deploy"

	local current_id
	local target_id
	local rollback_db_snapshot
	current_id="$(current_release_id)"

	if [ -n "$ROLLBACK_RUN_ID" ]; then
		target_id="$ROLLBACK_RUN_ID"
	else
		target_id="$(previous_release_id "$current_id")"
		[ -n "$target_id" ] || die "no previous release exists before current release $current_id"
	fi

	require_target "$target_id"

	if [ "$target_id" = "$current_id" ] && [ "$RESTORE_DB" != "true" ]; then
		healthcheck "$target_id"
		printf 'Rollback target is already current release: %s\n' "$target_id"
		return 0
	fi

	mkdir -p "$BACKUPS_DIR/db"
	rollback_db_snapshot="$BACKUPS_DIR/db/db-before-rollback-$current_id-to-$target_id-$(date -u +%Y%m%dT%H%M%SZ).sql"
	wp_cmd db export "$rollback_db_snapshot" --add-drop-table

	maintenance_on
	trap rollback_switch_on_error ERR
	trap maintenance_off EXIT

	switch_to_release "$target_id"

	if [ "$RESTORE_DB" = "true" ]; then
		db_backup="$(db_backup_for_target "$target_id" || true)"
		[ -n "${db_backup:-}" ] || die "no database backup found for target release $target_id"
		wp_cmd db import "$db_backup"
	fi

	wp_cmd core update-db
	wp_cmd rewrite flush
	wp_cmd cache flush || true
	maintenance_off
	healthcheck "$target_id"
	trap - ERR
	trap - EXIT

	printf 'Rollback completed: %s -> %s\n' "$current_id" "$target_id"
}

main "$@"
