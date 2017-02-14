
var vocab = require('./vocab');
var tokenize = require('../routes/_tokenize');
var group = require('../routes/_group');

// remove tokens which shouldn't be on their own
var removeTokens = [
  'west', 'east', 'north', 'south'
];

module.exports = function( db, text, cb ){

  // handle non-string value
  text = text || '';

  // remove address components
  text = text.replace(/^(.* (street|road|avenue|rd|st|ave) )/, '');

  var tokens = tokenize( text.split( /\s/g ) );
  var permutations = group( tokens );

  var vocabTokens = permutations.map( function( group ){
    return group.join(' ');
  });

  // remove tokens containing numbers
  // @todo: is this correct?
  vocabTokens = vocabTokens.filter( function( token ){
    return isNaN( parseInt( token, 10 ) );
  });

  // remove common address tokens
  vocabTokens = vocabTokens.filter( function( token ){
    return removeTokens.indexOf( token ) === -1;
  });

  vocab( db, vocabTokens, function( err, rows ){

    if( err ){
      console.error( err );
      return cb( err );
    }

    // @todo: improve matching algorithm
    var matches = {};

    // sort the largest matches first
    rows.sort( function( a, b ){
      return b.term.length - a.term.length;
    });

    rows.forEach( function( row ){
      var words = row.term.split(' ');
      words.forEach( function( word ){
        if( !matches.hasOwnProperty( word ) ){
          matches[ word ] = [];
        }
        matches[ word ].push( row );
      });
    });

    // var possible = [];

    var window = [];
    tokens.forEach( function( token ){
      if( matches.hasOwnProperty( token ) ){
        window.push( matches[token][0].term );
      }
    });

    return cb( null, window.filter( function( item, pos, self ){
      return self.indexOf(item) == pos;
    }));
  });
};
