locals {
  master_private_ip = var.master_private_ip
  user_data         = <<EOF
#!/bin/bash
echo "
docker run -p 8786:8786 -p 8787:8787 --entrypoint \"dask-worker tcp://${local.master_private_ip}:8786 --nworkers=auto\" daskdev/dask:2022.7.1-py3.10
" > /home/ubuntu/docker-init.sh;
EOF

}

module "security_group_worker" {

  source  = "terraform-aws-modules/security-group/aws"
  version = ">= 4.9.0, < 5.0.0"

  name        = join("-", [var.project_name, var.env])
  description = "opening ssh access to ec2 instance"
  vpc_id      = var.vpc_id

  ingress_with_cidr_blocks = [
    {
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      description = "SSH tunnel to database"
      cidr_blocks = "0.0.0.0/0"
    },
    {
      # TODO: set 8786 to vpc cidr
      # TODO: keep 8787 to global public
      from_port   = 8786
      to_port     = 8787
      protocol    = "tcp"
      description = "Dask ports"
      cidr_blocks = "0.0.0.0/0"
    },
    {
      from_port   = 0
      to_port     = 0
      protocol    = "tcp"
      description = "Opening access to whole infrastructure"
      cidr_blocks = "0.0.0.0/0"
    },
  ]

  egress_with_cidr_blocks = [
    {
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      description = "Access to whole infrastructure"
      cidr_blocks = "0.0.0.0/0"
    },
  ]
}

module "dask_worker" {


  source  = "terraform-aws-modules/ec2-instance/aws"
  version = ">= 4.1.0, < 5.0.0"

  count = var.workers_count

  name = join("-", [var.project_name, var.env, count.index])

  ami           = var.ami
  instance_type = var.instance_type
  key_name      = var.key_name
  monitoring    = true

  spot_price                          = "0.90"
  spot_wait_for_fulfillment           = true
  spot_type                           = "persistent"
  spot_instance_interruption_behavior = "terminate"

  vpc_security_group_ids      = [module.security_group_worker.security_group_id]
  subnet_id                   = var.subnet_id
  associate_public_ip_address = true

  root_block_device = [
    {
      encrypted   = true
      volume_type = "gp3"
      throughput  = 200
      volume_size = 30
    },
  ]

  user_data                   = local.user_data
  user_data_replace_on_change = true

}
