
var path = require('path');
var pool = require('./_pool');

// sql statement
var sql = [
  'SELECT * FROM place',
  'JOIN name_map ON place.wofid = name_map.wofid',
  'JOIN place_name ON name_map.rowid = place_name.rowid',
  'WHERE place.wofid IN ($ids)'
].join(' ');

module.exports = function( req, res ){

  // open db connection
  var db;
  try { db = pool( path.resolve( __dirname, '../fts.sqlite3' ) ); }
  catch ( e ){ return res.status( 500 ).send(); }

  var args = {
    $ids: ( req.query.ids || '' ).split(',').map( function( id ){
      return parseInt( id.trim(), 10 );
    }).filter( function( id ){
      return !isNaN( id );
    })
  };

  console.error( sql, args );

  db.all( sql.replace( '$ids', args.$ids.join(',') ), function( err, rows ){

    if( err ){
      console.error( err );
      return res.status(500).json({ error: err });
    }

    var memo = {};
    rows.forEach( function( row ){

      var name = row.name;
      var lang = row.lang;
      delete row.name;
      delete row.lang;

      if( !memo.hasOwnProperty( row.wofid ) ){
        memo[row.wofid] = row;
        memo[row.wofid].names = {};
      }

      memo[row.wofid].names[ lang ] = name;
    });

    res.status(200).json( memo );
  });

};
