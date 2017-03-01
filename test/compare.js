
var fs = require('fs'),
    path = require('path'),
    util = require('util'),
    _ = require('lodash');

console.error( 'tests', process.argv[2] );
var suite = require( path.resolve( __dirname, process.argv[2] ) );

console.error( 'geocoded', process.argv[3] );
var geocoded = require( path.resolve( __dirname, process.argv[3] ) );

console.error( 'parsed', process.argv[4] );
var parsed = require( path.resolve( __dirname, process.argv[4] ) );

var error = [];
var pass = [];
var fail = [];

suite.tests.forEach( function( test ){
  // console.log( test.in.text );

  var geocode = geocoded[ test.id ];
  var parse = parsed[ test.id ];

  if( !geocode || !geocode.body ){
    return error.push({
      test: test,
      geocode: geocode,
      parse: parse,
      suite_error: 'geocode not found!'
    });
  }
  if( !parse ){
    if( test.in.text == 'Yuba City' ){
      console.error( JSON.stringify( parse, null, 2 ) );
    }
    return error.push({
      test: test,
      geocode: geocode,
      parse: parse,
      suite_error: 'parse not found!'
    });
  }
  if( !geocode.body.features || !geocode.body.features.length ){
    return error.push({
      test: test,
      geocode: geocode,
      parse: parse,
      suite_error: 'no features found in geocode results!'
    });
  }


  // get geocode ids
  // var geocodeWofIds = geocode.body.features.map( function( feat ){
  //
  //   if( feat.properties.source === 'whosonfirst' ){
  //     return parseInt( feat.properties.gid.split(':')[2], 10 );
  //   }
  //
  //   var layer = feat.properties.layer;
  //
  //   if( !feat.properties.hasOwnProperty( layer + '_gid' ) ){
  //     console.error( 'geonames record has no corresponding wof id' );
  //     return;
  //   }
  //
  //   return parseInt( feat.properties[ layer + '_gid' ].split(':')[2], 10 );
  // }).filter( function( val ){
  //   return !!val;
  // });

  // get geocode ids
  var geocodeWofIds = [];
  geocode.body.features.forEach( function( feat ){

    if( feat.properties.source === 'whosonfirst' ){
      geocodeWofIds.push( parseInt( feat.properties.gid.split(':')[2], 10 ) );
      return;
    }

    // geonames doesn't have 1:1 mapping of admin keys
    for( var attr in feat.properties ){
      if( attr.match( /_gid$/ ) ){
        geocodeWofIds.push( parseInt( feat.properties[attr].split(':')[2], 10 ) );
      }
    }
  });

  // get parse ids
  var parseWofIds = parse.body.map( function( res ){
    return parseInt( res.wofid, 10 );
  });

  // intersect sets
  var intersect = _.intersection( geocodeWofIds, parseWofIds );

  // console.error( 'geocode', geocodeWofIds );
  // console.error( 'parse', parseWofIds );

  if( intersect.length > 0 ){
    pass.push( test );
  } else {
    fail.push({
      test: test,
      geocode: geocode,
      parse: parse,
      geocodeWofIds: geocodeWofIds,
      parseWofIds: parseWofIds,
      intersect: intersect
    });
  }
});

console.error('----------------------');
console.error( 'total\t', suite.tests.length );
console.error( 'pass\t', pass.length );
console.error( 'fail\t', fail.length );
console.error( 'error\t', error.length );
console.error('----------------------');

// error.forEach( function( err ){
//   console.log( err.suite_error, err.test.in.text );
//   // console.log( err );
// });

// fail.forEach( function( f ){
//
//   // console.log( f.test );
//   // console.log( f.geocode );
//   console.log( '--------------------------------------------------' );
//   console.log( util.format( '[%s] %s ', f.test.id, f.test.in.text ) );
//   f.geocode.body.features.forEach( function( feat ){
//     console.log( util.format( '[geocode] ', feat.properties.name ) );
//   });
//   // f.parse.body.forEach( function( p ){
//   //   console.log( util.format( '[parse] ', p ) );
//   // });
//   delete f.parse.test;
//   console.log( f.parse );
// });
