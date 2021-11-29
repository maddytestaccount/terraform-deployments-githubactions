#
# Defines VPC, subnets, security groups, NAT instance, etc.
#

# VPC
provider "aws" {
  region     = "us-east-2"
  access_key = "AKIAXDSL7DJC5HN775LW"
  secret_key = "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"
}
resource "aws_vpc" "default" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true

  tags = {
    Environment = var.env
    Name        = "spire-vpc-${var.env}"
    Provisoning = "terraform"
  }
}

## Public subnets
resource "aws_subnet" "public" {
  vpc_id            = aws_vpc.default.id
  cidr_block        = var.public_subnet_cidr_blocks["zone${count.index}"]
  availability_zone = "${var.region}${element(var.zones, count.index)}"
  count             = length(var.zones)

  tags = {
    Environment = var.env
    Name        = "spire-subnet-${var.env}-public-${count.index}"
    Type        = "spire-subnet-${var.env}-public"
    Provisoning = "terraform"
  }
}

### Custom route table for public subnets
resource "aws_route_table" "custom" {
  vpc_id = aws_vpc.default.id

  tags = {
    Environment = var.env
    Name        = "spire-${var.env}-public-rt"
    Provisoning = "terraform"
  }
}

#### Route for customer route table
resource "aws_route" "custom" {
  route_table_id         = aws_route_table.custom.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.default.id
  depends_on             = [aws_route_table.custom]
}

### NAT GW eip
resource "aws_eip" "natgw" {
  vpc = true
  tags = {
    Name = "spire-vpc-igw"
    Environment = var.env
    Provisoning = "terraform"
  }
}

### Internet Gateway
resource "aws_internet_gateway" "default" {
  vpc_id = aws_vpc.default.id
  tags = {
    Name = "spire-nat-sg"
    Environment = var.env
    Provisoning = "terraform"
  }
}

### NAT Gateway
resource "aws_nat_gateway" "natgw" {
  allocation_id = aws_eip.natgw.id
  subnet_id     = element(aws_subnet.public.*.id, 0)

  tags = {
    Environment = var.env
    Name        = "natgw-${var.env}"
    Provisoning = "terraform"
  }
}

#### Associate custom route table with public subnets
resource "aws_route_table_association" "public" {
  subnet_id      = element(aws_subnet.public.*.id, count.index)
  route_table_id = aws_route_table.custom.id
  count          = length(var.zones)
}

## Private subnets
resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.default.id
  cidr_block        = var.private_subnet_cidr_blocks["zone${count.index}"]
  availability_zone = "${var.region}${element(var.zones, count.index)}"
  count             = length(var.zones)

  tags = {
    Environment   = var.env
    Name          = "spire-subnet-${var.env}-private-${count.index}"
    Type          = "spire-subnet-${var.env}-private"
    Provisoning   = "terraform"
  }
}

### Main route table
resource "aws_route_table" "main" {
  vpc_id = aws_vpc.default.id

  tags = {
    Environment = var.env
    Name        = "spire-${var.env}-private-rt"
    Provisoning = "terraform"
  }
}

### Update main route table to use NAT
resource "aws_route" "main" {
  route_table_id         = aws_route_table.main.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.natgw.id
  depends_on             = [aws_nat_gateway.natgw]
}

### Associate main route table with private subnets
resource "aws_route_table_association" "private" {
  subnet_id      = element(aws_subnet.private.*.id, count.index)
  route_table_id = aws_route_table.main.id
  count          = length(var.zones)
}

### Set main route table
resource "aws_main_route_table_association" "main" {
  vpc_id         = aws_vpc.default.id
  route_table_id = aws_route_table.main.id
}

resource "aws_s3_bucket" "lambda" {
  bucket = "lambda-${var.env}.spire.io"
  region = var.region
  tags = {
    Environment = var.env
  }

  versioning {
    enabled = false
  }


  lifecycle_rule {
    abort_incomplete_multipart_upload_days = 7
    id                                     = "delete_failed_multipart_uploads"
    enabled                                = true
  }

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }
}