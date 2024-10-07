provider "aws" {
  region = "us-east-1"
}

locals {
  services = {
    "ec2messages" : {
      "name" : "com.amazonaws.us-east-1.ec2messages"
    },
    "ssm" : {
      "name" : "com.amazonaws.us-east-1.ssm"
    },
    "ssmmessages" : {
      "name" : "com.amazonaws.us-east-1.ssmmessages"
    }
  }
}


// VPC Module
module "vpc" {
  source          = "terraform-aws-modules/vpc/aws"
  name            = "evrim-vpc-dev"
  azs             = var.azs
  public_subnets  = var.public_subnet_cidrs
  private_subnets = var.private_subnet_cidrs

  enable_nat_gateway   = true
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = {
    Name = "Evrim Dev"
  }
}


// Configure VPC for SSM
resource "aws_vpc_endpoint" "ssm_endpoint" {
  for_each            = local.services
  vpc_id              = module.vpc.vpc_id
  service_name        = each.value.name
  vpc_endpoint_type   = "Interface"
  security_group_ids  = [aws_security_group.ssm_https.id]
  private_dns_enabled = true
  ip_address_type     = "ipv4"
  subnet_ids          = module.vpc.private_subnets
}


resource "aws_security_group" "ssm_https" {
  name        = "allow_ssm"
  description = "Allow SSM traffic"
  vpc_id      = module.vpc.vpc_id
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [module.vpc.vpc_cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "Private Instance"
  }
}


// configure SSM for the instance
resource "aws_iam_role" "ssm_role" {
  name = "ssm_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}


resource "aws_iam_role_policy_attachment" "ssm_role_AmazonSSMManagedInstanceCore" {
  role       = aws_iam_role.ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ssm_instance_profile" {
  name = "ssm_instance_profile"
  role = aws_iam_role.ssm_role.name
}

// the follwing is closely related to this tutorial https://www.youtube.com/watch?v=XhS2JbPg8jA&t=1128s
// security group
resource "aws_security_group" "evrim-dev-server-private" {
  name        = "evrim-dev-server-private"
  description = "Allow API Access"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "Allow Healthchecks"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [module.vpc.vpc_cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


// create ec2 instance
resource "aws_instance" "evrim-dev-server" {
  ami                    = "ami-04b70fa74e45c3917"
  instance_type          = "t2.xlarge"
  vpc_security_group_ids = [aws_security_group.evrim-dev-server-private.id]
  subnet_id              = module.vpc.private_subnets[0]
  iam_instance_profile   = aws_iam_instance_profile.ssm_instance_profile.name

  // increase the volume size of root volume
  root_block_device {
    volume_size = 256
  }

  tags = {
    Name = "Private Evrim Dev Server"
  }
}

// ECR
resource "aws_ecr_repository" "evrim-server" {
  name                 = "evrim-server"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name = "Evrim Server Repo"
  }
}

resource "aws_ecr_repository" "evrim-discord" {
  name                 = "evrim-discord"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name = "Evrim Discord Repo"
  }
}


// keep the last 5 images
resource "aws_ecr_lifecycle_policy" "evrim-server-lifecycle" {
  repository = aws_ecr_repository.evrim-server.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1,
        description  = "Keep last 5 images",
        selection = {
          tagStatus   = "any",
          countType   = "imageCountMoreThan",
          countNumber = 5
        },
        action = {
          type = "expire"
        }
      }
    ]
  })

}


resource "aws_ecr_lifecycle_policy" "evrim-discord-lifecycle" {
  repository = aws_ecr_repository.evrim-discord.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1,
        description  = "Keep last 5 images",
        selection = {
          tagStatus   = "any",
          countType   = "imageCountMoreThan",
          countNumber = 5
        },
        action = {
          type = "expire"
        }
      }
    ]
  })

}

// Create Evrim UI tagret group
resource "aws_lb_target_group" "evrim-ui-tg" {
  name     = "evrim-dev-ui-tg"
  port     = 3000
  protocol = "HTTP"
  vpc_id   = module.vpc.vpc_id
  health_check {
    enabled = true
    path    = "/login/"
  }
}

resource "aws_lb_target_group_attachment" "evrim-ui-tg-attachment" {
  target_group_arn = aws_lb_target_group.evrim-ui-tg.arn
  target_id        = aws_instance.evrim-dev-server.id
  port             = 3000
}

// Create AWS LB target group
resource "aws_lb_target_group" "evrim-dev-server-tg" {
  name     = "evrim-dev-server-tg"
  port     = 8080
  protocol = "TCP"
  vpc_id   = module.vpc.vpc_id
  health_check {
    enabled = true
    path    = "/ht/"
  }
}


resource "aws_lb_target_group_attachment" "evrim-dev-server-tg-attachment" {
  target_group_arn = aws_lb_target_group.evrim-dev-server-tg.arn
  target_id        = aws_instance.evrim-dev-server.id
  port             = 8080
}


// Prviate ALB
resource "aws_lb" "evrim-dev-server-lb" {
  name               = "evrim-dev-server-lb"
  internal           = true
  load_balancer_type = "network"
  subnets            = module.vpc.private_subnets

  tags = {
    Name = "Evrim Dev Server LB"
  }
}

// Listener
resource "aws_lb_listener" "evrim-dev-server-lb-listener" {
  load_balancer_arn = aws_lb.evrim-dev-server-lb.arn
  port              = 8080
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.evrim-dev-server-tg.arn
  }
}

// Create Listener for UI
resource "aws_lb_listener" "evrim-ui-lb-listener" {
  load_balancer_arn = aws_lb.evrim-dev-server-lb.arn
  port              = 3000
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.evrim-ui-tg.arn
  }
}


// API Gateway
resource "aws_apigatewayv2_api" "evrim-dev-api-gw" {
  name          = "evrim-dev-api-gw"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_stage" "evrim-dev-api-gw-stage" {
  api_id      = aws_apigatewayv2_api.evrim-dev-api-gw.id
  name        = "prod"
  auto_deploy = true
}

// Gateway VPC Link
resource "aws_apigatewayv2_vpc_link" "evrim-dev-api-gw-vpc-link" {
  name               = "evrim-dev-api-gw-vpc-link"
  security_group_ids = [aws_security_group.evrim-dev-server-private.id]
  subnet_ids         = module.vpc.private_subnets
}

// Gateway private resource integration
resource "aws_apigatewayv2_integration" "evrim-dev-gw-integration" {
  api_id = aws_apigatewayv2_api.evrim-dev-api-gw.id

  integration_uri    = aws_lb_listener.evrim-dev-server-lb-listener.arn
  integration_type   = "HTTP_PROXY"
  integration_method = "ANY"
  connection_type    = "VPC_LINK"
  connection_id      = aws_apigatewayv2_vpc_link.evrim-dev-api-gw-vpc-link.id
}


// UI Gateway private resource integration
resource "aws_apigatewayv2_integration" "evrim-ui-gw-integration" {
  api_id = aws_apigatewayv2_api.evrim-dev-api-gw.id

  integration_uri    = aws_lb_listener.evrim-ui-lb-listener.arn
  integration_type   = "HTTP_PROXY"
  integration_method = "ANY"
  connection_type    = "VPC_LINK"
  connection_id      = aws_apigatewayv2_vpc_link.evrim-dev-api-gw-vpc-link.id
}


// Gateway proxy route
resource "aws_apigatewayv2_route" "name" {
  api_id = aws_apigatewayv2_api.evrim-dev-api-gw.id

  route_key = "ANY /{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.evrim-dev-gw-integration.id}"
}

// UI Gateway proxy route
resource "aws_apigatewayv2_route" "ui-name" {
  api_id = aws_apigatewayv2_api.evrim-dev-api-gw.id

  route_key = "ANY /{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.evrim-ui-gw-integration.id}"
}


// Route53 for GoDaddy Domain
resource "aws_route53_zone" "evrim-domain" {
  name = var.evrim-domain
}


// AWS API Domain ACM Certificate
resource "aws_acm_certificate" "evrim-api-domain-cert" {
  domain_name       = var.evrim-api-domain
  validation_method = "DNS"

  tags = {
    Name = "Evrim API Domain Certificate"
  }
}


// AWS UI Domain ACM Certificate
resource "aws_acm_certificate" "evrim-ui-domain-cert" {
  domain_name       = var.evrim-ui-domain
  validation_method = "DNS"

  tags = {
    Name = "Evrim UI Domain Certificate"
  }
}

// Route53 Record for ACM Certificate Validation
resource "aws_route53_record" "evrim-api-domain-cert-validation" {
  for_each = {
    for dvo in aws_acm_certificate.evrim-api-domain-cert.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
    }
  }

  zone_id = aws_route53_zone.evrim-domain.zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = 300
  records = [each.value.record]
}

// Route53 Record for ACM Certificate Validation  for UI
resource "aws_route53_record" "evrim-ui-domain-cert-validation" {
  for_each = {
    for dvo in aws_acm_certificate.evrim-ui-domain-cert.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
    }
  }

  zone_id = aws_route53_zone.evrim-domain.zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = 300
  records = [each.value.record]
}

// wait for the api certificate to be issued
resource "aws_acm_certificate_validation" "ervim-api-domain-cert-validation" {
  certificate_arn         = aws_acm_certificate.evrim-api-domain-cert.arn
  validation_record_fqdns = [for record in aws_route53_record.evrim-api-domain-cert-validation : record.fqdn]
}

// wait for the ui certificate to be issued
resource "aws_acm_certificate_validation" "ervim-ui-domain-cert-validation" {
  certificate_arn         = aws_acm_certificate.evrim-ui-domain-cert.arn
  validation_record_fqdns = [for record in aws_route53_record.evrim-ui-domain-cert-validation : record.fqdn]
}


// API Gateway Custom Domain
resource "aws_apigatewayv2_domain_name" "evrim-api-domain" {
  domain_name = var.evrim-api-domain

  domain_name_configuration {
    certificate_arn = aws_acm_certificate.evrim-api-domain-cert.arn
    endpoint_type   = "REGIONAL"
    security_policy = "TLS_1_2"
  }
}


// API Gateway Custom Domain for UI
resource "aws_apigatewayv2_domain_name" "evrim-ui-domain" {
  domain_name = var.evrim-ui-domain

  domain_name_configuration {
    certificate_arn = aws_acm_certificate.evrim-ui-domain-cert.arn
    endpoint_type   = "REGIONAL"
    security_policy = "TLS_1_2"
  }
}


// Map the domain to the API Gateway
resource "aws_apigatewayv2_api_mapping" "evrim-dev-api-mapping" {
  api_id      = aws_apigatewayv2_api.evrim-dev-api-gw.id
  domain_name = aws_apigatewayv2_domain_name.evrim-api-domain.domain_name
  stage       = aws_apigatewayv2_stage.evrim-dev-api-gw-stage.name
}


// Map the domain to the UI Gateway
resource "aws_apigatewayv2_api_mapping" "evrim-ui-api-mapping" {
  api_id      = aws_apigatewayv2_api.evrim-dev-api-gw.id
  domain_name = aws_apigatewayv2_domain_name.evrim-ui-domain.domain_name
  stage       = aws_apigatewayv2_stage.evrim-dev-api-gw-stage.name
}


// Route53 alias record
resource "aws_route53_record" "evrim-api-domain-alias" {
  zone_id = aws_route53_zone.evrim-domain.zone_id
  name    = aws_apigatewayv2_domain_name.evrim-api-domain.domain_name
  type    = "A"

  alias {
    name                   = aws_apigatewayv2_domain_name.evrim-api-domain.domain_name_configuration[0].target_domain_name
    zone_id                = aws_apigatewayv2_domain_name.evrim-api-domain.domain_name_configuration[0].hosted_zone_id
    evaluate_target_health = false
  }
}

// Route53 alias record for UI
resource "aws_route53_record" "evrim-ui-domain-alias" {
  zone_id = aws_route53_zone.evrim-domain.zone_id
  name    = aws_apigatewayv2_domain_name.evrim-ui-domain.domain_name
  type    = "A"

  alias {
    name                   = aws_apigatewayv2_domain_name.evrim-ui-domain.domain_name_configuration[0].target_domain_name
    zone_id                = aws_apigatewayv2_domain_name.evrim-ui-domain.domain_name_configuration[0].hosted_zone_id
    evaluate_target_health = false
  }
}

// outputs for ecr uris
output "evrim_server_ecr_uri" {
  value = aws_ecr_repository.evrim-server.repository_url
}

output "evrim_discord_ecr_uri" {
  value = aws_ecr_repository.evrim-discord.repository_url
}

/// output for nameservers
output "evrim_domain_nameservers" {
  value = aws_route53_zone.evrim-domain.name_servers
}

// output for api gateway url
output "evrim_api_cert_arn" {
  value = aws_acm_certificate.evrim-api-domain-cert.arn
}