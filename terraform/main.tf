resource "aws_logs_log_group" "AgentLogGroup" {
  name              = "/aws/ecs/AgentLogGroup"
  retention_in_days = 7
}

resource "aws_vpc" "AgentVPC" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
}

resource "aws_internet_gateway" "InternetGateway" {
  vpc_id = aws_vpc.AgentVPC.id
}

resource "aws_vpc_gateway_attachment" "AttachGateway" {
  vpc_id             = aws_vpc.AgentVPC.id
  internet_gateway_id = aws_internet_gateway.InternetGateway.id
}

resource "aws_route_table" "PublicRouteTable" {
  vpc_id = aws_vpc.AgentVPC.id

  tags = {
    Name = "Public"
  }
}

resource "aws_route" "RouteToGateway" {
  route_table_id         = aws_route_table.PublicRouteTable.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.InternetGateway.id
}

resource "aws_subnet" "AgentSubnetA" {
  vpc_id                  = aws_vpc.AgentVPC.id
  cidr_block              = "10.0.0.0/22"
  availability_zone       = element(data.aws_availability_zones.available.names, 0)
  map_public_ip_on_launch = true
}

resource "aws_subnet" "AgentSubnetB" {
  vpc_id                  = aws_vpc.AgentVPC.id
  cidr_block              = "10.0.4.0/22"
  availability_zone       = element(data.aws_availability_zones.available.names, 1)
  map_public_ip_on_launch = true
}

resource "aws_subnet" "AgentSubnetC" {
  vpc_id                  = aws_vpc.AgentVPC.id
  cidr_block              = "10.0.8.0/22"
  availability_zone       = element(data.aws_availability_zones.available.names, 2)
  map_public_ip_on_launch = true
}

resource "aws_ecs_cluster" "AgentCluster" {
  name = "Dagster-Cloud-${var.DagsterOrganization}-${var.DagsterDeployment}-Cluster"

  capacity_providers = ["FARGATE"]

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
  }
}

resource "aws_ecs_task_definition" "AgentTaskDefinition" {
  family                   = "DagsterAgent"
  cpu                      = "256"
  memory                   = "512"
  requires_compatibilities = ["FARGATE"]

  container_definitions = jsonencode([
    {
      "name": "DagsterAgent",
      "image": "docker.io/dagster/dagster-cloud-agent:1.3.10",
      "environment": [
        {
          "name": "DAGSTER_HOME",
          "value": "/opt/dagster/dagster_home"
        }
      ],
      "entryPoint": [
        "bash",
        "-c"
      ],
      "stopTimeout": 120,
      "command": [
        <<-EOF
        /bin/bash -c "
        mkdir -p $DAGSTER_HOME && echo 'instance_class:
          module: dagster_cloud
          class: DagsterCloudAgentInstance

        dagster_cloud_api:
          url: \"https://${var.DagsterOrganization}.agent.dagster.cloud\"
          agent_token: \"${var.AgentToken}\"
          ${DeploymentConfig}
          branch_deployments: ${var.EnableBranchDeployments}

        user_code_launcher:
          module: dagster_cloud.workspace.ecs
          class: EcsUserCodeLauncher
          config:
            cluster: ${ConfigCluster}
            subnets: [${ConfigSubnet}]
            service_discovery_namespace_id: ${ServiceDiscoveryNamespace}
            execution_role_arn: ${TaskExecutionRole.arn}
            task_role_arn: ${AgentRole.arn}
            log_group: ${aws_logs_log_group.AgentLogGroup.name}
            requires_healthcheck: ${var.EnableZeroDowntimeDeploys}
        ' > $DAGSTER_HOME/dagster.yaml && cat $DAGSTER_HOME/dagster.yaml && dagster-cloud agent run"
        EOF
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": aws_logs_log_group.AgentLogGroup.name,
          "awslogs-region": data.aws_region.current.name,
          "awslogs-stream-prefix": "agent"
        }
      },
      "healthCheck": {
        "command": [
          "CMD-SHELL",
          "test -f /opt/finished_initial_reconciliation_sentinel.txt"
        ],
        "interval": 60,
        "startPeriod": 300,
        "retries": 5
      }
    }
  ])

  execution_role_arn = aws_iam_role.TaskExecutionRole.arn
  task_role_arn      = aws_iam_role.AgentRole.arn
  network_mode       = "awsvpc"
}

resource "aws_ecs_service" "AgentService" {
  name            = "Dagster-Cloud-${var.DagsterOrganization}-${var.DagsterDeployment}-Service"
  cluster         = aws_ecs_cluster.AgentCluster.id
  desired_count   = var.NumReplicas
  launch_type     = "FARGATE"
  task_definition = aws_ecs_task_definition.AgentTaskDefinition.arn

  deployment_controller {
    type = "ECS"
    type = "CODE_DEPLOY"
    type = "EXTERNAL"
    type = "EXTERNAL"
  }

  network_configuration {
    awsvpc_configuration {
      subnets          = [aws_subnet.AgentSubnetA.id, aws_subnet.AgentSubnetB.id, aws_subnet.AgentSubnetC.id]
      assign_public_ip = "ENABLED"
    }
  }
}

resource "aws_service_discovery_private_dns_namespace" "ServiceDiscoveryNamespace" {
  name = "dagster-agent-${var.DagsterOrganization}-${var.DagsterDeployment}-${uuid()}"

  vpc = aws_vpc.AgentVPC.id

  dns_properties {
    soa {
      ttl = 100
    }
  }
}

resource "aws_iam_role" "TaskExecutionRole" {
  name               = "TaskExecutionRole"
  assume_role_policy = <<-EOF
    {
      "Version": "2012-10-17",
      "Statement": [
        {
          "Effect": "Allow",
          "Principal": {
            "Service": "ecs-tasks.amazonaws.com"
          },
          "Action": "sts:AssumeRole",
          "Condition": {
            "ArnLike": {
              "aws:SourceArn": "arn:aws:ecs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
            },
            "StringEquals": {
              "aws:SourceAccount": data.aws_caller_identity.current.account_id
            }
          }
        }
      ]
    }
  EOF

  managed_policy_arns = ["arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"]
}

resource "aws_iam_role" "AgentRole" {
  name               = "AgentRole"
  assume_role_policy = <<-EOF
    {
      "Version": "2012-10-17",
      "Statement": [
        {
          "Effect": "Allow",
          "Principal": {
            "Service": "ecs-tasks.amazonaws.com"
          },
          "Action": "sts:AssumeRole",
          "Condition": {
            "ArnLike": {
              "aws:SourceArn": "arn:aws:ecs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
            },
            "StringEquals": {
              "aws:SourceAccount": data.aws_caller_identity.current.account_id
            }
          }
        }
      ]
    }
  EOF

  policy {
    name        = "root"
    policy_json = <<-EOF
      {
        "Version": "2012-10-17",
        "Statement": [
          {
            "Effect": "Allow",
            "Action": [
              "ecs:ListTagsForResource",
              "secretsmanager:DescribeSecret",
              "secretsmanager:GetSecretValue",
              "secretsmanager:ListSecrets"
            ],
            "Resource": "*"
          },
          {
            "Effect": "Allow",
            "Action": [
              "ec2:DescribeRouteTables",
              "ec2:DescribeNetworkInterfaces",
              "ecs:ListAccountSettings"
            ],
            "Resource": "*"
          },
          {
            "Effect": "Allow",
            "Action": [
              "ecs:CreateService",
              "ecs:DeleteService",
              "ecs:DescribeServices",
              "ecs:DescribeTasks",
              "ecs:ListServices",
              "ecs:ListTasks",
              "ecs:RunTask",
              "ecs:StopTask",
              "ecs:UpdateService"
            ],
            "Resource": "*",
            "Condition": {
              "ArnLike": {
                "ecs:cluster": aws_ecs_cluster.AgentCluster.arn
              }
            }
          },
          {
            "Effect": "Allow",
            "Action": [
              "ecs:TagResource"
            ],
            "Resource": "${aws_ecs_cluster.AgentCluster.arn}*"
          },
          {
            "Effect": "Allow",
            "Action": [
              "ecs:DescribeTaskDefinition",
              "ecs:RegisterTaskDefinition",
              "ecs:TagResource"
            ],
            "Resource": "*"
          },
          {
            "Effect": "Allow",
            "Action": [
              "iam:PassRole"
            ],
            "Resource": "*"
          },
          {
            "Effect": "Allow",
            "Action": [
              "logs:GetLogEvents"
            ],
            "Resource": "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:${aws_logs_log_group.AgentLogGroup.name}:log-stream:*"
          },
          {
            "Effect": "Allow",
            "Action": [
              "servicediscovery:ListServices",
              "servicediscovery:ListTagsForResource",
              "servicediscovery:ListInstances",
              "servicediscovery:DeregisterInstance",
              "servicediscovery:GetOperation",
              "servicediscovery:DeleteService"
            ],
            "Resource": "*"
          },
          {
            "Effect": "Allow",
            "Action": [
              "servicediscovery:CreateService",
              "servicediscovery:GetNamespace",
              "servicediscovery:TagResource"
            ],
            "Resource": aws_service_discovery_private_dns_namespace.ServiceDiscoveryNamespace.arn
          }
        ]
      }
    EOF
  }
}
