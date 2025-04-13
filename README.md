# ansible-vps
Proyecto ansible para automatizar configuraciones en un servidor VPS

La idea de este proyecto es preparar un servidor vps con las siguientes características
- Sistema operativo Ubuntu recien creado
- El vps cuenta con ip pública IPv4 y nos da un usuario con permisos root
- Una vez configurado podremos hostear cualquier aplicación basada en docker haciendo uso de watchtower

## Quickstart
1. Inicia sesion (desde donde ejecutaras el proyecto ansible) por ssh con el usuario root por primera vez para crear fingerprint.

```
ssh -i ~/.ssh/clavesshprivada root@ipVps
```

1. Crea el archivo group_vars/vps.yml
2. Introduce el siguiente contenido configurado con tus datos particulares
```
docker_user: "mi_usuario_de_docker"
docker_pass: "mi_contraseña_super_secreta"
```
3. Configura los datos de tu vps en el archivo inventory.ini
4. Modifica el playbook.yml con los servicios que quieras desplegar y las confuraciones extra que desees realizar.
5. Ejecuta el proyecto con los siguientes comandos
```
ansible-playbook step1.yml -i inventory_root.ini --ask-pass
```
```
ansible-playbook step2.yml -i inventory.ini --private-key ~/.ssh/clavesshprivada
ansible-playbook step3.yml -i inventory.ini --private-key ~/.ssh/clavesshprivada
```
