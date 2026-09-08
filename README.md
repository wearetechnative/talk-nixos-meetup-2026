# ElastiNix & Nivis — NixOS Meetup 2026

Slides and demo material for the talk given by [Pim Snel](https://github.com/mipmip)
at the NixOS Meetup on **8 September 2026**.

The talk is in two halves. The first is [**ElastiNix**](https://github.com/wearetechnative/elastinix),
the flake TechNative uses to run NixOS on AWS: one command that deploys both the
machine and the infrastructure it runs on. The second half is
[**Nivis**](https://github.com/nivis-project/nivis), where that idea goes next —
OpenTofu/Terraform provider resources as first-class Nix values, with provider
outputs round-tripping back into Nix to a fixpoint.

## The slides

`talk-2026-09-08-elastinix.qmd`, rendered with [Quarto](https://quarto.org) to a
reveal.js deck using TechNative's branding extensions.

```sh
nix develop                                   # quarto, TeX, entr
./RUNME.sh install_deps                       # fetch the quarto extensions
quarto render talk-2026-09-08-elastinix.qmd   # -> output/
```

`_extensions/` is not tracked here; `install_deps` fetches it.

## The demos

**ElastiNix — Vaultwarden on AWS** lives in this repo, under
[`demos/elastinix-vaultwarden/`](demos/elastinix-vaultwarden/).

**The Nivis demos live with Nivis**, in
[`nivis-project/nivis-demos`](https://github.com/nivis-project/nivis-demos) —
self-contained catstack-style domains with their own `stackctl`, tests and gate:

```sh
git clone https://github.com/nivis-project/nivis-demos
cd nivis-demos
nix develop

./stackctl demo 000_backend apply --backend=local     # bootstrap the state bucket
./stackctl demo 000_backend state migrate --to-remote
./stackctl demo 010_dns apply                         # the hosted zone
./stackctl demo 020_vaultwarden_ec2 apply             # the workload
```

Every account-specific value in that repo is deliberately fake; read its
*Before you apply anything* section first, and supply your own state bucket name.

## Links

| | |
| --------------------------- | -------------------------------------------------------------- |
| ElastiNix                   | <https://github.com/wearetechnative/elastinix>                   |
| ElastiNix Terraform module  | <https://github.com/wearetechnative/terraform-aws-module-elastinix> |
| Nivis                       | <https://github.com/nivis-project/nivis>                         |
| Nivis docs                  | <https://nivis-project.github.io/nivis/>                         |
| Nivis demos                 | <https://github.com/nivis-project/nivis-demos>                   |
| Nivis registry              | <https://github.com/nivis-project/registry>                      |
| Amplify site module         | <https://github.com/wearetechnative/nivis-aws-amplify-site>      |
| Form endpoint module        | <https://github.com/wearetechnative/nivis-aws-form-action>       |
| Introducing Nivis (blog)    | <https://technative.eu/en/blog/introducing-nivis/>               |

## Credits

ElastiNix would not exist without Jonas Carpay's
[End-to-end declarative deployment](https://jonascarpay.com/posts/2022-09-19-declarative-deployment.html)
(2022), which introduced the core design.

## License

Apache-2.0 — see [LICENSE](LICENSE).
