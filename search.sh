#!/bin/bash
# set -e;
export LC_ALL=en_US.UTF-8;

# location of this file in filesystem
DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd );

# location of sqlite database file
DB=${DB:-"$DIR/fts.sqlite3"};

# note: requires libspatialite to be compiled with librttopo
export LD_LIBRARY_PATH=/lib:/usr/lib:/usr/local/lib;

## search - search the database
function search(){

  terms=$1;
  length=${#terms[@]};

  sqlite3 "$DB" <<SQL

SELECT *, COUNT(wofid) AS cnt FROM place_name
WHERE key = 'default'
AND (
    place_name MATCH "${terms[0]}*"
 OR place_name MATCH "${terms[1]}*"
 OR place_name MATCH "${terms[2]}*"
)
GROUP BY wofid
ORDER BY cnt DESC
LIMIT 10;

SQL
}

# TERMS=('wellington' 'new' 'zealand');
TERMS=( "$@" );

echo $TERMS;
search $TERMS;
