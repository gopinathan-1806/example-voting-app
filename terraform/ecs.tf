# -------------------------------------------------------
# ECS Cluster
# -------------------------------------------------------
resource "aws_ecs_cluster" "main" {
  name = "${var.project_name}-cluster"
  tags = { Name = "${var.project_name}-cluster" }
}

# -------------------------------------------------------
# CloudWatch Log Group
# -------------------------------------------------------
resource "aws_cloudwatch_log_group" "voting_app" {
  name              = "/ecs/${var.project_name}"
  retention_in_days = 7
}

# -------------------------------------------------------
# Task Definitions
# -------------------------------------------------------

# --- Vote ---
resource "aws_ecs_task_definition" "vote" {
  family                   = "${var.project_name}-vote"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([{
    name      = "vote"
    image     = var.vote_image
    essential = true

    portMappings = [{
      containerPort = 80
      protocol      = "tcp"
    }]

    environment = [
      { name = "REDIS_HOST", value = aws_elasticache_cluster.redis.cache_nodes[0].address }
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.voting_app.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "vote"
      }
    }
  }])
}

# --- Result ---
resource "aws_ecs_task_definition" "result" {
  family                   = "${var.project_name}-result"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([{
    name      = "result"
    image     = var.result_image
    essential = true

    portMappings = [{
      containerPort = 80
      protocol      = "tcp"
    }]

    environment = [
      { name = "DATABASE_URL", value = "postgres://${var.db_username}:${var.db_password}@${aws_db_instance.postgres.address}/${var.db_name}" }
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.voting_app.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "result"
      }
    }
  }])
}

# --- Worker ---
resource "aws_ecs_task_definition" "worker" {
  family                   = "${var.project_name}-worker"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([{
    name      = "worker"
    image     = var.worker_image
    essential = true

    environment = [
      { name = "REDIS_HOST",       value = aws_elasticache_cluster.redis.cache_nodes[0].address },
      { name = "DATABASE_HOST",    value = aws_db_instance.postgres.address },
      { name = "DATABASE_USER",    value = var.db_username },
      { name = "DATABASE_PASSWORD", value = var.db_password },
      { name = "DATABASE_NAME",    value = var.db_name }
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.voting_app.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "worker"
      }
    }
  }])
}

# -------------------------------------------------------
# ECS Services
# -------------------------------------------------------

# --- Vote Service ---
resource "aws_ecs_service" "vote" {
  name            = "${var.project_name}-vote"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.vote.arn
  desired_count   = 2
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.vote.arn
    container_name   = "vote"
    container_port   = 80
  }

  depends_on = [aws_lb_listener.vote]
}

# --- Result Service ---
resource "aws_ecs_service" "result" {
  name            = "${var.project_name}-result"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.result.arn
  desired_count   = 2
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.result.arn
    container_name   = "result"
    container_port   = 80
  }

  depends_on = [aws_lb_listener.result]
}

# --- Worker Service (no ALB needed, background processor) ---
resource "aws_ecs_service" "worker" {
  name            = "${var.project_name}-worker"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.worker.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }
}
