# ansible-vps
La idea de este proyecto es configurar de forma atomatizada un servidor VPS para hostear servicios basados en imagenes docker. El servidor detectará cuando subes una nueva imagen de tus servicios a dockerhub y hará un nuevo despliegue. El objetivo es configurarlo todo de forma automática en poco tiempo para centrarte en desarrollar tus proyectos sin tener que pensar en la infraestructura en exceso. Esta alternativa te permite desplegar tus proyectos de forma más económica respecto a servicios de hosting dedicados. 

Si no dispones de un proyecto en particular que desplegar puedes probar el codigo con el ejemplo de base de datos MariaDB que se incluye en el código. No puedo confirmarlo pero creo que puedes usar este mismo proyecto en una máquina virtual que tengas en tu localhost si quieres probar el código sin contratar una VPS.

He desarrollado una guía más detallada en el siguiente enlace --> [Guía](https://app.gitbook.com/o/zhiwD9T7aIpHje3tHOwR/s/RDpGUpgtYFiJN3RSO60J/guias/configura-tu-vps-para-ci-cd) 

Prerrequisitos de VPS:
- Sistema operativo Ubuntu recien creado
- El vps cuenta con ip pública IPv4 y nos da un usuario con permisos root

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
