#!/bin/bash

sudo apt-get install -y unzip jq 

VAULT_ZIP="vault.zip"
VAULT_URL="${vault_download_url}"
curl --silent --output /tmp/$${VAULT_ZIP} $${VAULT_URL}
unzip -o /tmp/$${VAULT_ZIP} -d /usr/local/bin/
chmod 0755 /usr/local/bin/vault
chown vault:vault /usr/local/bin/vault
mkdir -pm 0755 /etc/vault.d
mkdir -pm 0755 /opt/vault
chown azureuser:azureuser /opt/vault

export VAULT_ADDR=http://127.0.0.1:8200

cat << EOF > /lib/systemd/system/vault.service
[Unit]
Description=Vault Agent
Requires=network-online.target
After=network-online.target

[Service]
Restart=on-failure
PermissionsStartOnly=true
ExecStartPre=/sbin/setcap 'cap_ipc_lock=+ep' /usr/local/bin/vault
ExecStart=/usr/local/bin/vault server -config /etc/vault.d
ExecReload=/bin/kill -HUP $MAINPID
KillSignal=SIGTERM
User=azureuser
Group=azureuser

[Install]
WantedBy=multi-user.target
EOF


cat << EOF > /etc/vault.d/config.hcl
storage "file" {
  path = "/opt/vault"
}

listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = 1
}

ui=true
disable_mlock = true
EOF


sudo chmod 0664 /lib/systemd/system/vault.service
systemctl daemon-reload
sudo chown -R vault:vault /etc/vault.d
sudo chmod -R 0644 /etc/vault.d/*

cat << EOF > /etc/profile.d/vault.sh
export VAULT_ADDR=http://127.0.0.1:8200
export VAULT_SKIP_VERIFY=true
export VAULT_SEAL_TYPE="azurekeyvault"
export VAULT_AZUREKEYVAULT_VAULT_NAME="${vault_name}"
export VAULT_AZUREKEYVAULT_KEY_NAME="${key_name}"
export AZURE_TENANT_ID="${tenant_id}"
export AZURE_CLIENT_ID="${client_id}"
export AZURE_CLIENT_SECRET="${client_secret}"
EOF

systemctl enable vault
systemctl start vault


sudo cat << EOF > /tmp/azure_auth.sh
set -v
export VAULT_ADDR="http://127.0.0.1:8200"

vault auth enable azure

vault write auth/azure/config tenant_id="${tenant_id}" resource="https://management.azure.com/" client_id="${client_id}" client_secret="${client_secret}"

vault write auth/azure/role/dev-role policies="default" bound_subscription_ids="${subscription_id}" bound_resource_groups="${resource_group_name}"

vault write auth/azure/login role="dev-role" \
  jwt="$(curl 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https%3A%2F%2Fmanagement.azure.com%2F'  -H Metadata:true -s | jq -r .access_token)" \
  subscription_id="${subscription_id}" \
  resource_group_name="${resource_group_name}" \
  vm_name="${vm_name}"
EOF

sudo chmod +x /tmp/azure_auth.sh

sudo cat << SECRET > /tmp/azure_secret.sh
set -v
export VAULT_ADDR="http://127.0.0.1:8200"

vault secrets enable azure

vault write azure/config subscription_id="${subscription_id}" tenant_id="${tenant_id}" client_id="${client_id}" client_secret="${client_secret}"

vault write azure/roles/reader-role ttl=1h azure_roles=-<<EOF
    [
        {
            "role_name": "Reader",
            "scope":  "/subscriptions/${subscription_id}"
        }
    ]
EOF
SECRET

sudo chmod +x /tmp/azure_secret.sh
