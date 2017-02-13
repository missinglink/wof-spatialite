
var path = require('path');
var pool = require('./_pool');
var search = require('../api/search');
var tokenize = require('./_tokenize');

module.exports = function( req, res ){

  // open db connection
  var db;
  try { db = pool( path.resolve( __dirname, '../fts.sqlite3' ) ); }
  catch ( e ){ return res.status( 500 ).send(); }

  search( db, tokenize( req.query.token ), function( err, rows ){

    if( err ){
      console.error( err );
      return res.status(500).json({ error: err });
    }

    res.status(200).json( rows );
  });
};
