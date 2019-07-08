# Ansible toolkit for Openstack
This role provides a means to provision multiple components of an Openstack enduser environment (NOTE: This does NOT deploy Openstack, it will only deploy stuff ON an Openstack service of your choosing).

This code has been developed using the Openstack 2.0 service of CloudVPS (https://www.cloudvps.nl). It should be service agnostic, if the featureset of the service is comparible with that of CloudVPS. Your mileage may vary, you have been warned!

The following components can be deployed using this role:

* Routers
* Networks
* Compute Instances (with persistent storage only)
* Security groups (including rules and application to Compute instances)

The following has not (yet) been included in this role:

* Floating IPs
* Volumes (beyond the default volume that is created with a Compute instance with persistent storage)

This role will also setup the following:

* SSH keypair to attach to newly created Compute instances
* Host groups to group systems together
* Install required software to interact with the Openstack API

# Authentication setup
This role can be used in one of 2 ways, command-line Ansible or via Ansible Tower/AWX. Within the configuration of this role, we refer to the 'Auth source' for either scenario.

## Auth source: File
In order to use this role with the commandline version of Ansible, without Tower, do the following:

* Create a new SSH keypair (or let this role generate one for you), make sure it is RSA
* Copy default/main.yml to your inventory
* Configure the variables in the 'API information' section
* Create your playbooks (see below for more information)

## Auth source: Tower
In order to use this role with Ansible Tower/AWX, do the following:

* Add a new credential type to Tower with the following configuration:
Name: Openstack SSH key
Input:
```
fields:
  - id: key_name
    type: string
    label: SSH key name
  - id: public_key
    type: string
    label: SSH public key
    help_text: SSH public key to attach to newly provisioned Compute instances
    multiline: true
required:
  - key_name
  - public_key
```
Injector:
```
extra_vars:
  openstack_ssh_key_name: '{{ key_name }}'
  openstack_ssh_public_key: '{{ public_key }}'
```
* Configure the following credentials for your project
	* Machine: with a RSA private key
	* Openstack SSH: with the public key of this SSH key
	* Openstack: the credentials for your Openstack service
* Create your playbooks/workflows (see below)
