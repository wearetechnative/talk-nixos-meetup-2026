# Root SSH keys baked into the bootstrap image.
#
# Deployment itself goes over SSM, not over public SSH — these are for the
# break-glass case. Replace with your own before applying.
[
  # "ssh-ed25519 AAAA... you@example.org"
]
