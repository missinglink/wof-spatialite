
var express = require('express'),
    directory = require('serve-index');

// optionally override port using env var
var PORT = process.env.PORT || 3000;
var app = express();

// routes
var routes = {
  findbyid: require( './routes/findbyid' ),
  search: require( './routes/search' ),
  tokeninfo: require( './routes/tokeninfo' ),
  group: require( './routes/group' ),
  tokenize: require( './routes/tokenize' ),
  parse: require( './routes/parse' )
};

//
app.get( '/parser/findbyid', routes.findbyid );
app.get( '/parser/search', routes.search );
app.get( '/parser/tokeninfo', routes.tokeninfo );
app.get( '/parser/group', routes.group );
app.get( '/parser/tokenize', routes.tokenize );
app.get( '/parser/parse', routes.parse );

// root page
app.use('/', express.static( __dirname ));

// start server
app.listen( PORT, function() {
  console.log( 'server listening on port', PORT );
});
