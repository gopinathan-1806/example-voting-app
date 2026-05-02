var app = angular.module('catsvsdogs', []);
var socket = io.connect();

app.controller('statsCtrl', function ($scope) {

  // default values before first socket message
  $scope.aVotes    = 0;
  $scope.bVotes    = 0;
  $scope.cVotes    = 0;
  $scope.total     = 0;
  $scope.aPercent  = 0;
  $scope.bPercent  = 0;
  $scope.cPercent  = 0;
  $scope.recentVotes = [];

  socket.on('message', function () {
    document.body.style.opacity = 1;
  });

  socket.on('scores', function (json) {
    var data = JSON.parse(json);

    var a = parseInt(data.a || 0);
    var b = parseInt(data.b || 0);
    var c = parseInt(data.c || 0);
    var total = a + b + c;

    var percentages = getPercentages(a, b, c, total);

    $scope.$apply(function () {
      $scope.aVotes   = a;
      $scope.bVotes   = b;
      $scope.cVotes   = c;
      $scope.total    = total;
      $scope.aPercent = percentages.a;
      $scope.bPercent = percentages.b;
      $scope.cPercent = percentages.c;
      $scope.recentVotes = data.recent || [];
    });
  });

});

function getPercentages(a, b, c, total) {
  if (total === 0) {
    return { a: 0, b: 0, c: 0 };
  }
  var aP = Math.round(a / total * 100);
  var bP = Math.round(b / total * 100);
  var cP = 100 - aP - bP;
  return { a: aP, b: bP, c: cP };
}