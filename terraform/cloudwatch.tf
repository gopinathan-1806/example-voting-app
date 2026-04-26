# -------------------------------------------------------
# CloudWatch Alarms for monitoring
# -------------------------------------------------------

# Alert when vote service CPU goes above 80%
resource "aws_cloudwatch_metric_alarm" "vote_cpu_high" {
  alarm_name          = "${var.project_name}-vote-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 60
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "Vote service CPU utilization is too high"

  dimensions = {
    ClusterName = aws_ecs_cluster.main.name
    ServiceName = aws_ecs_service.vote.name
  }

  tags = { Name = "${var.project_name}-vote-cpu-alarm" }
}

# Alert when result service CPU goes above 80%
resource "aws_cloudwatch_metric_alarm" "result_cpu_high" {
  alarm_name          = "${var.project_name}-result-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 60
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "Result service CPU utilization is too high"

  dimensions = {
    ClusterName = aws_ecs_cluster.main.name
    ServiceName = aws_ecs_service.result.name
  }

  tags = { Name = "${var.project_name}-result-cpu-alarm" }
}

# Alert when RDS has too many connections
resource "aws_cloudwatch_metric_alarm" "rds_connections_high" {
  alarm_name          = "${var.project_name}-rds-connections-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = 60
  statistic           = "Average"
  threshold           = 50
  alarm_description   = "RDS connection count is too high"

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.postgres.identifier
  }

  tags = { Name = "${var.project_name}-rds-connections-alarm" }
}

# Alert when ElastiCache CPU goes above 75%
resource "aws_cloudwatch_metric_alarm" "redis_cpu_high" {
  alarm_name          = "${var.project_name}-redis-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ElastiCache"
  period              = 60
  statistic           = "Average"
  threshold           = 75
  alarm_description   = "Redis CPU utilization is too high"

  dimensions = {
    CacheClusterId = aws_elasticache_cluster.redis.cluster_id
  }

  tags = { Name = "${var.project_name}-redis-cpu-alarm" }
}
