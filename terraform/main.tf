provider "aws" {
  region = "us-east-2"
}

# -------------------------
# VPC
# -------------------------
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.1.2"

  name = "voting-app-vpc"
  cidr = "10.0.0.0/16"

  azs            = ["us-east-2a", "us-east-2b"]
  public_subnets = ["10.0.1.0/24", "10.0.2.0/24"]

  enable_nat_gateway   = false # 💰 cost saving
  enable_dns_hostnames = true
  enable_dns_support   = true
}

# -------------------------
# Security Group (VERY IMPORTANT)
# -------------------------
resource "aws_security_group" "eks_nodes_sg" {
  name        = "eks-nodes-sg"
  description = "Allow traffic for EKS nodes"
  vpc_id      = module.vpc.vpc_id

  # HTTP
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTPS
  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Kubernetes NodePort (IMPORTANT)
  ingress {
    description = "K8s NodePort"
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Internal cluster communication
  ingress {
    description = "Cluster internal"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  # Outbound (allow all)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# -------------------------
# EKS Cluster
# -------------------------
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.8.4"

  cluster_name    = "voting-app-cluster"
  cluster_version = "1.29"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.public_subnets
  #----

  enable_cluster_creator_admin_permissions = true

  # -------------------------
  # Node Group
  # -------------------------
  eks_managed_node_groups = {
    micro_nodes = {
      desired_size = 1
      min_size     = 1
      max_size     = 1

      instance_types = ["t3.micro"]
      capacity_type  = "ON_DEMAND"

      vpc_security_group_ids = [
        aws_security_group.eks_nodes_sg.id
      ]
    }
  }
}

# -------------------------
# Outputs
# -------------------------
output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "cluster_security_group_id" {
  value = module.eks.cluster_security_group_id
}
