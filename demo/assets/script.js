
// Create a basic Leaflet map
var map = L.map('map', { zoomControl:false });
new L.Control.Zoom({ position: 'bottomleft' }).addTo(map);

// click handler
// map.on('click', function(e){ update( e.latlng ); });
// map.on('dragend', function(e){ update(); });
map.on('moveend', function(e){ update(); });
map.on('resize', function(e){ update(); });
// map.on('load', function(e){ update(); });

L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
  attribution: '&copy; <a href="http://openstreetmap.org/copyright">OpenStreetMap contributors</a>'
}).addTo(map);

// init location
var hash = new L.Hash(map);
if( 'string' !== typeof location.hash || location.hash.split('/').length !== 3 ){

  // on error, set NYC
  map.on('locationerror', function(){ map.setView([40.7259, -73.9805], 12); });

  // try to locate using browser geolocation API
  map.locate({ setView: true, maxZoom: 16 });
}

// Add geocoding plugin
var params = {};
var options = {
  focus: false,
  expanded: true,
  params: params,
  url: 'https://api.geocode.earth/v1',
  attribution: 'Geocoding by <a href="https://geocode.earth/">geocode.earth</a>'
};
var geocoder = L.control.geocoder('ge-6361345754ea1287', options).addTo(map);

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
  "postalcode",
  "borough",
  "macrohood",
  "neighbourhood",
  "microhood",
  "campus"
];

function update( latlng ){

  // use map center when latlng not supplied
  if( !latlng ){
    latlng = map.getCenter();
  }

  // unwrap longitude
  while( latlng.lng > +180 ){ latlng.lng -= 360; }
  while( latlng.lng < -180 ){ latlng.lng += 360; }

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
        html.push("<a target=\"wof\" href=\"https://spelunker.whosonfirst.org/id/" + place.id + "\">" + place.id + "</a>");
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
