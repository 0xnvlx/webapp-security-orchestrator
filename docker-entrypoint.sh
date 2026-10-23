#!/bin/sh
# Fix the mounted out/ ownership, then drop to the non-root analyst user.
#
# out/ is a bind mount, so Docker creates it owned by root (or a host uid) the
# first time — the analyst user then can't mkdir out/<target> for reports.
# Running as root here lets us chown it before handing control to analyst via
# gosu. If the container is started with --user (not root), we skip straight to
# the command.
#
# PUID/PGID (optional): remap analyst to the host user's uid/gid so files written
# to the mounted out/ are owned by the invoking user. analyst defaults to uid 1000
# (the usual first host user), so this is only needed where yours differs.
set -e

OUT=/home/analyst/webapp-security-orchestrator/out

if [ "$(id -u)" = "0" ]; then
    if [ -n "$PGID" ] && [ "$PGID" != "$(id -g analyst)" ]; then
        groupmod -o -g "$PGID" analyst
    fi
    if [ -n "$PUID" ] && [ "$PUID" != "$(id -u analyst)" ]; then
        usermod -o -u "$PUID" analyst
    fi
    if [ -n "$PUID" ] || [ -n "$PGID" ]; then
        chown -R analyst:analyst /home/analyst
    fi
    mkdir -p "$OUT"
    chown -R analyst:analyst "$OUT" 2>/dev/null || true
    exec gosu analyst "$@"
fi

exec "$@"
