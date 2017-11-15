
// Create a basic Leaflet map
var map = L.map('map', { zoomControl:false });
new L.Control.Zoom({ position: 'bottomleft' }).addTo(map);

// click handler
// map.on('click', function(e){ update( e.latlng ); });
map.on('dragend', function(e){ update(); });
map.on('moveend', function(e){ update(); });
map.on('resize', function(e){ update(); });
map.on('load', function(e){ update(); });

L.tileLayer('http://{s}.tile.osm.org/{z}/{x}/{y}.png', {
  attribution: '&copy; <a href="http://openstreetmap.org/copyright">OpenStreetMap contributors</a>'
}).addTo(map);

// init
map.setView([40.7259, -73.9805], 12);

// Add geocoding plugin
var params = { };
var options = { focus: false, expanded: true, params: params };
var geocoder = L.control.geocoder('search-S0p1Seg', options).addTo(map);
map.locate({setView: true, maxZoom: 16});

var wof_order = [
  "planet",
  "ocean",
  "continent",
  "marinearea",
  "empire",
  "timezone",
  "country",
  "dependency",
  "disputed",
  "macroregion",
  "region",
  "macrocounty",
  "county",
  "localadmin",
  "locality",
  "borough",
  "macrohood",
  "neighbourhood",
  "microhood"
];

function update( latlng ){
  // use map center when latlng not supplied
  if( !latlng ){ latlng = map.getCenter(); }

  $.ajax({
    dataType: "json",
    url: "/pip?lat="+latlng.lat+"&lon="+latlng.lng,
    success: function(data) {

      // console.error( JSON.stringify( data, null, 2 ) );
      $("#infobox").empty();
      if( !data ){ return; }

      var html = [];
      html.push("<table>");

      data.sort( function( a, b ){
        return wof_order.indexOf( a.placetype ) - wof_order.indexOf( b.placetype );
      });

      data.forEach( function( place ){
        html.push("<tr>");
        html.push("<th>" + place.placetype + "</th>");
        html.push("<td>" + place.name + "</td>");
        html.push("<td class=\"wof\">");
        html.push("<a target=\"wof\" href=\"https://whosonfirst.mapzen.com/spelunker/id/" + place.id + "\">" + place.id + "</a>");
        html.push("</td>");
        html.push("</tr>");
      });

      html.push("</table>");

      $("#infobox").html($(html.join("\n")));
    }
  }).error(function( err ) {
    console.error( err );
  });
}
