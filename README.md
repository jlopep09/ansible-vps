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

2. Configura los archivos del directorio group_vars eliminando el prefijo example- y modificando los valores con tus datos
3. Configura los datos de tu vps en los archivos inventory.ini y inventory_root.ini
4. Modifica el archivo playbooks/yourapp.yml con los servicios que quieras desplegar y las confuraciones extra que desees realizar.
5. Ejecuta el proyecto con los siguientes comandos
El primer comando creará un usuario con los permisos necesarios
```
ansible-playbook step1.yml -i inventory_root.ini --ask-pass
```
El segundo comando configurará ssh para hacer mas seguras las conexiones
```
ansible-playbook step2.yml -i inventory.ini --private-key ~/.ssh/clavesshprivada
```
El tercer comando instalará dependencias y configurará los servicios
```
ansible-playbook step3.yml -i inventory.ini --private-key ~/.ssh/clavesshprivada
```