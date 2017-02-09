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

  terms=("$@");
  length=${#terms[@]};

  # clean input tokens
  for i in "${!terms[@]}"
  do
     terms[i]=${terms[i]//.};
     terms[i]=${terms[i]//,};
     terms[i]=${terms[i]//\'};
     terms[i]=${terms[i]//\"};
  done

  printf 'term: %s\n' "${terms[@]}"

read -r -d '' SQL <<SNIPPET
  SELECT place.*, place_name.lang, place_name.name FROM place
  JOIN place_name ON place.wofid = place_name.wofid AND place_name.lang = 'default'
  WHERE place.wofid IN (
SNIPPET

  # build query
  for (( i=${#terms[@]}-1 ; i>=0 ; i-- ))
  do
    if [ $i -eq 0 ]; then
      SQL=$"$SQL SELECT wofid FROM place_name WHERE place_name MATCH \"${terms[i]}\"";
    elif [ $i -eq $((length-1)) ]; then
      SQL=$"$SQL SELECT graph.child FROM place_name";
      SQL=$"$SQL JOIN graph ON place_name.wofid = graph.parent";
      SQL=$"$SQL WHERE place_name MATCH \"${terms[i]}*\"";
      SQL=$"$SQL INTERSECT";
    else
      SQL=$"$SQL SELECT graph.child FROM place_name";
      SQL=$"$SQL JOIN graph ON place_name.wofid = graph.parent";
      SQL=$"$SQL WHERE place_name MATCH \"${terms[i]}\"";
      SQL=$"$SQL INTERSECT";
    fi
  done

  SQL=$"$SQL ) ORDER BY area DESC;";

  sqlite3 -header -column "$DB" <<< "$SQL";

#   sqlite3 "$DB" <<SQL
# .timer ON
#
# SELECT * FROM place
# JOIN place_name ON place.wofid = place_name.wofid AND place_name.lang = 'eng'
# WHERE place.wofid IN (
#   SELECT graph.child FROM place_name
#   JOIN graph ON place_name.wofid = graph.parent
#   WHERE place_name MATCH "${terms[2]}"
#   INTERSECT
#   SELECT graph.child FROM place_name
#   JOIN graph ON place_name.wofid = graph.parent
#   WHERE place_name MATCH "${terms[1]}"
#   INTERSECT
#   SELECT wofid FROM place_name WHERE place_name MATCH "${terms[0]}"
# );
# SQL
}

# TERMS=('wellington' 'new' 'zealand');
# TERMS=("$@");

# echo $TERMS;
# printf '%s\n' "${TERMS[@]}"
search "$@";
