
module.exports = function( input ){

  var tokens = [];
  if( 'string' === typeof input ){
    tokens = [ input ];
  }
  else if ( Array.isArray( input ) ){
    tokens = input;
  }

  return tokens.map( function( token ){
    return token.replace(/[\.,'"]/g, '').trim();
  }).filter( function( token ){
    return token.length > 0;
  });
};
