provider "aws" {
  region = "us-west-2"  #you can change to any region
}

# Fetch the latest Ubuntu AMI ID from the SSM parameter store
data "aws_ssm_parameter" "ubuntu_ami" {
  name = "/aws/service/canonical/ubuntu/server/jammy/stable/current/amd64/hvm/ebs-gp2/ami-id"
}

# Create a VPC with a CIDR block
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

# Create an Internet Gateway to allow internet access
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
}

# Create a public subnet within the VPC
resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-west-2a"
  map_public_ip_on_launch = true
}

# Create a route table for the public subnet
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id

  # Route all outbound traffic (0.0.0.0/0) to the Internet Gateway
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

# Associate the route table with the public subnet
resource "aws_route_table_association" "public_rt_assoc" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rt.id
}

# Create a security group to allow HTTP and SSH access
resource "aws_security_group" "web_sg" {
  name_prefix = "web-sg-"

  vpc_id = aws_vpc.main.id

  # Allow HTTP access
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow SSH access
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Launch an EC2 instance with the specified AMI and instance type
resource "aws_instance" "legacy_web_server" {
  ami                    = data.aws_ssm_parameter.ubuntu_ami.value
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.public_subnet.id
  key_name               = "vockey" # Replace with your actual key pair name
  vpc_security_group_ids = [aws_security_group.web_sg.id]

  # User data script to configure the instance on launch
  user_data = <<-EOF
              #!/bin/bash
              apt-get update -y
              apt-get install -y apache2 php php-mysql mysql-server
              systemctl start apache2
              systemctl enable apache2
              systemctl start mysql
              systemctl enable mysql

              # Setup MySQL database and user for WordPress
              mysql -e "CREATE DATABASE wordpress;"
              mysql -e "CREATE USER 'wpuser'@'localhost' IDENTIFIED BY 'password';"
              mysql -e "GRANT ALL PRIVILEGES ON wordpress.* TO 'wpuser'@'localhost';"
              mysql -e "FLUSH PRIVILEGES;"

              # Download and extract WordPress
              cd /var/www/html
              wget https://wordpress.org/latest.tar.gz
              tar -xzf latest.tar.gz
              mv wordpress/* .
              rm -rf wordpress latest.tar.gz
              chown -R www-data:www-data /var/www/html
              chmod -R 755 /var/www/html

              # Create the wp-config.php file
              cat > /var/www/html/wp-config.php <<-EOF2
              <?php
              define('DB_NAME', 'wordpress');
              define('DB_USER', 'wpuser');
              define('DB_PASSWORD', 'password');
              define('DB_HOST', 'localhost');
              define('DB_CHARSET', 'utf8');
              define('DB_COLLATE', '');
              \$table_prefix  = 'wp_';
              define('WP_DEBUG', false);
              if ( !defined('ABSPATH') )
                  define('ABSPATH', dirname(__FILE__) . '/');
              require_once(ABSPATH . 'wp-settings.php');
              EOF2
              EOF

  tags = {
    Name = "LegacyWebServer"  #Any name for your web server or instance
  }
}

# Associate an Elastic IP to the EC2 instance for a static IP address
resource "aws_eip" "eip" {
  instance = aws_instance.legacy_web_server.id
}
