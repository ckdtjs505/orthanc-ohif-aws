# Single EC2 instance in the default VPC running the docker compose stack from ../docker.
# Access for admins is via SSM Session Manager (no SSH key, no port 22).

data "aws_vpc" "default" {
  default = true
}

data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_security_group" "pacs" {
  name        = "${var.project}-sg"
  description = "Mini PACS: HTTP from allowed CIDRs, optional DICOM"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "HTTP (nginx -> OHIF / Orthanc)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidrs
  }

  dynamic "ingress" {
    for_each = length(var.dicom_allowed_cidrs) > 0 ? [1] : []
    content {
      description = "DICOM C-STORE"
      from_port   = 4242
      to_port     = 4242
      protocol    = "tcp"
      cidr_blocks = var.dicom_allowed_cidrs
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_iam_role" "ec2" {
  name = "${var.project}-ec2-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Basic-auth password lives in Parameter Store, not in user data (which is readable via the EC2 API).
resource "aws_ssm_parameter" "basic_auth_password" {
  name  = "/${var.project}/basic-auth-password"
  type  = "SecureString"
  value = var.basic_auth_password
}

resource "aws_iam_role_policy" "read_password" {
  name = "${var.project}-read-basic-auth"
  role = aws_iam_role.ec2.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "ssm:GetParameter"
      Resource = aws_ssm_parameter.basic_auth_password.arn
    }]
  })
}

resource "aws_iam_instance_profile" "ec2" {
  name = "${var.project}-ec2-profile"
  role = aws_iam_role.ec2.name
}

locals {
  docker_dir = "${path.module}/../docker"

  user_data = templatefile("${path.module}/user_data.sh.tftpl", {
    compose_version = var.compose_version
    basic_auth_user = var.basic_auth_user
    password_param  = aws_ssm_parameter.basic_auth_password.name
    region          = var.region
    compose_b64     = filebase64("${local.docker_dir}/docker-compose.yml")
    nginx_conf_b64  = filebase64("${local.docker_dir}/nginx/default.conf")
    ohif_config_b64 = filebase64("${local.docker_dir}/ohif/app-config.js")
    ohif_nginx_b64  = filebase64("${local.docker_dir}/ohif/nginx.conf.template")
  })
}

resource "aws_instance" "pacs" {
  ami                    = data.aws_ssm_parameter.al2023.value
  instance_type          = var.instance_type
  vpc_security_group_ids = [aws_security_group.pacs.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2.name

  user_data                   = local.user_data
  depends_on                  = [aws_iam_role_policy.read_password]
  user_data_replace_on_change = true

  metadata_options {
    http_tokens = "required" # IMDSv2 only
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = var.volume_size_gb
    encrypted   = true
  }

  tags = {
    Name = var.project
  }

  lifecycle {
    ignore_changes = [ami]
  }
}

resource "aws_eip" "pacs" {
  instance = aws_instance.pacs.id
  domain   = "vpc"

  tags = {
    Name = var.project
  }
}
