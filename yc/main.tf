# ***********************************************
#	Set provider and credentials
# ***********************************************

terraform {
  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
    }
  }
  required_version = ">= 0.13"
}

# How to work with this: 
#	terraform plan -var-file=cred.tfvar | terraform aplly -var-file=cred.tfvar | terraform destroy -var-file=cred.tfvar
provider "yandex" {
	 token 		= var.token
	 cloud_id 	= var.cloud_id
	 folder_id 	= var.folder_id
    zone = "ru-central1-b"
}

# ***********************************************
#	Main part
# ***********************************************


resource "yandex_vpc_network" "yc-net1" {
	name = "yc-net1"
}

resource "yandex_vpc_subnet" "yc-snetb1" {
  name           = "yc-snetb1"
  zone           = "ru-central1-b"
  network_id     = yandex_vpc_network.yc-net1.id
  v4_cidr_blocks = ["192.168.10.0/24"]
}


resource "yandex_compute_instance" "vm-1" {
	name 			= "terraform1"
	platform_id = "standard-v2"
#	status		= stop

	resources {
		core_fraction = 20
   	cores  = 2   
		gpus   = 0 
		memory = 2
  	}

	boot_disk {
    	initialize_params {
      	image_id = "fd80le4b8gt2u33lvubr"
			size		= 10
   	}
  	}	

  	network_interface {
    	subnet_id = yandex_vpc_subnet.yc-snetb1.id
   	nat       = true
  	}

	# Significantly decrease VM's price for Yandex Cloud
   scheduling_policy {
   	preemptible = true
   }

	# Add local user to sudoer
  	metadata = {
   	ssh-keys = "centos:${file("./key/id_rsa.pub")}"
		user-data = "${file("./meta.txt")}"	
		serial-port-enable=1
  	}

  	provisioner "remote-exec" {
  		inline = ["sudo hostnamectl set-hostname gnomeCraft1"]
#		on_failure = continue

		connection {
		   host        = yandex_compute_instance.vm-1.network_interface.0.nat_ip_address 	# coalesce(self.public_ip, self.private_ip)
		   agent       = true
		   type        = "ssh"
		   user        = "test"
		   private_key = file("./key/id_rsa")
		}
	}
	
 	provisioner "local-exec" {
#   	command = "ansible-playbook -i '${yandex_compute_instance.vm-1.network_interface.0.nat_ip_address},' -u test --private-key ./key/id_rsa --extra-vars \"host=${yandex_compute_instance.vm-1.network_interface.0.nat_ip_address}\" ./just_check.yml"
   	command = "ansible-playbook -i '${yandex_compute_instance.vm-1.network_interface.0.nat_ip_address},' -u test --private-key ./key/id_rsa --extra-vars \"hosts=${yandex_compute_instance.vm-1.network_interface.0.nat_ip_address}\" ./clichePrepare.yml"
  	}
}

# Just to user infrom
output "internal_ip_address_vm_1" {
  value = yandex_compute_instance.vm-1.network_interface.0.ip_address
}

output "external_ip_address_vm_1" {
  value = yandex_compute_instance.vm-1.network_interface.0.nat_ip_address
}

