# assettrack
App destinada a inventariar inventarios de hardware y software con su criticidad y responsable

# Documento de ambientes
## 0.Diagrama de infraestructura

![[Pasted image 20260825085204.png]]
## 1. Armado de las VMs

**VM-CI**

|||
|---|---|
|SO|Ubuntu Server 24.04 LTS (sin escritorio)|
|RAM|5 GB, o 8 GB |
|vCPU|2|
|Disco|40 GB, VDI dinámico|
|Red|Adaptador 1 NAT, Adaptador 2 host-only `vboxnet0`|

sudo apt install openssh-server 
sudo systemctl enable --now ssh

**VM-APP**

|||
|---|---|
|SO|Ubuntu Server 24.04 LTS|
|RAM|3 GB|
|vCPU|2|
|Disco|20 GB, VDI dinámico|
|Red|Adaptador 1 NAT, Adaptador 2 host-only `vboxnet0`|

sudo apt install openssh-server 
sudo systemctl enable --now ssh

- Credenciales:
	- User: deploy
	- Pass: deploy
## 2. Configuración de red en VirtualBox

#### Comprobación de VMs y apagado de equipos
```bash
VBoxManage list vms
"VM_CI" {5756a65c-7691-498a-9fb6-01c09b736804}
"VM-APP" {f3dfa333-80ec-444b-9b9c-19fd6207430c}

VBoxManage controlvm "VM_CI" poweroff 2>/dev/null
VBoxManage controlvm "VM-APP" poweroff 2>/dev/null

VBoxManage list runningvms    # tiene que salir vacío
```

#### Configuración de red

```bash
VBoxManage list hostonlyifs
VBoxManage hostonlyif create


0%...10%...20%...30%...40%...50%...60%...70%...80%...90%...100%
Interface 'vboxnet0' was successfully created

```

```bash
VBoxManage hostonlyif ipconfig vboxnet0 --ip 192.168.56.1 --netmask 255.255.255.0
VBoxManage dhcpserver modify --ifname vboxnet0 --disable 2>/dev/null

VBoxManage modifyvm "VM_CI"  --nic2 hostonly --hostonlyadapter2 vboxnet0
VBoxManage modifyvm "VM-APP" --nic2 hostonly --hostonlyadapter2 vboxnet0

VBoxManage showvminfo "VM_CI"  --machinereadable | grep -E "^nic[12]="
VBoxManage showvminfo "VM-APP" --machinereadable | grep -E "^nic[12]="
```

*Salida*

```bash
nic1="nat"
nic2="hostonly"
nic1="nat"
nic2="hostonly"
```
#### Encendido de VMs

```bash
ip -br link
```

Vas a ver `lo`, algo tipo `enp0s3` (NAT) y `enp0s8` (host-only). La segunda placa es la nueva, sin IP asignada. Confirmalo antes de escribir.

En **VM_CI**:

bash

```bash
sudo tee /etc/netplan/99-hostonly.yaml > /dev/null <<'EOF'
network:
  version: 2
  ethernets:
    enp0s8:
      dhcp4: false
      addresses: [192.168.56.10/24]
EOF
sudo chmod 600 /etc/netplan/99-hostonly.yaml
sudo netplan apply
```

En **VM-APP**, lo mismo cambiando `.10` por `.20`.

Verificar que haya tomado bien la ip y el funcionamiento de internet

```bash
ip -br addr          # enp0s8 con la IP nueva
ping -c2 1.1.1.1     # internet sigue vivo
```

#### Atajos de SSH en Host

```bash
cat >> ~/.ssh/config <<'EOF'

Host vmci
    HostName 192.168.56.10
    User deploy

Host vmapp
    HostName 192.168.56.20
    User deploy
EOF
```

Probar conexión (Solicita password)

```bash
ssh vmci
ssh vmapp
```

Para que no solicite mas password, correr el siguiente comando


```bash
ssh-copy-id deploy@192.168.56.10
ssh-copy-id deploy@192.168.56.20
```
#### Configuración de claves en VM_CI

Generas el par de claves:

```bash
ssh-keygen -t ed25519 -C "runner@vm-ci" -f ~/.ssh/id_ed25519 -N ""
ssh-copy-id deploy@192.168.56.20
ssh deploy@192.168.56.20 'echo OK'
```

Comprobamos el funcionamiento. Ejecutar el siguiente comando desde VM_CI hacia VM-APP

```bash
docker -H ssh://deploy@192.168.56.20 ps
```


## 3. Instalación de Docker en VM-CI y VM-APP

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install ca-certificates curl -y

sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update

sudo apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y

sudo systemctl status docker

```

#### Opcional: Ejecutar Docker sin usar `sudo`

```bash
sudo usermod -aG docker $USER
```

Desloguearse de la sesión y volver a iniciarla.
Nota: Probar el funcionamiento de docker sin sudo:

```bash
docker ps -a
```

Salida esperada:


```bash
CONTAINER ID   IMAGE     COMMAND   CREATED   STATUS    PORTS     NAMES
(Vacío)
```

Docker version 29.7.2, build a7dcaa6
