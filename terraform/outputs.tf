output "alb_dns_name" {
  description = "DNS name of the load balancer"
  value       = aws_lb.main.dns_name
}

output "vote_url" {
  description = "URL to access the vote app"
  value       = "http://${aws_lb.main.dns_name}"
}

output "result_url" {
  description = "URL to access the result app"
  value       = "http://${aws_lb.main.dns_name}:8080"
}

output "rds_endpoint" {
  description = "RDS Postgres endpoint"
  value       = aws_db_instance.postgres.address
}

output "redis_endpoint" {
  description = "ElastiCache Redis endpoint"
  value       = aws_elasticache_cluster.redis.cache_nodes[0].address
}

output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = aws_ecs_cluster.main.name
}
