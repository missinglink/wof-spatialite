
module.exports = function( db, tokens, cb ){

  var sql = [
    'SELECT * FROM place',
    // 'SELECT place.*, place_name.lang, place_name.name FROM place',
    // 'JOIN name_map ON place_name.rowid = name_map.rowid',
    // 'JOIN place_name ON place.wofid = name_map.wofid AND place_name.lang = \'default\'',
    'WHERE place.wofid IN ('
  ];

  // build query
  for( var i = tokens.length-1; i>=0; i-- ){
    if( i === 0 ){
      sql.push( "SELECT wofid FROM place_name WHERE place_name = 'name: \"" + tokens[i] + "\"'" );
    } else {
      sql.push( "SELECT graph.child FROM place_name" );
      sql.push( "JOIN name_map ON place_name.rowid = name_map.rowid" );
      sql.push( "JOIN graph ON name_map.wofid = graph.parent" );
      sql.push( "WHERE place_name = 'name: \"" + tokens[i] + "\"'" );
      sql.push( "INTERSECT" );
    }
  }

  sql.push( ") GROUP BY place.wofid ORDER BY area DESC;" );
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
