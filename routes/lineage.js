
var path = require('path');
var pool = require('./_pool');

// sql statement
var sql = [
  'SELECT * FROM place',
  'WHERE place.wofid IN (',
    'SELECT parent FROM graph WHERE child = $id',
    // 'AND parent != $id',
  ')',
  'GROUP BY place.placetype',
  'ORDER BY place.area DESC',
].join(' ');

module.exports = function( req, res ){

  // open db connection
  var db;
  try { db = pool( path.resolve( __dirname, '../fts.sqlite3' ) ); }
  catch ( e ){ return res.status( 500 ).send(); }

  var args = {
    $id: ( req.params.id || '' )
  };

  console.error( sql, args );

  db.all( sql, args, function( err, rows ){

    if( err ){
      console.error( err );
      return res.status(500).json({ error: err });
    }

    res.status(200).json( rows );
  });

};
