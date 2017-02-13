
var fs = require('fs'),
    sqlite3 = require('sqlite3'),
    conn = {};

sqlite3.verbose();

var pool = function( path ){

  if( !fs.existsSync( path ) ){
    console.error( 'invalid path:', path );
    throw new Error( 'invalid path' );
  }

  // find conn
  var db = conn[ path ];

  // init db
  if( !db ){
    db = new sqlite3.Database( path, sqlite3.OPEN_READONLY );

    // configure
    db.loadExtension('mod_spatialite');
    db.run('PRAGMA main.foreign_keys=OFF;'); // we don't enforce foreign key constraints
    db.run('PRAGMA main.page_size=4096;'); // (default: 1024)
    db.run('PRAGMA main.cache_size=-2000;'); // (default: -2000, 2GB)
    db.run('PRAGMA main.synchronous=OFF;');
    db.run('PRAGMA main.journal_mode=OFF;');
    db.run('PRAGMA main.temp_store=MEMORY;');

    conn[ path ] = db;
  }

  return db;
};

// close all
pool.close = function(){ for( var path in conn ){ conn[ path ].close(); } };

// export
module.exports = pool;
