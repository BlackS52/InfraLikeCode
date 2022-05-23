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
#	Init variables
# ***********************************************

variable "isMasterNode" {
  	type      = bool
	default 	 = false
  	sensitive = false
	description = "Master node have DHCP, TFTP and need to boot another PXE nodes. If isMaster=true then deploy these services. Default state - false."
}

variable "isMakeImage" {
  	type      = bool
	default 	 = false
  	sensitive = false
	description = "Do you want to make an image? Default state - false."
}



# ***********************************************
#	Preapre Object storage for image loading
# ***********************************************

resource "yandex_iam_service_account" "sa" {
  folder_id = var.folder_id
  name      = "imgmng"
}

# Grant permissions
resource "yandex_resourcemanager_folder_iam_member" "sa-editor" {
  folder_id = var.folder_id
  role      = "storage.admin"
  member    = "serviceAccount:${yandex_iam_service_account.sa.id}"
}

# Create Static Access Keys
resource "yandex_iam_service_account_static_access_key" "sa-static-key" {
  service_account_id = yandex_iam_service_account.sa.id
  description        = "static access key for object storage"
}

# Use keys to create bucket
resource "yandex_storage_bucket" "bctimgs" {
  bucket = "bucketimg"

  access_key = yandex_iam_service_account_static_access_key.sa-static-key.access_key
  secret_key = yandex_iam_service_account_static_access_key.sa-static-key.secret_key

  grant {
    id          = var.user_id
    type        = "CanonicalUser"
    permissions = ["FULL_CONTROL"]
  }
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

	# ***********************************************
	#	Deploy 
	# ***********************************************

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
#   	command = "ansible-playbook -i '${yandex_compute_instance.vm-1.network_interface.0.nat_ip_address},' -u test --private-key ./key/id_rsa --extra-vars \"hosts=${yandex_compute_instance.vm-1.network_interface.0.nat_ip_address} isMasterNode=${var.isMasterNode} isMakeImage=${var.isMakeImage}\" ./clichePrepare.yml"
   	command = "ansible-playbook -i '${yandex_compute_instance.vm-1.network_interface.0.nat_ip_address},' -u test --private-key ./key/id_rsa --extra-vars \"hosts=${yandex_compute_instance.vm-1.network_interface.0.nat_ip_address} access_key=${yandex_iam_service_account_static_access_key.sa-static-key.access_key} secret_key=${yandex_iam_service_account_static_access_key.sa-static-key.secret_key} isMasterNode=${var.isMasterNode} isMakeImage=${var.isMakeImage}\" ./clichePrepare.yml"
  	}
}



## Load object to bucket from local directory. Seems not that we are lookup
#resource "yandex_storage_object" "object1" {
#  access_key = yandex_iam_service_account_static_access_key.sa-static-key.access_key
#  secret_key = yandex_iam_service_account_static_access_key.sa-static-key.secret_key
#
#  bucket = yandex_storage_bucket.bucket1.bucket
#  key    = "WasAble"
#  source = "wasAble.txt"
#}



# ***********************************************
#	Output
# ***********************************************

# Just to user infrom
output "internal_ip_address_vm_1" {
  value = yandex_compute_instance.vm-1.network_interface.0.ip_address
}

output "external_ip_address_vm_1" {
  value = yandex_compute_instance.vm-1.network_interface.0.nat_ip_address
}

