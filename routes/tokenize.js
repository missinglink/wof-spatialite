
var path = require('path');
var pool = require('./_pool');
var tokenize = require('../api/tokenize');

module.exports = function( req, res ){

  // open db connection
  var db;
  try { db = pool( path.resolve( __dirname, '../fts.sqlite3' ) ); }
  catch ( e ){ return res.status( 500 ).send(); }

  tokenize( db, req.query.text, function( err, tokens ){

    if( err ){
      console.error( err );
      return res.status(500).json({ error: err });
    }

    res.status(200).json( tokens );
  });
};
