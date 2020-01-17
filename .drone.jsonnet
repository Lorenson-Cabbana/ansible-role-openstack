[
  {
    name: "Lint",
    kind: "pipeline",
    steps: [
      {
        name: "Lint code",
        image: "quay.io/ansible/molecule",
        commands: [
          "pip install -U ansible molecule",
          "molecule lint",
          "molecule syntax"
        ],
        privileged: true,
        volumes: [
          { name: "docker", path: "/var/run/docker.sock" },
        ],
      }
    ],
    volumes: [
      { name: "docker",
        host: { path: "/var/run/docker.sock" }
      },
    ],
  },
  {
    name: "Publish",
    kind: "pipeline",
    clone:
      { disable: true },
    steps: [
      {
        name: "Ansible Galaxy",
        image: "quay.io/ansible/molecule",
        commands: [
          "ansible-galaxy login --github-token $$GITHUB_TOKEN",
          "ansible-galaxy import Thulium-Drake ansible-role-openstack --role-name=openstack",
        ],
        environment:
          { GITHUB_TOKEN: { from_secret: "github_token" } },
      },
    ],
    depends_on: [
      "Lint",
    ],
  },
]
