# Ansible toolkit for Openstack
This role provides a means to provision multiple components of an Openstack enduser environment (NOTE: This does NOT deploy Openstack, it will only deploy stuff ON an Openstack service of your choosing).

This code has been developed using the Openstack 2.0 service of CloudVPS (https://www.cloudvps.nl). It should be service agnostic, if the featureset of the service is comparible with that of CloudVPS. Your mileage may vary, you have been warned!

The following components can be deployed using this role:

* Routers
* Networks
* Compute Instances, including updating metadata
* Security groups (including rules and application to Compute instances)
* Volumes

This role will also setup the following:

* SSH keypair to attach to newly created Compute instances
* Host groups to group systems together
* Install required software to interact with the Openstack API

# Bugs (and workarounds/fixes)
Some functions of this role rely on fixes for bugs in Ansible's modules for Openstack, below is a list of PR's this role depends on:

Workarounds:
* https://github.com/ansible/ansible/pull/59055 for removing default added Security Group egress rules
* https://github.com/ansible/ansible/pull/66351 for removing default added Security Group egress rules (part 2)

Bugs:
* https://github.com/ansible/ansible/issues/19863 at time of writing it is not possible to allocate a fixed floating IP to a server. Code is present that will allow this, but the module does not use it.

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

* Add a new credential type to Tower with the following configuration (you can also use the [playbooks/tower_add_credential_type.yml](add_credential_type) playbook)
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

There are 2 ways to create the host, it will use the disk provided by the flavor, or it can create a new volume and boot from there.

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
      disk_gb: 10 # NOTE: this will create a _separate_ volume on OS to boot from, this might incur extra fees!
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

## Get server info
You can request all information the API has from an instance with the following snippet. It will register all facts into 'os_server_info'

```
- name: 'Get server facts'
  import_role:
    name: 'openstack'
  vars:
    target_action: 'server_info'
    target_args:
      name: 'server1'

- name: 'List all security groups'
  debug:
    msg: "{{ os_server_info['openstack_servers'][0]['security_groups'] }}"
```

## Update server metadata
You can also update the metadata of an existing server with the following code.
```
- name: 'Get server facts'
  import_role:
    name: 'openstack'
  vars:
    target_action: 'server_metadata'
    target_state: 'present'
    target_args:
      name: 'server1'
      meta:
        key1: 'value1'
        key2: 'value2'
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

Unfortunately it is not possible to remove these rules without [ansible PR #59055](https://github.com/ansible/ansible/pull/59055), as matching rules with protocol 'any' is not possible. If you apply the PR on your copy of the os_security_group_rule module it will remove these default egress rules.

## Volumes
Volumes are used as either the boot volume for a VM or as an extra disk to store data on.

This role can do the following actions on volumes:

* Create / delete
* Attach / Detach from host
* Snapshot

```
- name: 'Create volume and attach to instance'
  import_role:
    name: 'openstack'
  vars:
    target_action: 'volume'
    target_state: 'present'
    target_args:
      name: 'volume1'
      size: 50
      attach_host: 'server1'

- name: 'Create volume snapshot'
  import_role:
    name: 'openstack'
  vars:
    target_action: 'volume'
    target_state: 'present'
    target_args:
      name: 'volume1'
      snap_name: 'before_big_change'

- name: 'Detach volume from server1'
  import_role:
    name: 'openstack'
  vars:
    target_action: 'volume'
    target_state: 'present'
    target_args:
      name: 'volume1'
      detach_host: 'server1'
```
