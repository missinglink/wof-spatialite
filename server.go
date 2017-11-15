package main

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"strconv"
	"strings"

	_ "github.com/shaxbee/go-spatialite" // required database driver
)

type result struct {
	ID        uint64 `json:"id"`
	Name      string `json:"name"`
	Placetype string `json:"placetype"`
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

	_db.SetMaxOpenConns(1)

	// enable mmap
	_db.Exec("PRAGMA mmap_size=268435456")
	_db.Exec("PRAGMA page_size=65536")
	_db.Exec("PRAGMA temp_store=MEMORY")
	_db.Exec("PRAGMA locking_mode=EXCLUSIVE")
	return _db
}()

var query = func() *sql.Stmt {

	var sql = strings.TrimSpace(`
SELECT id, name, layer FROM place
WHERE id IN (
  SELECT wofid
  FROM tiles
  WHERE rowid IN (
    SELECT pkid FROM idx_tiles_geom
    WHERE pkid MATCH RTreeIntersects(:lon, :lat, :lon, :lat)
  )
  AND WITHIN( ST_Point(:lon, :lat), tiles.geom )
)`)

	_query, err := db.Prepare(sql)
	if err != nil {
		panic(err)
	}

	return _query
}()

func parseCoord(m map[string][]string, k string) float64 {
	var coord float64
	if v, ok := m[k]; ok {
		i, err := strconv.ParseFloat(v[0], 64)
		if nil == err {
			coord = i
		}
	}
	return coord
}

func pip(w http.ResponseWriter, r *http.Request) {
	r.ParseForm()

	var lon = sql.Named("lon", parseCoord(r.Form, "lon"))
	var lat = sql.Named("lat", parseCoord(r.Form, "lat"))

	// start := time.Now()
	rows, err := query.Query(lon, lat)
	defer rows.Close()
	if err != nil {
		log.Println(err)
	}
	// elapsed := time.Since(start)
	// fmt.Printf("took %s\n", elapsed)

	var res []result
	var id uint64
	var name, layer string
	for rows.Next() {
		rows.Scan(&id, &name, &layer)
		res = append(res, result{ID: id, Name: name, Placetype: layer})
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
