# Troubleshooting

## Docker

Check all compose stack health at once:

```sh
sudo docker ps --format "table {{.Names}}\t{{.Status}}"
```

## DNS

### Quick Diagnostic Commands

Test AdGuard DNS directly from the NAS:

```sh
dig SVLNAS.<domain> @<router IP>
```

Test full external resolution chain via router:

```sh
dig google.com @<router IP>
```

Test DNSSEC chain:

```sh
dig +dnssec internetsociety.org @<router IP>
```

Test Quad9 DNS directly:

```sh
dig google.com @9.9.9.9
```
