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
	"sync"

	_ "github.com/shaxbee/go-spatialite" // required database driver
)

// total requests to queue at any time
var queue = make(chan *query, 1024)

type connection struct {
	DB   *sql.DB
	Stmt *sql.Stmt
}

type result struct {
	ID        uint64 `json:"id"`
	Name      string `json:"name"`
	Placetype string `json:"placetype"`
}

type query struct {
	Send func(res []*result)
	Lon  sql.NamedArg
	Lat  sql.NamedArg
}

// newConnection - constructor
func newConnection() *connection {

	var dbFile = "wof.sqlite"
	if len(os.Args) > 1 {
		dbFile = os.Args[1]
	}

	var uri = fmt.Sprintf("file:%s?mode=ro&cache=shared&nolock=1&immutable=1", dbFile)
	_db, err := sql.Open("spatialite", uri)
	if err != nil {
		panic(err)
	}

	_stmt, err := _db.Prepare(strings.TrimSpace(`
SELECT id, name, layer FROM place
WHERE id IN (
  SELECT wofid
  FROM tiles
  WHERE rowid IN (
    SELECT pkid FROM idx_tiles_geom
    WHERE pkid MATCH RTreeIntersects(:lon, :lat, :lon, :lat)
  )
  AND WITHIN( ST_Point(:lon, :lat), tiles.geom )
)`))
	if err != nil {
		panic(err)
	}

	return &connection{
		DB:   _db,
		Stmt: _stmt,
	}
}

// parseFloat - convert form
func parseFloat(m map[string][]string, k string) float64 {
	var num float64
	if v, ok := m[k]; ok {
		i, err := strconv.ParseFloat(v[0], 64)
		if nil == err {
			num = i
		}
	}
	return num
}

func pip(w http.ResponseWriter, r *http.Request) {

	r.ParseForm()
	var lon = sql.Named("lon", parseFloat(r.Form, "lon"))
	var lat = sql.Named("lat", parseFloat(r.Form, "lat"))

	var wg = &sync.WaitGroup{}
	wg.Add(1)

	var cb = func(res []*result) {
		w.Header().Set("Content-Type", "application/json; charset=UTF-8")
		w.Header().Set("Cache-Control", "public, max-age=120")
		json, err := json.Marshal(res)
		if err != nil {
			panic(err)
		}
		w.Write(json)
		wg.Done()
	}

	queue <- &query{Send: cb, Lon: lon, Lat: lat}
	wg.Wait()
}

func lookup(c *connection, q *query) {

	// start := time.Now()
	rows, err := c.Stmt.Query(q.Lon, q.Lat)
	if err != nil {
		log.Println(err)
	}
	// elapsed := time.Since(start)
	// fmt.Printf("took %s\n", elapsed)

	var res = make([]*result, 0, 20)
	for rows.Next() {
		var r = &result{}
		rows.Scan(&r.ID, &r.Name, &r.Placetype)
		res = append(res, r)
	}
	rows.Close()

	q.Send(res)
}

func worker() {
	var c = newConnection()
	for q := range queue {
		lookup(c, q)
	}
	c.Stmt.Close()
	c.DB.Close()
}

func main() {

	// spawn worker(s)
	for i := 0; i < 1; i++ {
		go worker()
	}

	fs := http.FileServer(http.Dir("demo"))
	http.Handle("/demo/", http.StripPrefix("/demo/", fs))
	http.HandleFunc("/pip", pip)
	fmt.Println("listening on port 8080")
	err := http.ListenAndServe(":8080", nil)
	if err != nil {
		log.Fatal("ListenAndServe: ", err)
	}
}
