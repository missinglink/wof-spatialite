package main

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"strings"

	_ "github.com/shaxbee/go-spatialite" // required database driver
)

type result struct {
	ID   string
	Name string
}

var db = func() *sql.DB {

	var dbFile = "wof.sqlite"
	if len(os.Args) > 1 {
		dbFile = os.Args[1]
	}

	var uri = fmt.Sprintf("file:%s?mode=ro&cache=shared&nolock=1&immutable=1", dbFile)
	_db, err := sql.Open("spatialite", uri)
	if err != nil {
		panic(err)
	}

	// enable mmap
	_db.Exec("PRAGMA mmap_size=268435456")
	_db.Exec("PRAGMA page_size=65536")
	_db.Exec("PRAGMA temp_store=MEMORY")
	_db.Exec("PRAGMA locking_mode=EXCLUSIVE")
	return _db
}()

var query = func() *sql.Stmt {
	_query, err := db.Prepare(strings.TrimSpace(`
	    SELECT id, name FROM place
	    WHERE id IN (
	      SELECT wofid
	      FROM tiles
	      WHERE id IN (
	        SELECT pkid FROM idx_tiles_geom
	        WHERE pkid MATCH RTreeIntersects(:lon, :lat, :lon, :lat)
	      )
	      AND INTERSECTS( tiles.geom, MakePoint(:lon, :lat, 4326) )
	    );
	  `))
	if err != nil {
		panic(err)
	}

	return _query
}()

func pip(w http.ResponseWriter, r *http.Request) {
	r.ParseForm()

	var lat, lon string
	if val, ok := r.Form["lat"]; ok {
		lat = val[0]
	}
	if val, ok := r.Form["lon"]; ok {
		lon = val[0]
	}

	// start := time.Now()
	rows, err := query.Query(sql.Named("lon", lon), sql.Named("lat", lat))
	defer rows.Close()
	if err != nil {
		log.Println(err)
	}
	// elapsed := time.Since(start)
	// fmt.Printf("took %s\n", elapsed)

	var res []result
	var id, name string
	for rows.Next() {
		rows.Scan(&id, &name)
		res = append(res, result{ID: id, Name: name})
	}

	jsonValue, err := json.Marshal(res)
	if err != nil {
		panic(err)
	}

	w.Header().Set("Content-Type", "application/json; charset=UTF-8")
	w.Write(jsonValue)
}

func main() {
	http.HandleFunc("/pip", pip)
	fmt.Println("listening on port 8080")
	err := http.ListenAndServe(":8080", nil)
	if err != nil {
		log.Fatal("ListenAndServe: ", err)
	}
}
