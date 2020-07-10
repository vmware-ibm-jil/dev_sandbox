provider "vcd" {
  user                 = var.vcd_user
  password             = var.vcd_pass
  org                  = var.vcd_org
  vdc                  = var.vcd_vdc
  url                  = var.vcd_url
  max_retry_timeout    = var.vcd_max_retry_timeout
  allow_unverified_ssl = var.vcd_allow_unverified_ssl
}

data "vcd_org" "jil-org" {
  name   = var.vcd_org
}
data "vcd_network_routed" "jil-org-net" {
  name = var.vcd_org_net
}

data "vcd_org_vdc" "jil-vdc" {
  org     = data.vcd_org.jil-org.name
  name    = var.vcd_vdc
}

data "vcd_edgegateway" "jil-edge" {
  name = data.vcd_network_routed.jil-org-net.edge_gateway
  org  = data.vcd_org.jil-org.name
  vdc  = data.vcd_org_vdc.jil-vdc.name
}

resource "vcd_vapp" "vapp1" {
  name = var.vapp_name
}

resource "vcd_vapp_org_network" "org_net" {
  vapp_name         = vcd_vapp.vapp1.name
  org_network_name  = data.vcd_network_routed.jil-org-net.name
}


data "template_file" "vm_customization" {
  template = file("setup.sh")
  vars = {
    username    = var.username
    sshkey       = var.sshkey
    userpassword = var.userpassword
    hostname = var.vm_name
  }
}

resource "vcd_vapp_vm" "vm1" {
  vapp_name     = vcd_vapp.vapp1.name
  name          = var.vm_name

  catalog_name  = var.catalog_name
  template_name = var.template_name

  memory        = 4096
  cpus          = 2
  storage_profile    = var.vcd_storage_policy

  network {
    type               = "org"
    name               = vcd_vapp_org_network.org_net.org_network_name
    ip_allocation_mode = "POOL"
    is_primary         = true
  }

  customization {
    enabled = true
    admin_password = "VMware1!"
    initscript = data.template_file.vm_customization.rendered
  }
}
resource "vcd_nsxv_dnat" "dnat-ssh" {
  edge_gateway = data.vcd_edgegateway.jil-edge.name
  network_name = "Public"
  network_type = "ext"

  enabled = true
  logging_enabled = false
  description = "Enable SSH to dev machine"

  original_address   = data.vcd_edgegateway.jil-edge.default_external_network_ip
  original_port      = var.vm_nat_port

  translated_address = vcd_vapp_vm.vm1.network[0].ip
  translated_port    = 22
  protocol           = "tcp"
}

resource "vcd_nsxv_firewall_rule" "ssh-inbound-allow" {
  edge_gateway = data.vcd_edgegateway.jil-edge.name
  action = "accept"
  enabled = true
  logging_enabled = false
  name = "Allow ssh"

  source {
    exclude = false
    ip_addresses = ["any"]
  }

  destination {
    exclude = false
    ip_addresses = [data.vcd_edgegateway.jil-edge.default_external_network_ip]
  }

  service {
    protocol = "tcp"
    port     = var.vm_nat_port
    source_port = "any"
  }
}

resource "time_sleep" "wait" {
  depends_on = [vcd_vapp_vm.vm1]

  create_duration = "90s"
}

resource "null_resource" "next" {
  depends_on = [time_sleep.wait]
}

output "vm-ip-info" {
  value = "VM ${vcd_vapp_vm.vm1.name} has internal IP of ${vcd_vapp_vm.vm1.network[0].ip} and nat IP of ${data.vcd_edgegateway.jil-edge.default_external_network_ip} on port ${var.vm_nat_port}"
}
output "ssh-info" {
  value = "You can now SSH via: ssh ${var.username}@${data.vcd_edgegateway.jil-edge.default_external_network_ip} -p ${var.vm_nat_port}"
}
