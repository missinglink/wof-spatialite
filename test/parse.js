
var fs = require('fs'),
    qs = require('qs'),
    path = require('path'),
    request = require('superagent');

var Agent = require('agentkeepalive');

var keepaliveAgent = new Agent({
  maxSockets: 100,
  maxFreeSockets: 10,
  timeout: 60000,
  keepAliveTimeout: 30000 // free socket keepalive for 30 seconds
});

console.error( 'open', process.argv[2] );
var data = require( path.resolve( __dirname, process.argv[2] ) );
var tests = data.tests || [];

var TIMEOUT = 20;
var results = {};

function next(){
  var test = tests.shift();
  if( !test ){ return; }

  request
    .get('http://parser.wiz.co.nz/parser/tokenize')
    .agent( keepaliveAgent )
    .query({ text: test.in.text })
    .end( function( err, res ){

      if( err ){ console.error( err ); }
      var q = qs.stringify({ token: res.body || [] });
      console.error( test.in.text, q );

      request
        .get('http://parser.wiz.co.nz/parser/search')
        .agent( keepaliveAgent )
        .query( q )
        .end( function( err2, res2 ){

          if( err2 ){ console.error( err2 ); }

          if( !res2.body ){
            console.error( res2.body );
            process.exit(1);
          }

          console.error( '---' );
          console.error( 'remaining:', tests.length );
          // console.error( '---' );
          // console.error( test.in.text );
          // console.error( err, res.body );
          // console.error( err2, res2.body );

          results[ test.id ] = {
            test: test,
            err: err,
            err2: err2,
            tokens: res.body,
            body: res2.body
          };
        });
    });

  setTimeout( next, TIMEOUT );
}

function done(){
  console.log( JSON.stringify( results ) );
}

process.on('exit', done );
next();
