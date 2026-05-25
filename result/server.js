var express = require('express'),
    async = require('async'),
    { Pool } = require('pg'),
    app = express(),
    server = require('http').Server(app),
    io = require('socket.io')(server, {
        cors: {
            origin: "*",
            methods: ["GET", "POST"]
        }
    });

var port = process.env.PORT || 80;

io.on('connection', function (socket) {
  socket.emit('message', { text : 'Welcome!' });

  socket.on('subscribe', function (data) {
    socket.join(data.channel);
  });
});

var dbPassword = process.env.DB_PASSWORD || 'v4gX9^D4cv';
var dbEndpoint = process.env.DB_ENDPOINT || 'db';
var pool = new Pool({
  connectionString: `postgres://postgres:${dbPassword}@${dbEndpoint}/postgres`,
  ssl: {
    rejectUnauthorized: false
  }
});

async.retry(
  {times: 1000, interval: 1000},
  function(callback) {
    pool.connect(function(err, client, done) {
      if (err) {
        console.error("Waiting for db");
      }
      callback(err, client);
    });
  },
  function(err, client) {
    if (err) {
      return console.error("Giving up");
    }
    console.log("Connected to db");
    getVotes(client);
  }
);

function getVotes(client) {
  client.query('SELECT vote, COUNT(id) AS count FROM votes GROUP BY vote', [], function(err, result) {
    if (err) {
      console.error("Error performing query: " + err);
    } else {
      var votes = collectVotesFromResult(result);
      io.sockets.emit("scores", JSON.stringify(votes));
    }

    setTimeout(function() {getVotes(client) }, 1000);
  });
}

function collectVotesFromResult(result) {
  var votes = {a: 0, b: 0};

  result.rows.forEach(function (row) {
    votes[row.vote] = parseInt(row.count);
  });

  return votes;
}

app.get('/api/health', function (req, res) {
  res.status(200).json({status: 'ok'});
});

server.listen(port, function () {
  var port = server.address().port;
  console.log('App running on port ' + port);
});
