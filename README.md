# samba-fs

This is a docker images to run a file server for Windows Network Neighborhood sharing folders. It's base on alpine + samba 4 + openldap + [WAM](https://github.com/leejoneshane/WAM).

# How to use

This image has no SSL Certification build-in, so please use it with [letsnginx](https://hub.docker.com/r/leejoneshane/letsnginx) or [traefik](https://hub.docker.com/_/traefik).

```
docker run -p 80:3000 -p 137:137/udp -p 138:138/udp -p 139:139 -p 445:445 \
-v ./permanent_storage/files:/mnt -v ./permanent_storage/users:/sam \
-d leejoneshane/samba-fs
```
