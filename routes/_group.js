
var GROUP_MIN = 1;
var GROUP_MAX = 4;

// produce all the possible token groups from adjacent input tokens (without reordering tokens)

module.exports = function( tokens ){

  var groups = [];

  for( var i=0; i<tokens.length; i++ ){
    for( var j=i+GROUP_MIN; j<i+GROUP_MIN+GROUP_MAX; j++ ){
      if( j > tokens.length ){ break; }
      groups.push( tokens.slice( i, j ) );
    }
  }

  return groups;
};

/**
example:

input: [ 'soho', 'new', 'york', 'usa' ]

output: [
  [ 'soho' ],
  [ 'soho', 'new' ],
  [ 'soho', 'new', 'york' ],
  [ 'soho', 'new', 'york', 'usa' ],
  [ 'new' ],
  [ 'new', 'york' ],
  [ 'new', 'york', 'usa' ],
  [ 'york' ],
  [ 'york', 'usa' ],
  [ 'usa' ]
]
**/
