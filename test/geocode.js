
var fs = require('fs'),
    path = require('path'),
    request = require('superagent');

console.error( 'open', process.argv[2] );
var data = require( path.resolve( __dirname, process.argv[2] ) );
var tests = data.tests || [];

var TIMEOUT = 200;
var results = {};

function next(){
  var test = tests.shift();
  if( !test ){ return; }

  console.error( test.in.text );
  test.in.api_key = 'search-S0p1Seg';
  test.in.size = '40';

  request
    .get('https://search.mapzen.com/v1/search')
    .query( test.in )
    .end( function( err, res ){
      console.error( tests.length );
      if( err ){ console.error( err ); }

      results[ test.id ] = {
        test: test,
        err: err,
        body: res.body
      };

      // console.log( err, res.body.features[0].properties );
      // Do something
    });

  setTimeout( next, TIMEOUT );
}

function done(){
  console.log( JSON.stringify( results ) );
}

process.on('exit', done );
next();
