using System;
using System.Data.Common;
using System.Linq;
using System.Net;
using System.Net.Sockets;
using System.Threading;
using Newtonsoft.Json;
using Npgsql;
using StackExchange.Redis;

namespace Worker
{
    public class Program
    {
        public static int Main(string[] args)
        {
            try
            {
                var pgsql = OpenDbConnection(
                    $"Server={Environment.GetEnvironmentVariable("DATABASE_HOST") ?? "db"};" +
                    $"Username={Environment.GetEnvironmentVariable("DATABASE_USER") ?? "postgres"};" +
                    $"Password={Environment.GetEnvironmentVariable("DATABASE_PASSWORD") ?? "postgres"};"
                );
                var redisConn = OpenRedisConnection(
                    Environment.GetEnvironmentVariable("REDIS_HOST") ?? "redis"
                );
                var redis = redisConn.GetDatabase();

                var keepAliveCommand = pgsql.CreateCommand();
                keepAliveCommand.CommandText = "SELECT 1";

                // Added voter_name and voted_at to the definition
                var definition = new { vote = "", voter_id = "", voter_name = "", voted_at = "" };

                while (true)
                {
                    Thread.Sleep(100);

                    if (redisConn == null || !redisConn.IsConnected) {
                        Console.WriteLine("Reconnecting Redis");
                        redisConn = OpenRedisConnection("redis");
                        redis = redisConn.GetDatabase();
                    }

                    string json = redis.ListLeftPopAsync("votes").Result;
                    if (json != null)
                    {
                        var vote = JsonConvert.DeserializeAnonymousType(json, definition);
                        Console.WriteLine($"Processing vote for '{vote.vote}' by '{vote.voter_name}'");

                        if (!pgsql.State.Equals(System.Data.ConnectionState.Open))
                        {
                            Console.WriteLine("Reconnecting DB");
                            pgsql = OpenDbConnection(
                                $"Server={Environment.GetEnvironmentVariable("DATABASE_HOST") ?? "db"};" +
                                $"Username={Environment.GetEnvironmentVariable("DATABASE_USER") ?? "postgres"};" +
                                $"Password={Environment.GetEnvironmentVariable("DATABASE_PASSWORD") ?? "postgres"};"
                            );
                        }
                        else
                        {
                            UpdateVote(pgsql, vote.voter_id, vote.voter_name, vote.vote, vote.voted_at);
                        }
                    }
                    else
                    {
                        keepAliveCommand.ExecuteNonQuery();
                    }
                }
            }
            catch (Exception ex)
            {
                Console.Error.WriteLine(ex.ToString());
                return 1;
            }
        }

        private static NpgsqlConnection OpenDbConnection(string connectionString)
        {
            NpgsqlConnection connection;

            while (true)
            {
                try
                {
                    connection = new NpgsqlConnection(connectionString);
                    connection.Open();
                    break;
                }
                catch (SocketException)
                {
                    Console.Error.WriteLine("Waiting for db");
                    Thread.Sleep(1000);
                }
                catch (DbException)
                {
                    Console.Error.WriteLine("Waiting for db");
                    Thread.Sleep(1000);
                }
            }

            Console.Error.WriteLine("Connected to db");

            var command = connection.CreateCommand();
            command.CommandText = @"CREATE TABLE IF NOT EXISTS votes (
                            id          VARCHAR(255) NOT NULL UNIQUE,
                            voter_name  VARCHAR(255) NOT NULL DEFAULT '',
                            vote        VARCHAR(255) NOT NULL,
                            voted_at    TIMESTAMPTZ  NOT NULL DEFAULT now()
                        )";
command.ExecuteNonQuery();

command.CommandText = @"ALTER TABLE votes ADD COLUMN IF NOT EXISTS voter_name VARCHAR(255) NOT NULL DEFAULT ''";
command.ExecuteNonQuery();

command.CommandText = @"ALTER TABLE votes ADD COLUMN IF NOT EXISTS voted_at TIMESTAMPTZ NOT NULL DEFAULT now()";
command.ExecuteNonQuery();

            return connection;
        }

        private static ConnectionMultiplexer OpenRedisConnection(string hostname)
        {
            var ipAddress = GetIp(hostname);
            Console.WriteLine($"Found redis at {ipAddress}");

            while (true)
            {
                try
                {
                    Console.Error.WriteLine("Connecting to redis");
                    return ConnectionMultiplexer.Connect(ipAddress);
                }
                catch (RedisConnectionException)
                {
                    Console.Error.WriteLine("Waiting for redis");
                    Thread.Sleep(1000);
                }
            }
        }

        private static string GetIp(string hostname)
            => Dns.GetHostEntryAsync(hostname)
                .Result
                .AddressList
                .First(a => a.AddressFamily == AddressFamily.InterNetwork)
                .ToString();

        private static void UpdateVote(
            NpgsqlConnection connection,
            string voterId,
            string voterName,
            string vote,
            string votedAt)
        {
            var command = connection.CreateCommand();
            try
            {
                command.CommandText = @"INSERT INTO votes (id, voter_name, vote, voted_at)
                                        VALUES (@id, @voter_name, @vote, @voted_at)";
                command.Parameters.AddWithValue("@id",         voterId);
                command.Parameters.AddWithValue("@voter_name", voterName);
                command.Parameters.AddWithValue("@vote",       vote);
                command.Parameters.AddWithValue("@voted_at",
                    string.IsNullOrEmpty(votedAt)
                        ? (object)DateTime.UtcNow
                        : DateTime.Parse(votedAt).ToUniversalTime());
                command.ExecuteNonQuery();
            }
            catch (DbException)
            {
                command.CommandText = @"UPDATE votes
                                        SET vote       = @vote,
                                            voter_name = @voter_name,
                                            voted_at   = @voted_at
                                        WHERE id = @id";
                command.ExecuteNonQuery();
            }
            finally
            {
                command.Dispose();
            }
        }
    }
}