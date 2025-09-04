# Configure your VPS with Ansible

[Ver este README en español](./README.es.md)

The idea of this project is to automatically configure a VPS server to host services based on Docker images. The server will detect when you upload a new image of your services to DockerHub and perform a new deployment. The goal is to configure everything automatically in a short time so you can focus on developing your projects without having to think too much about infrastructure. This alternative allows you to deploy your projects more economically compared to dedicated hosting services.

## Example Service (MariaDB)

If you don't have a particular project to deploy, you can test the code with the MariaDB database example included in the code (I've chosen not to expose the ports, you can modify this in the yourapp.yml playbook). I've also configured a reverse proxy (Traefik) so that if you add a web service, it will automatically provide HTTPS certification.

> I've detailed some steps a bit more in the following guide --> [Guide](https://app.gitbook.com/o/zhiwD9T7aIpHje3tHOwR/s/RDpGUpgtYFiJN3RSO60J/guias/configura-tu-vps-para-ci-cd)

*I can't confirm it, but I believe you can use this same project on a virtual machine that you have on your localhost if you want to test the code without hiring a VPS.*


VPS prerequisites:
- Freshly created Ubuntu operating system
- The VPS has a public IPv4 address and provides a user with root permissions

## Quick Start
1. Log in (from where you will run the ansible project) via SSH with the root user for the first time to create a fingerprint and close the session.
```
ssh root@ipvps
```
2. Configure the files in the group_vars directory by removing the example- prefix and modifying the values with your data
3. Configure your VPS data in the inventory.ini and inventory_root.ini files
4. Review and modify the files in ./playbooks/ with your data, the services you want to deploy, and any extra configurations you wish to make.
5. Run the project with the following commands
The first command will create a user with the necessary permissions
```
ansible-playbook step1.yml -i inventory_root.ini --ask-pass
```
The second command will configure SSH to make connections more secure
```
ansible-playbook step2.yml -i inventory.ini --private-key ~/.ssh/privatesskey
```
Now you'll be able to connect to the VPS without being prompted for a password using SSH keys
```
ssh -i ~/.ssh/privatesskey root@ipVps
```
The third command will install dependencies and configure the services
```
ansible-playbook step3.yml -i inventory.ini --private-key ~/.ssh/privatesskey
```
### Check that it worked
If all steps have been successfully completed, you will be able to connect to your VPS and run the following command to see the status of your services

```
sudo docker ps
```

### Help

To run this project, you must have Ansible installed. You can see the installation process on the official Ansible website. As of today, I understand that it is not possible to install Ansible directly on Windows (I could be wrong). I personally installed virtualized Ubuntu on Windows, installed Ansible using the guide on the official Ubuntu website, and navigated to the project directory from Ubuntu with the following command:

```
//Project content on drive D
cd /mnt/d/projectPath
```