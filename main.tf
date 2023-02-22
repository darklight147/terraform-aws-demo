terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "4.55.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

resource "tls_private_key" "private_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "my_key" {
  key_name   = "my_key"
  public_key = tls_private_key.private_key.public_key_openssh
}


resource "aws_vpc" "my_vpc" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_internet_gateway" "ig" {
  vpc_id = aws_vpc.my_vpc.id
  depends_on = [
    aws_vpc.my_vpc,
  ]
}
resource "aws_route_table" "example" {
  vpc_id = aws_vpc.my_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.ig.id
  }
}

resource "aws_route_table_association" "example" {
  subnet_id      = aws_subnet.example.id
  route_table_id = aws_route_table.example.id
}


resource "aws_subnet" "example" {
  vpc_id            = aws_vpc.my_vpc.id
  availability_zone = "us-east-1a"
  cidr_block        = "10.0.1.0/24"
  depends_on = [
    aws_vpc.my_vpc,
  ]
}

resource "aws_security_group" "nginx" {
  name        = "nginx"
  description = "Allow inbound traffic"
  vpc_id      = aws_vpc.my_vpc.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP"
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


resource "aws_instance" "example" {
  instance_type          = "t3.micro"
  key_name               = aws_key_pair.my_key.key_name
  subnet_id              = aws_subnet.example.id
  ami                    = "ami-0557a15b87f6559cf" # Ubuntu
  vpc_security_group_ids = [aws_security_group.nginx.id]



  depends_on = [
    aws_internet_gateway.ig,
    aws_subnet.example,
    aws_security_group.nginx,
    aws_route_table_association.example
  ]

  user_data = <<-EOF
    #!/bin/bash
    sudo apt-get update
    sudo apt-get install -y docker.io
    sudo usermod -aG docker ubuntu
    sudo docker run -d -p 80:80 --name yes --rm alexwhen/docker-2048
    EOF



  tags = {
    Name = "yes-server"
  }
}

resource "aws_eip" "example" {
  instance   = aws_instance.example.id
  depends_on = [aws_instance.example]
}

# resource "null_resource" "example" {
#   provisioner "remote-exec" {
#     inline = [
#       "sudo apt-get update",
#       "curl -sSL https://get.docker.com/ | sh",
#       "sudo usermod -aG docker ubuntu",
#       "sudo docker run -d -p 80:80 --name yes --rm alexwhen/docker-2048",
#     ]

#     connection {
#       type        = "ssh"
#       user        = "ubuntu"
#       private_key = tls_private_key.private_key.private_key_pem
#       host        = aws_eip.example.public_ip
#       timeout     = "10m"
#     }
#   }

#   depends_on = [aws_eip.example, aws_instance.example]
# }


output "public_ip" {
  value = "http://${aws_eip.example.public_ip}"

}
