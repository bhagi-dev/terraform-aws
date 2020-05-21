resource "aws_vpc" "my_vpc" {
  cidr_block       = "10.0.0.0/21"
  enable_dns_hostnames = true

  tags {
    Name = "My VPC"
  }
}

resource "aws_subnet" "public_us_east_1a" {
  vpc_id     = "${aws_vpc.my_vpc.id}"
  cidr_block = "10.0.0.0/23"
  availability_zone = "us-east-1a"

  tags {
    Name = "Public Subnet us-east-1a"
  }
}

resource "aws_subnet" "public_us_east_1b" {
  vpc_id     = "${aws_vpc.my_vpc.id}"
  cidr_block = "10.0.2.0/23"
  availability_zone = "us-east-1b"

  tags {
    Name = "Public Subnet us-east-1b"
  }
}

resource "aws_subnet" "private_us_east_1a" {
  vpc_id     = "${aws_vpc.my_vpc.id}"
  cidr_block = "10.0.3.0/23"
  availability_zone = "us-east-1a"

  tags {
    Name = "Public Subnet us-east-1a"
  }
}

resource "aws_subnet" "private_us_east_1b" {
  vpc_id     = "${aws_vpc.my_vpc.id}"
  cidr_block = "10.0.4.0/23"
  availability_zone = "us-east-1b"

  tags {
    Name = "Public Subnet us-east-1b"
  }
}

resource "aws_internet_gateway" "my_vpc_igw" {
  vpc_id = "${aws_vpc.my_vpc.id}"

  tags {
    Name = "My VPC - Internet Gateway"
  }
}

resource "aws_route_table" "my_vpc_route_table" {
    vpc_id = "${aws_vpc.my_vpc.id}"

    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = "${aws_internet_gateway.my_vpc_igw.id}"
    }

    tags {
        Name = "Public Subnets Route Table for My VPC"
    }
}

resource "aws_route_table_association" "my_vpc_us_east_1a_public" {
    subnet_id = "${aws_subnet.public_us_east_1a.id}"
    route_table_id = "${aws_route_table.my_vpc_route_table.id}"
}

resource "aws_route_table_association" "my_vpc_us_east_1b_public" {
    subnet_id = "${aws_subnet.public_us_east_1b.id}"
    route_table_id = "${aws_route_table.my_vpc_route_table.id}"
}

resource "aws_route_table_association" "my_vpc_us_east_1a_private" {
    subnet_id = "${aws_subnet.private_us_east_1a.id}"
    route_table_id = "${aws_route_table.my_vpc_route_table.id}"
}

resource "aws_route_table_association" "my_vpc_us_east_1b_private" {
    subnet_id = "${aws_subnet.private_us_east_1b.id}"
    route_table_id = "${aws_route_table.my_vpc_route_table.id}"
}

resource "aws_instance" "server" {
  ami                         = ami-01d86dd3e5bc5d67f
  instance_type               = t2.micro
  key_name                    = local.ssh_key
  subnet_id                   = public_us_east_1a
  vpc_security_group_ids      = [aws_security_group.id]
  associate_public_ip_address = true

  tags = {
    Name    = "Bastion host"
  }
}


resource "aws_security_group" "allow_http_ssh" {
  name        = "allow_http_ssh"
  description = "Allow HTTP SSH inbound connections"
  vpc_id = "${aws_vpc.my_vpc.id}"

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
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks     = ["0.0.0.0/0"]
  }

  tags {
    Name = "Allow HTTP SSH Security Group"
  }
}

data "aws_s3_bucket_object" "bootstrap_script" {
  bucket = "ourcorp-deploy-config"
  key    = "bootstrap-script.sh"
}

resource "aws_launch_configuration" "web" {
  name_prefix = "web-"

  image_id = "ami-01f08ef3e76b957e5" # Amazon Linux AMI 2018.03.0 (HVM)
  instance_type = "t2.micro"
  key_name = "Lenovo T410"

  security_groups = ["${aws_security_group.allow_http.id}"]
  associate_public_ip_address = true

  user_data = "${data.aws_s3_bucket_object.bootstrap_script.body}"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "elb_http" {
  name        = "elb_http"
  description = "Allow HTTP traffic to instances through Elastic Load Balancer"
  vpc_id = "${aws_vpc.my_vpc.id}"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks     = ["0.0.0.0/0"]
  }

  tags {
    Name = "Allow HTTP through ELB Security Group"
  }
}

resource "aws_elb" "web_elb" {
  name = "web-elb"
  security_groups = [
    "${aws_security_group.elb_http.id}"
  ]
  subnets = [
    "${aws_subnet.public_us_east_1a.id}",
    "${aws_subnet.public_us_east_1b.id}"
  ]
  cross_zone_load_balancing   = true
  health_check {
    healthy_threshold = 2
    unhealthy_threshold = 2
    timeout = 3
    interval = 30
    target = "HTTP:80/"
  }
  listener {
    lb_port = 80
    lb_protocol = "http"
    instance_port = "80"
    instance_protocol = "http"
  }
}

resource "aws_autoscaling_group" "web" {
  name = "${aws_launch_configuration.web.name}-asg"

  min_size             = 1
  desired_capacity     = 2
  max_size             = 4

  health_check_type    = "ELB"
  load_balancers = [
    "${aws_elb.web_elb.id}"
  ]

  launch_configuration = "${aws_launch_configuration.web.name}"
  availability_zones = ["us-east-1a", "us-east-1b"]

  enabled_metrics = [
    "GroupMinSize",
    "GroupMaxSize",
    "GroupDesiredCapacity",
    "GroupInServiceInstances",
    "GroupTotalInstances"
  ]

  metrics_granularity="1Minute"

  vpc_zone_identifier  = [
    "${aws_subnet.public_us_east_1a.*.id}",
    "${aws_subnet.public_us_east_1b.*.id}"
  ]

  # Required to redeploy without an outage.
  lifecycle {
    create_before_destroy = true
  }

  tag {
    key                 = "Name"
    value               = "web"
    propagate_at_launch = true
  }
}

resource "aws_autoscaling_policy" "web_policy_up" {
  name = "web_policy_up"
  scaling_adjustment = 1
  adjustment_type = "ChangeInCapacity"
  cooldown = 300
  autoscaling_group_name = "${aws_autoscaling_group.web.name}"
}

resource "aws_autoscaling_policy" "web_policy_down" {
  name = "web_policy_down"
  scaling_adjustment = -1
  adjustment_type = "ChangeInCapacity"
  cooldown = 300
  autoscaling_group_name = "${aws_autoscaling_group.web.name}"
}


output "ELB IP" {
  value = "${aws_elb.web_elb.dns_name}"
}
