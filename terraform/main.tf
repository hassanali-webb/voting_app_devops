############################################
# PROVIDERS
############################################
provider "aws" {
  region = "us-east-2"
}

############################################
# VPC (FREE-TIER OPTIMIZED)
############################################
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.1.2"

  name = "voting-app-vpc"
  cidr = "10.0.0.0/16"

  azs            = ["us-east-2a", "us-east-2b"]
  public_subnets = ["10.0.1.0/24", "10.0.2.0/24"]

  enable_nat_gateway      = false
  map_public_ip_on_launch = true
  enable_dns_hostnames    = true
  enable_dns_support      = true
}

############################################
# SECURITY GROUP (EKS NODES)
############################################
resource "aws_security_group" "eks_nodes_sg" {
  name_prefix = "eks-nodes-sg-"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

############################################
# EKS CLUSTER
############################################
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.11.0"

  cluster_name    = "voting-app-cluster"
  cluster_version = "1.30"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.public_subnets

  cluster_endpoint_public_access = true

  enable_cluster_creator_admin_permissions = true

  eks_managed_node_groups = {
    micro_nodes = {
      desired_size = 3
      min_size     = 3
      max_size     = 3 # 🔥 FIXED (stable 3 nodes)

      instance_types = ["t3.micro"]
      ami_type       = "AL2_x86_64"
      capacity_type  = "ON_DEMAND"

      vpc_security_group_ids = [
        aws_security_group.eks_nodes_sg.id
      ]
    }
  }
}

############################################
# CLUSTER AUTH DATA
############################################
data "aws_eks_cluster" "cluster" {
  name = module.eks.cluster_name
}

data "aws_eks_cluster_auth" "cluster" {
  name = module.eks.cluster_name
}

############################################
# KUBERNETES PROVIDER
############################################
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.cluster.token
}

############################################
# HELM PROVIDER (FIXED)
############################################
provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    token                  = data.aws_eks_cluster_auth.cluster.token
  }
}

############################################
# INGRESS CONTROLLER (FIXED)
############################################
resource "helm_release" "ingress_nginx" {
  name             = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  namespace        = "ingress-nginx"
  create_namespace = true

  force_update = true
  replace      = true

  values = [
    yamlencode({
      controller = {
        service = {
          type = "NodePort"
        }
      }
    })
  ]
}

############################################
# OUTPUTS
############################################
output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}
