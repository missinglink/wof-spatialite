#!/bin/bash
# set -e;
export LC_ALL=en_US.UTF-8;

# location of this file in filesystem
DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd );

# location of sqlite database file
DB=${DB:-"$DIR/fts.sqlite3"};

# note: requires libspatialite to be compiled with librttopo
export LD_LIBRARY_PATH=/lib:/usr/lib:/usr/local/lib;

## vocab - search the terms list
function vocab(){

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

  echo '';
  printf 'term: \e[1;34m%s\e[m\n' "${terms[@]}";
  echo '';

SQL=$'.timer ON\n\n';

  # build query
  length=${#terms[@]}
  for i in "${!terms[@]}"
  do
    if [ $i -eq $((length-1)) ]; then
      SQL=$"$SQL SELECT * FROM vocab WHERE term='${terms[i]}'";
    else
      SQL=$"$SQL SELECT * FROM vocab WHERE term='${terms[i]}' UNION";
    fi
  done

  SQL=$"$SQL ORDER BY LENGTH(1) DESC;";

  echo "$SQL";

  sqlite3 -header -column "$DB" <<< "$SQL";
  echo;
}

vocab "$@";
