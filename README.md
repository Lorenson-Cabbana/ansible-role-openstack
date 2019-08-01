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

# Bugs (and workarounds/fixes)
Some functions of this role rely on fixes for bugs in Ansible's modules for Openstack, below is a list of PR's this role depends on:

* https://github.com/ansible/ansible/pull/59055 for removing default added Security Group egress rules
* https://github.com/ansible/ansible/pull/20969 for creating instances with a static IP address

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

* Add a new credential type to Tower with the following configuration (you can also use the playbook in playbooks/)
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
	* Openstack: the credentials for your Openstack service, for all details, download the RC file from Horizon -> API Access
* Create your playbooks/workflows (see below)

# Components
After setting up the authentication as described above you can now start writing playbooks to deploy things on the Openstack service.

## Networks
A network can be deployed as follows, it will automatically be prefixed with 'net-' to avoid naming collisions with other components.

The role will also provision a subnet (named 'subnet-{{ name }}').

```
- name: 'Create network'
  import_role:
    name: 'openstack'
  vars:
    target_action: 'network'
    target_state: 'present'
    target_args:
      name: 'somenet'
      subnet: '192.168.1.0/24'
      gateway: '192.168.1.1'
      dns:
        - '192.168.1.1'
      dhcp_enabled: true
      routes:
        - destination: '10.0.0.0/8'
          nexthop: '192.168.1.1'
      external: false
```

## Routers
Routers can be used to connect multiple subnets together, and can also be used as external gateway to access the Internet (outbound connectivity only).

Routers are created with the 'rtr-' prefix.

```
- name: 'Create router'
  import_role:
    name: 'openstack'
  vars:
    target_action: 'router'
    target_state: 'present'
    target_args:
      name: 'mgmt'
      interfaces:
        - 'subnet-somenet'
```

## Compute instances with persistent storage
The example below is how to create a Debian server with a public connected interface and a private interface.

If defined, a hostgroup can also be created for the servers created with any of the policies mentioned in the os_server_group module documentation.

NOTE: as long as [ansible #20969](https://github.com/ansible/ansible/pull/20969/files) remains unmerged, the static IP will not work, unless you provide a modded version of os_server.py with the fix from this PR.
```
- name: 'Create server'
  import_role:
    name: 'openstack'
  vars:
    target_action: 'server_persistent'
    target_state: 'present'
    target_args:
      name: 'server'
      image: 'Debian 9 (LTS)'
      flavor: 'Standard 1GB'
      disk_gb: 10
      group_name: 'grp-mgmt'
      group_policies:
        - 'affinity'
      networks:
        - net-name: 'net-public'
        - net-name: 'net-mgmt'
          v4-fixed-ip: '192.168.1.10'
      customization: |
        {%- raw -%}#!/bin/bash
        echo "auto eth1" >> /etc/network/interfaces
        echo "iface eth1 inet dhcp" >> /etc/network/interfaces
        ifup eth1
        {%- endraw -%}
```

## Security groups
Security groups are the firewall layer of the network, they will allow or disallow traffic leaving your instances.

This role will create security groups, rules and apply the groups to the interfaces of servers.

Groups are created with the 'secgrp-' prefix.

```
- name: 'Create security group'
  import_role:
    name: 'openstack'
  vars:
    target_action: 'security_group'
    target_state: 'present'
    target_args:
      name: 'ext-shell'
      description: 'Allow SSH and ICMP from external sources'
      rules:
        - proto: 'tcp'
          port_min: 22
          port_max: 22
          remote_ips: '0.0.0.0/0' # or remote_secgrp: 'security group'
          direction: 'ingress'
        - proto: 'icmp'
          port_min: '-1'
          port_max: '-1'
          remote_ips: '0.0.0.0/0' # or remote_secgrp: 'security group'
          direction: 'ingress'
      apply_hosts:
        - name: 'server'
          network: 'net-public'
```

When security groups are created they always contain a set of rules that allow any egress traffic to 0.0.0.0/0, this can nullify the existing firewall policies you want to create to isolate project machines from each other.

Unfortunately it is not possible to remove these rules without [ansible PR #?????](https://github.com/ansible/ansible/pull/?????), as matching rules with protocol 'any' is not possible. If you apply the PR on your copy of the os_security_group_rule module it will remove these default egress rules.
