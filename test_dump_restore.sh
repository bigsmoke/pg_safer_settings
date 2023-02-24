#!/bin/bash

SCRIPT_NAME=$(basename "$0")
PG_BIN_DIR="$(pg_config --bindir)"

usage() {
    cat <<EOF
Usage:
    $SCRIPT_NAME --extension <extension_name> --psql-script-file <file> --out-file <file> --expected-out-file <file>
    $SCRIPT_NAME --help|-h
EOF
}

psql_script_file=""
expected_out_file=""
out_file=""
extension_name=""
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        --psql-script-file)
            psql_script_file="$2"
            shift 2
            ;;
        --out-file)
            out_file="$2"
            shift 2
            ;;
        --expected-out-file)
            expected_out_file="$2"
            shift 2
            ;;
        --extension)
            extension_name="$2"
            shift 2
            ;;
        --*|-*)
            echo -e "\e[31mUnrecognized option: \e[1m$1\e[0m" >&2
            usage >&2
            exit 2
            ;;
    esac
done
if [ -z "$psql_script_file" ]; then
    echo -e "\e[31mMissing param: \e[1m--psql-script-file\e[0m" >&2
    usage >&2
    exit 2
fi
if [ -z "$out_file" ]; then
    echo -e "\e[31mMissing param: \e[1m--out-file\e[0m" >&2
    usage >&2
    exit 2
fi
if [ -z "$expected_out_file" ]; then
    echo -e "\e[31mMissing param: \e[1m--expected-out-file\e[0m" >&2
    usage >&2
    exit 2
fi
if [ -z "$extension_name" ]; then
    echo -e "\e[31mMissing param: \e[1m--extension\e[0m" >&2
    usage >&2
    exit 2
fi

cleanup() {
    if [ -n "$pg_pid" ]; then
        kill "$pg_pid"
    fi

    if [ -n "$tmp_dir" ]; then
        rm -rf "$tmp_dir"
    fi
}
trap cleanup exit

tmp_dir=$(mktemp --directory)
dump_file="$tmp_dir/dump"

export PGDATA="$tmp_dir/data"
export PGHOST="$tmp_dir"
export PGDATABASE="test_dump_restore"
export PGUSER="wortel"

"$PG_BIN_DIR/initdb" \
        --auth trust \
        --username "$PGUSER" \
        --pwfile <(echo ondergronds) >/dev/null 2>&1 || exit 4

"$PG_BIN_DIR/postgres" -k "$PGHOST" -h "" 2>/dev/null &
pg_pid=$!

# Wait for the daemon to come online.
while true; do
    if psql -c "select true" postgres >/dev/null; then
        break
    fi
    sleep 0.1
done

mkdir -p $(dirname "$out_file")

echo "-- createdb" > "$out_file"
$PG_BIN_DIR/createdb || exit 5

echo "-- psql -f '$psql_script_file' -v 'extension_name=$extension_name' -v 'test_stage=pre-dump'" >> "$out_file"
$PG_BIN_DIR/psql \
    -f "$psql_script_file" \
    -v "extension_name=$extension_name" \
    -v "test_stage=pre-dump" \
    >> "$out_file" 2>&1 || exit 5

echo "-- pg_dumpall --globals-only"
$PG_BIN_DIR/pg_dumpall --globals-only > "$dump_file" || exit 5

echo "-- pg_dump --format=custom --file <dump_file>" >> "$out_file"
$PG_BIN_DIR/pg_dump --format=custom --file "$dump_file" >> "$out_file" || exit 5


echo "-- dropdb"
$PG_BIN_DIR/dropdb "$PGDATABASE" || exit 5

echo "-- pg_restore --create --dbname postgres <dump_file>"
$PG_BIN_DIR/pg_restore --create --dbname postgres "$dump_file" || exit 5

echo "-- psql -f '$psql_script_file' -v 'extension_name=$extension_name' -v 'test_stage=post-restore'" >> "$out_file"
$PG_BIN_DIR/psql \
    -f "$psql_script_file" \
    -v "extension_name=$extension_name" \
    -v "test_stage=post-restore" \
    >> "$out_file" 2>&1 || exit 5

if ! diff "$expected_out_file" "$out_file" >/dev/null; then
    echo "Expected output was not the same as the actual output:"
    diff "$expected_out_file" "$out_file"
    exit 6
fi

# vim: set expandtab shiftwidth=4 tabstop=4:
