#  Typically all this would be wrapped up in a module, but I didn't to save time.


# Set up the VPC, subnets, IGW, and route tables.
provider "aws" {
  region = "us-east-1"
}

data "aws_availability_zones" "available" {}

resource "aws_vpc" "eks" {
  cidr_block = "${var.full-vpc-subnet}"

  tags = "${
    map(
     "Name", "${var.cluster-name}",
     "kubernetes.io/cluster/${var.cluster-name}", "shared",
     "environment", "${var.environment}",
    )
  }"
}

resource "aws_subnet" "eks_subnet" {
  count = 2

  availability_zone = "${data.aws_availability_zones.available.names[count.index]}"
  cidr_block        = "10.${var.vpc-second-octet}.${count.index}.0/24"
  vpc_id            = "${aws_vpc.eks.id}"

  tags = "${
    map(
     "Name", "${var.cluster-name}",
     "kubernetes.io/cluster/${var.cluster-name}", "shared",
     "environment", "${var.environment}",
    )
  }"
}

resource "aws_internet_gateway" "eks_ig" {
  vpc_id = "${aws_vpc.eks.id}"

  tags = "${
    map(
     "Name", "${var.cluster-name}-igw",
     "kubernetes.io/cluster/${var.cluster-name}", "shared",
     "environment", "${var.environment}",
    )
  }"
}

resource "aws_route_table" "eks_route" {
  vpc_id = "${aws_vpc.eks.id}"

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${aws_internet_gateway.eks_ig.id}"
  }
}

resource "aws_route_table_association" "eks" {
  count = 2

  subnet_id      = "${aws_subnet.eks_subnet.*.id[count.index]}"
  route_table_id = "${aws_route_table.eks_route.id}"
}

# Set up the EKS master IAM role.
resource "aws_iam_role" "eks_role" {
  name = "${var.cluster-name}"

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "eks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
POLICY
}

resource "aws_iam_role_policy_attachment" "eks-AmazonEKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = "${aws_iam_role.eks_role.name}"
}

resource "aws_iam_role_policy_attachment" "eks-AmazonEKSServicePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSServicePolicy"
  role       = "${aws_iam_role.eks_role.name}"
}

# Set up the security group for the master clsuter.
resource "aws_security_group" "eks_cluster" {
  name        = "${var.cluster-name}"
  description = "Cluster communication with worker nodes"
  vpc_id      = "${aws_vpc.eks.id}"

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = "${
    map(
     "environment", "${var.environment}",
    )
  }"
}

# Create the EKS cluster.
resource "aws_eks_cluster" "eks_cluster" {
  name     = "${var.cluster-name}"
  role_arn = "${aws_iam_role.eks_role.arn}"

  vpc_config {
    security_group_ids = ["${aws_security_group.eks_cluster.id}"]
    subnet_ids         = ["${aws_subnet.eks_subnet.*.id}"]
  }

  depends_on = [
    "aws_iam_role_policy_attachment.eks-AmazonEKSClusterPolicy",
    "aws_iam_role_policy_attachment.eks-AmazonEKSServicePolicy",
  ]
}

# Worker node role/policies/instance profile.
resource "aws_iam_role" "eks_node" {
  name = "${var.cluster-name}_node"

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
POLICY
}

resource "aws_iam_role_policy_attachment" "eks-AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = "${aws_iam_role.eks_node.name}"
}

resource "aws_iam_role_policy_attachment" "eks-AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = "${aws_iam_role.eks_node.name}"
}

resource "aws_iam_role_policy_attachment" "demo-node-AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = "${aws_iam_role.eks_node.name}"
}

resource "aws_iam_instance_profile" "eks_node" {
  name = "${var.cluster-name}_node"
  role = "${aws_iam_role.eks_node.name}"
}

# Worker node security groups.
resource "aws_security_group" "eks_node" {
  name        = "${var.cluster-name}-node"
  description = "Security group for all nodes in the cluster"
  vpc_id      = "${aws_vpc.eks.id}"

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = "${
    map(
     "Name", "terraform-eks-node",
     "kubernetes.io/cluster/${var.cluster-name}", "owned",
     "environment", "${var.environment}",
    )
  }"
}

resource "aws_security_group_rule" "eks-node-ingress-self" {
  description              = "Allow node to communicate with each other"
  from_port                = 0
  protocol                 = "-1"
  security_group_id        = "${aws_security_group.eks_node.id}"
  source_security_group_id = "${aws_security_group.eks_node.id}"
  to_port                  = 65535
  type                     = "ingress"
}

resource "aws_security_group_rule" "eks-node-ingress-cluster" {
  description              = "Allow worker Kubelets and pods to receive communication from the cluster control plane"
  from_port                = 1025
  protocol                 = "tcp"
  security_group_id        = "${aws_security_group.eks_node.id}"
  source_security_group_id = "${aws_security_group.eks_cluster.id}"
  to_port                  = 65535
  type                     = "ingress"
}

resource "aws_security_group_rule" "eks-cluster-ingress-node-https" {
  description              = "Allow pods to communicate with the cluster API Server"
  from_port                = 443
  protocol                 = "tcp"
  security_group_id        = "${aws_security_group.eks_cluster.id}"
  source_security_group_id = "${aws_security_group.eks_node.id}"
  to_port                  = 443
  type                     = "ingress"
}

# Grab the ami
data "aws_ami" "eks-worker" {
  filter {
    name   = "name"
    values = ["eks-worker-*"]
  }

  most_recent = true
  owners      = ["602401143452"] # Account id of official aws eks image
}

# Set up the userdata.
data "aws_region" "current" {}

locals {
  eks-node-userdata = <<USERDATA
#!/bin/bash -xe

CA_CERTIFICATE_DIRECTORY=/etc/kubernetes/pki
CA_CERTIFICATE_FILE_PATH=$CA_CERTIFICATE_DIRECTORY/ca.crt
mkdir -p $CA_CERTIFICATE_DIRECTORY
echo "${aws_eks_cluster.eks_cluster.certificate_authority.0.data}" | base64 -d >  $CA_CERTIFICATE_FILE_PATH
INTERNAL_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)
sed -i s,MASTER_ENDPOINT,${aws_eks_cluster.eks_cluster.endpoint},g /var/lib/kubelet/kubeconfig
sed -i s,CLUSTER_NAME,${var.cluster-name},g /var/lib/kubelet/kubeconfig
sed -i s,REGION,${data.aws_region.current.name},g /etc/systemd/system/kubelet.service
sed -i s,MAX_PODS,20,g /etc/systemd/system/kubelet.service
sed -i s,MASTER_ENDPOINT,${aws_eks_cluster.eks_cluster.endpoint},g /etc/systemd/system/kubelet.service
sed -i s,INTERNAL_IP,$INTERNAL_IP,g /etc/systemd/system/kubelet.service
DNS_CLUSTER_IP=10.100.0.10
if [[ $INTERNAL_IP == 10.* ]] ; then DNS_CLUSTER_IP=172.20.0.10; fi
sed -i s,DNS_CLUSTER_IP,$DNS_CLUSTER_IP,g /etc/systemd/system/kubelet.service
sed -i s,CERTIFICATE_AUTHORITY_FILE,$CA_CERTIFICATE_FILE_PATH,g /var/lib/kubelet/kubeconfig
sed -i s,CLIENT_CA_FILE,$CA_CERTIFICATE_FILE_PATH,g  /etc/systemd/system/kubelet.service
systemctl daemon-reload
systemctl restart kubelet
USERDATA
}

# Launch config for worker ASG.
resource "aws_launch_configuration" "eks-launch-config" {
  associate_public_ip_address = true
  iam_instance_profile        = "${aws_iam_instance_profile.eks_node.name}"
  image_id                    = "${data.aws_ami.eks-worker.id}"
  instance_type               = "m4.large"
  name_prefix                 = "${var.cluster-name}-"
  security_groups             = ["${aws_security_group.eks_node.id}"]
  user_data_base64            = "${base64encode(local.eks-node-userdata)}"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "eks-worker" {
  desired_capacity     = 2
  launch_configuration = "${aws_launch_configuration.eks-launch-config.id}"
  max_size             = 2
  min_size             = 1
  name                 = "eks-workers"
  vpc_zone_identifier  = ["${aws_subnet.eks_subnet.*.id}"]

  tag {
    key                 = "Name"
    value               = "eks-worker"
    propagate_at_launch = true
  }

  tag {
    key                 = "kubernetes.io/cluster/${var.cluster-name}"
    value               = "owned"
    propagate_at_launch = true
  }
}

# The assignment asked for a DNS entry but I'm not setting up an ingress cotroller in the EKS cluster
# and I don't have a hosted zone in my aws account.
# This would set a CNAME pointing to the EKS endpoint.
# The ssl certs wouldn't match if you accessed the enpoint via this CNAME

#resource "aws_route53_record" "eks" {
#  zone_id = "PUT_ZONE_ID_IN_HERE"
#  name    = "eks"
#  type    = "CNAME"
#  ttl     = "300"
#  records = ["${replace(aws_eks_cluster.eks_cluster.endpoint, "https://", "")}"]
#}


