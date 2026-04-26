// var express = require('express'),
//     async = require('async'),
//     { Pool } = require('pg'),
//     cookieParser = require('cookie-parser'),
//     app = express(),
//     server = require('http').Server(app),
//     io = require('socket.io')(server);

// var port = process.env.PORT || 4000;

// io.on('connection', function (socket) {

//   socket.emit('message', { text : 'Welcome!' });

//   socket.on('subscribe', function (data) {
//     socket.join(data.channel);
//   });
// });

// var pool = new Pool({
//   connectionString: 'postgres://postgres:postgres@db/postgres'
// });

// async.retry(
//   {times: 1000, interval: 1000},
//   function(callback) {
//     pool.connect(function(err, client, done) {
//       if (err) {
//         console.error("Waiting for db");
//       }
//       callback(err, client);
//     });
//   },
//   function(err, client) {
//     if (err) {
//       return console.error("Giving up");
//     }
//     console.log("Connected to db");
//     getVotes(client);
//   }
// );

// function getVotes(client) {
//   client.query('SELECT vote, COUNT(id) AS count FROM votes GROUP BY vote', [], function(err, result) {
//     if (err) {
//       console.error("Error performing query: " + err);
//     } else {
//       var votes = collectVotesFromResult(result);
//       io.sockets.emit("scores", JSON.stringify(votes));
//     }

//     setTimeout(function() {getVotes(client) }, 1000);
//   });
// }

// function collectVotesFromResult(result) {
//   var votes = {a: 0, b: 0};

//   result.rows.forEach(function (row) {
//     votes[row.vote] = parseInt(row.count);
//   });

//   return votes;
// }

// app.use(cookieParser());
// app.use(express.urlencoded());
// app.use(express.static(__dirname + '/views'));

// app.get('/', function (req, res) {
//   res.sendFile(path.resolve(__dirname + '/views/index.html'));
// });

// server.listen(port, function () {
//   var port = server.address().port;
//   console.log('App running on port ' + port);
// });




var express = require('express'),
    async = require('async'),
    { Pool } = require('pg'),
    cookieParser = require('cookie-parser'),
    path = require('path'),
    app = express(),
    server = require('http').Server(app),
    io = require('socket.io')(server);

var port = process.env.PORT || 4000;

io.on('connection', function (socket) {
  socket.emit('message', { text: 'Welcome!' });
  socket.on('subscribe', function (data) {
    socket.join(data.channel);
  });
});

var pool = new Pool({
  connectionString: process.env.DATABASE_URL || 'postgres://postgres:postgres@db/postgres'
});

async.retry(
  { times: 1000, interval: 1000 },
  function (callback) {
    pool.connect(function (err, client, done) {
      if (err) {
        console.error("Waiting for db");
      }
      callback(err, client);
    });
  },
  function (err, client) {
    if (err) {
      return console.error("Giving up");
    }
    console.log("Connected to db");
    getVotes(client);
  }
);

function getVotes(client) {
  // get scores for a, b, c
  client.query(
    'SELECT vote, COUNT(id) AS count FROM votes GROUP BY vote',
    [],
    function (err, result) {
      if (err) {
        console.error("Error performing query: " + err);
      } else {
        var votes = collectVotesFromResult(result);

        // get 10 most recent votes with names and timestamps
        client.query(
          'SELECT id, vote, voted_at FROM votes ORDER BY voted_at DESC LIMIT 10',
          [],
          function (err2, recentResult) {
            if (err2) {
              console.error("Error fetching recent votes: " + err2);
            } else {
              votes.recent = collectRecentVotes(recentResult);
            }
            io.sockets.emit("scores", JSON.stringify(votes));
          }
        );
      }
      setTimeout(function () { getVotes(client); }, 1000);
    }
  );
}

function collectVotesFromResult(result) {
  var votes = { a: 0, b: 0, c: 0 };

  result.rows.forEach(function (row) {
    votes[row.vote] = parseInt(row.count);
  });

  return votes;
}

function collectRecentVotes(result) {
  return result.rows.map(function (row) {
    // id column stores the voter name from app.py
    var name = row.id || 'Anonymous';
    var initials = name
      .split(' ')
      .map(function (w) { return w.charAt(0).toUpperCase(); })
      .join('')
      .slice(0, 2);

    return {
      voter_name: name,
      initials: initials,
      vote: row.vote,
      voted_at: row.voted_at
        ? new Date(row.voted_at).toLocaleString('en-GB', {
            year: 'numeric',
            month: '2-digit',
            day: '2-digit',
            hour: '2-digit',
            minute: '2-digit',
            second: '2-digit',
            hour12: false
          })
        : ''
    };
  });
}

app.use(cookieParser());
app.use(express.urlencoded({ extended: false }));
app.use(express.static(__dirname + '/views'));

app.get('/', function (req, res) {
  res.sendFile(path.resolve(__dirname + '/views/index.html'));
});

// ── Reset endpoint ──
app.post('/reset', function (req, res) {
  pool.query('DELETE FROM votes', function (err) {
    if (err) {
      console.error('Reset failed:', err);
      return res.status(500).json({ error: 'Reset failed' });
    }
    console.log('Votes reset at', new Date().toISOString());
    res.json({ status: 'ok', message: 'All votes cleared' });
  });
});

server.listen(port, function () {
  console.log('App running on port ' + port);
});