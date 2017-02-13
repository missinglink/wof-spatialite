
var path = require('path');
var pool = require('./_pool');
var vocab = require('../api/vocab');
var tokenize = require('./_tokenize');

module.exports = function( req, res ){

  // open db connection
  var db;
  try { db = pool( path.resolve( __dirname, '../fts.sqlite3' ) ); }
  catch ( e ){ return res.status( 500 ).send(); }

  var tokens = tokenize( req.query.token );

  vocab( db, tokens, function( err, rows ){

    if( err ){
      console.error( err );
      return res.status(500).json({ error: err });
    }

    res.status(200).json( rows );
  });

};
