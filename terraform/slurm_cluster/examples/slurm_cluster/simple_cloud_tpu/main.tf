/**
 * Copyright (C) SchedMD LLC.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     https://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

##########
# LOCALS #
##########

locals {
  controller_instance_config = {
    disk_size_gb    = 32
    disk_type       = "pd-standard"
    machine_type    = "n1-standard-4"
    service_account = module.slurm_sa_iam["controller"].service_account
    subnetwork      = data.google_compute_subnetwork.default.self_link
    enable_public_ip = true
  }

  login_nodes = [
    {
      group_name = "l0"
      num_instances = 2
      disk_size_gb    = 32
      disk_type       = "pd-standard"
      machine_type    = "n1-standard-2"
      service_account = module.slurm_sa_iam["login"].service_account
      subnetwork      = data.google_compute_subnetwork.default.self_link
      enable_public_ip = true
    }
  ]
  nodeset_tpu = [
    {
      nodeset_name           = "v4x8"
      node_type              = "v4-8"
      tf_version             = "2.14.0"
      zone                   = var.zone
      preemptible            = true
      preserve_tpu           = true
      enable_public_ip       = true
      node_count_dynamic_max = 0
      node_count_static      = 8
      subnetwork             = data.google_compute_subnetwork.default.self_link
      service_account        = module.slurm_sa_iam["compute"].service_account
    },
  ]

  partitions = [
    {
      partition_conf = {
        Default = "YES"
      }
      partition_name        = "test"
      partition_nodeset_tpu = [local.nodeset_tpu[0].nodeset_name]
      resume_timeout        = 900
    },
  ]
}

############
# PROVIDER #
############

provider "google" {
  project = var.project_id
  region  = var.region
}

########
# DATA #
########

data "google_compute_subnetwork" "default" {
  name = "default"
}

#################
# SLURM CLUSTER #
#################

module "slurm_cluster" {
  source = "../../../../slurm_cluster"

  region                     = var.region
  slurm_cluster_name         = var.slurm_cluster_name
  controller_instance_config = local.controller_instance_config
  login_nodes                = local.login_nodes
  partitions                 = local.partitions
  nodeset_tpu                = local.nodeset_tpu
  project_id                 = var.project_id

  depends_on = [
    module.slurm_firewall_rules,
    module.slurm_sa_iam,
  ]

  controller_startup_scripts = [
    {
      filename = "controller-login-sssd.sh"
      content  = file("${path.module}/scripts/controller-login-sssd.sh")
    },
  ]

  compute_startup_scripts = [
    {
      filename = "compute-setup-sssd.sh"
      content  = file("${path.module}/scripts/compute-setup-sssd.sh")
    },
  ]

  login_startup_scripts = [
    {
      filename = "controller-login-sssd.sh"
      content  = file("${path.module}/scripts/controller-login-sssd.sh")
    },
    {
      filename = "makeuser.sh"
      content  = file("${path.module}/scripts/makeuser.sh")
    }
  ]

}

##################
# FIREWALL RULES #
##################

module "slurm_firewall_rules" {
  source = "../../../../slurm_firewall_rules"

  slurm_cluster_name = var.slurm_cluster_name
  network_name       = data.google_compute_subnetwork.default.network
  project_id         = var.project_id
}

##########################
# SERVICE ACCOUNTS & IAM #
##########################

module "slurm_sa_iam" {
  source = "../../../../slurm_sa_iam"

  for_each = toset(["controller", "login", "compute"])

  account_type       = each.value
  slurm_cluster_name = var.slurm_cluster_name
  project_id         = var.project_id
}
