
module.exports = function( db, tokens, cb ){

  var sql = [];

  // build query
  for( var i=0; i<tokens.length; i++ ){
    if( i === tokens.length-1 ){
      sql.push( "SELECT * FROM vocab WHERE term = '" + tokens[i] + "'" );
    } else {
      sql.push( "SELECT * FROM vocab WHERE term = '" + tokens[i] + "'" );
      sql.push( "UNION" );
    }
  }

  // console.log( tokens );
  // console.error( sql, args );

  db.all( sql.join('\n'), function( err, rows ){

    if( err ){
      console.error( err );
      return cb( err );
    }

    return cb( null, rows );
  });
};
