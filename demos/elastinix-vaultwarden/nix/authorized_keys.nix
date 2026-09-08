# Root SSH keys baked into the bootstrap image.
#
# Deployment reaches the machine over SSM rather than public SSH, but it still
# authenticates with this key — the SSM session only carries the SSH
# connection. The matching private key is `ssh_id_file` in the tfvars.
[
  "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKINGVowIMjcemIuZN03e1/uFO6y4Ke89QK3PvQrFjrA vaultwarden-demo"
]
