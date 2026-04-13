provider "aws" {
  region = "eu-north-1"
}

# -------------------------
# VPC and Networking
# -------------------------

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "main-vpc-kalyanifinal"
  }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "main-gateway-kalyanifinal"
  }
}

resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true
  tags = {
    Name = "public-subnet-1-kalyanifinal"
  }
}

resource "aws_subnet" "public_2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true
  tags = {
    Name = "public-subnet-2-kalyanifinal"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "public-route-table-kalyanifinal"
  }
}

resource "aws_route_table_association" "public_assoc_1" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_assoc_2" {
  subnet_id      = aws_subnet.public_2.id
  route_table_id = aws_route_table.public.id
}

# -------------------------
# ECS Networking (Security Group)
# -------------------------

resource "aws_security_group" "ecs_sg" {
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ecs-sg-hemanthfinal"
  }
}

# -------------------------
# ECS Cluster
# -------------------------

resource "aws_ecs_cluster" "main" {
  name = "hemanth-fargate-cluster"
}

# -------------------------
# IAM Role for ECS Tasks
# -------------------------

resource "aws_iam_role" "ecs_task_exec_role" {
  name = "ecsTaskExecutionRole-kalyani"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      },
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_exec_attach" {
  role       = aws_iam_role.ecs_task_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# -------------------------
# ECR Repositories
# -------------------------

resource "aws_ecr_repository" "appointment_service" {
  name = "appointment-phk"
}

resource "aws_ecr_repository" "patient_service" {
  name = "patient-phk"
}

# -------------------------
# Build and Push Docker Images
# -------------------------

resource "null_resource" "docker_build_and_push_appointment_service" {
  provisioner "local-exec" {
    command = <<EOT
      aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin ${aws_ecr_repository.appointment_service.repository_url}
      docker build -t appointment-phk ./appointment-phk
      docker tag appointment-phk:latest ${aws_ecr_repository.appointment_service.repository_url}:latest
      docker push ${aws_ecr_repository.appointment_service.repository_url}:latest
    EOT
  }
}

resource "null_resource" "docker_build_and_push_patient_service" {
  provisioner "local-exec" {
    command = <<EOT
      aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin ${aws_ecr_repository.patient_service.repository_url}
      docker build -t patient-phk ./patient-phk
      docker tag patient-phk:latest ${aws_ecr_repository.patient_service.repository_url}:latest
      docker push ${aws_ecr_repository.patient_service.repository_url}:latest
    EOT
  }
}

# -------------------------
# ECS Task Definitions
# -------------------------

resource "aws_ecs_task_definition" "appointment_service_task" {
  family                   = "appointment-kalyani-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_task_exec_role.arn

  container_definitions = jsonencode([{
    name  = "appointment-kalyani-container",
    image = "${aws_ecr_repository.appointment_service.repository_url}:latest",
    portMappings = [{
      containerPort = 3001,
      protocol      = "tcp"
    }]
  }])

  depends_on = [null_resource.docker_build_and_push_appointment_service]
}

resource "aws_ecs_task_definition" "patient_service_task" {
  family                   = "patient-kalyani-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_task_exec_role.arn

  container_definitions = jsonencode([{
    name  = "patient-kalyani-container",
    image = "${aws_ecr_repository.patient_service.repository_url}:latest",
    portMappings = [{
      containerPort = 3002,
      protocol      = "tcp"
    }]
  }])

  depends_on = [null_resource.docker_build_and_push_patient_service]
}

# -------------------------
# Load Balancer
# -------------------------

resource "aws_lb" "main" {
  name               = "ecs-app-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.ecs_sg.id]
  subnets            = [aws_subnet.public_1.id, aws_subnet.public_2.id]
}

resource "aws_lb_target_group" "appointment_service_tg" {
  name        = "kalyani-appointment-tg"
  port        = 3001
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.main.id
}

resource "aws_lb_target_group" "patient_service_tg" {
  name        = "phk-patient-tg"
  port        = 3002
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.main.id
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.appointment_service_tg.arn
  }
}

resource "aws_lb_listener_rule" "patient_service_rule" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.patient_service_tg.arn
  }

  condition {
    path_pattern {
      values = ["/patient/*"]
    }
  }
}

# -------------------------
# ECS Services
# -------------------------

resource "aws_ecs_service" "appointment_service" {
  name            = "appointment-kalyani"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.appointment_service_task.arn
  desired_count   = 2
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = [aws_subnet.public_1.id, aws_subnet.public_2.id]
    security_groups = [aws_security_group.ecs_sg.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.appointment_service_tg.arn
    container_name   = "appointment-phk-container"
    container_port   = 3001
  }
}

resource "aws_ecs_service" "patient_service" {
  name            = "patient-kalyani"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.patient_service_task.arn
  desired_count   = 2
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = [aws_subnet.public_1.id, aws_subnet.public_2.id]
    security_groups = [aws_security_group.ecs_sg.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.patient_service_tg.arn
    container_name   = "patient-kalyani-container"
    container_port   = 3002
  }
}
