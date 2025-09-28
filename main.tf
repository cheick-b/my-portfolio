provider "aws" {
  region = "us-east-1"
}

# --- Networking ---
resource "aws_vpc" "ecs_vpc" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "ecs_subnet_1" {
  vpc_id                  = aws_vpc.ecs_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true
}

resource "aws_subnet" "ecs_subnet_2" {
  vpc_id                  = aws_vpc.ecs_vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true
}

resource "aws_internet_gateway" "ecs_igw" {
  vpc_id = aws_vpc.ecs_vpc.id
}

resource "aws_route_table" "ecs_rt" {
  vpc_id = aws_vpc.ecs_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.ecs_igw.id
  }
}

resource "aws_route_table_association" "ecs_rta_1" {
  subnet_id      = aws_subnet.ecs_subnet_1.id
  route_table_id = aws_route_table.ecs_rt.id
}

resource "aws_route_table_association" "ecs_rta_2" {
  subnet_id      = aws_subnet.ecs_subnet_2.id
  route_table_id = aws_route_table.ecs_rt.id
}

# --- Security Group ---
resource "aws_security_group" "ecs_sg" {
  vpc_id = aws_vpc.ecs_vpc.id

  ingress {
    from_port   = 5001
    to_port     = 5001
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# --- ECS Cluster ---
resource "aws_ecs_cluster" "portfolio_cluster" {
  name = "portfolio-cluster"
}

# --- IAM Role for ECS Execution ---
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "ecsTaskExecutionRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# --- ECS Task Definition ---
resource "aws_ecs_task_definition" "portfolio_task" {
  family                   = "portfolio-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([{
    name      = "portfolio"
    image     = "${var.account_id}.dkr.ecr.${var.region}.amazonaws.com/portfolio:latest"
    essential = true
    portMappings = [{
      containerPort = 5001
      hostPort      = 5001
    }]
  }])
}

# --- Load Balancer ---
resource "aws_lb" "portfolio_alb" {
  name               = "portfolio-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.ecs_sg.id]
  subnets            = [
    aws_subnet.ecs_subnet_1.id,
    aws_subnet.ecs_subnet_2.id
  ]
}

# --- Target Group ---
resource "aws_lb_target_group" "portfolio_tg" {
  name        = "portfolio-tg"
  port        = 5001
  protocol    = "HTTP"
  vpc_id      = aws_vpc.ecs_vpc.id
  target_type = "ip"

  health_check {
    path                = "/"
    port                = "5001"
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 10
    timeout             = 5
  }
}

# --- Listener ---
resource "aws_lb_listener" "portfolio_listener" {
  load_balancer_arn = aws_lb.portfolio_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.portfolio_tg.arn
  }
}

# --- ECS Service ---
resource "aws_ecs_service" "portfolio_service" {
  name            = "portfolio-service"
  cluster         = aws_ecs_cluster.portfolio_cluster.id
  task_definition = aws_ecs_task_definition.portfolio_task.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = [aws_subnet.ecs_subnet_1.id, aws_subnet.ecs_subnet_2.id]
    security_groups  = [aws_security_group.ecs_sg.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.portfolio_tg.arn
    container_name   = "portfolio"
    container_port   = 5001
  }

  depends_on = [aws_lb_listener.portfolio_listener]
}


