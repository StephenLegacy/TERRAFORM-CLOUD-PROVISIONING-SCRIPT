Stephen Oloo

Last Updated: 09/03/2025 22:44


---

# AWS Terraform Configuration for WordPress Deployment

This repository contains Terraform scripts to deploy a WordPress website on AWS using EC2, Apache, PHP, and MySQL. The infrastructure setup includes creating a VPC, public subnet, internet gateway, security groups, and configuring an EC2 instance.

## Infrastructure Components

### AWS Provider Configuration
```hcl
provider "aws" {
  region = "us-west-2"
}
```
Specifies the AWS provider and the region where the resources will be deployed.

### Ubuntu AMI Data Source
```hcl
data "aws_ssm_parameter" "ubuntu_ami" {
  name = "/aws/service/canonical/ubuntu/server/jammy/stable/current/amd64/hvm/ebs-gp2/ami-id"
}
```
Retrieves the latest Ubuntu AMI ID using AWS Systems Manager Parameter Store.

### VPC, Internet Gateway, and Subnet
```hcl
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
}

resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-west-2a"
  map_public_ip_on_launch = true
}
```
Sets up the VPC, Internet Gateway, and a public subnet for the instance.

### Route Table for Public Subnet
```hcl
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table_association" "public_rt_assoc" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rt.id
}
```
Configures a route table to route all traffic (`0.0.0.0/0`) through the Internet Gateway for the public subnet.

### Security Group (Firewall Rules)
```hcl
resource "aws_security_group" "web_sg" {
  name_prefix = "web-sg-"

  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
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
```
Defines a security group allowing inbound HTTP (port 80) and SSH (port 22) traffic.

### EC2 Instance (WordPress Server)
```hcl
resource "aws_instance" "legacy_web_server" {
  ami                    = data.aws_ssm_parameter.ubuntu_ami.value
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.public_subnet.id
  key_name               = "vockey" # Replace with your actual key pair name
  vpc_security_group_ids = [aws_security_group.web_sg.id]

  user_data = <<-EOF
              #!/bin/bash
              apt-get update -y
              apt-get install -y apache2 php php-mysql mysql-server
              systemctl start apache2
              systemctl enable apache2
              systemctl start mysql
              systemctl enable mysql

              mysql -e "CREATE DATABASE wordpress;"
              mysql -e "CREATE USER 'wpuser'@'localhost' IDENTIFIED BY 'password';"
              mysql -e "GRANT ALL PRIVILEGES ON wordpress.* TO 'wpuser'@'localhost';"
              mysql -e "FLUSH PRIVILEGES;"

              cd /var/www/html
              wget https://wordpress.org/latest.tar.gz
              tar -xzf latest.tar.gz
              mv wordpress/* .
              rm -rf wordpress latest.tar.gz
              chown -R www-data:www-data /var/www/html
              chmod -R 755 /var/www/html

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
    Name = "LegacyWebServer"
  }
}
```
Deploys an EC2 instance using the specified Ubuntu AMI, configures Apache, PHP, MySQL, and installs WordPress. The `user_data` script sets up the database, downloads and configures WordPress, and creates the `wp-config.php` file.

### Elastic IP (EIP)
```hcl
resource "aws_eip" "eip" {
  instance = aws_instance.legacy_web_server.id
}
```
Associates an Elastic IP address with the EC2 instance for a static public IP.

## Serving WordPress from the Root Directory

To serve WordPress from the root directory (`/`), the Apache virtual host configuration (`/etc/apache2/sites-available/000-default.conf`) needs to be modified to point to `/var/www/html` where WordPress is installed. This adjustment ensures the WordPress site is active on the root of the server, not the default Apache test page.

Add or modify this in your `user_data` script after setting up WordPress:

```bash
sed -i 's|DocumentRoot /var/www/html|DocumentRoot /var/www/html|' /etc/apache2/sites-available/000-default.conf
systemctl restart apache2
```

This command changes the Apache document root to `/var/www/html`, where WordPress is installed, and restarts Apache to apply the changes.

## Summary

This Terraform script automates the deployment of a WordPress website on AWS, including setting up necessary infrastructure components and configuring an EC2 instance to serve WordPress from the root directory. It provides a robust and scalable solution for hosting a WordPress site on AWS. Do Not Edit ReadMe

--- 

STEPHEN OLOO 

