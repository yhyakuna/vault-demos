# Vault Demo on Azure

Terraform provisions Azure resources to demonstrate the following HashiCorp Vault features:

- [Auto-unsealing with Azure Key Vault](#auto-unseal-using-azure-key-vault)
- [Azure auth method](#azure-auth-method)
- [Azure secret engine](#azure-secrets-engine)


# Prerequisites

Follow the instruction in the [Terraform documentation](https://www.terraform.io/docs/providers/azurerm/auth/service_principal_client_certificate.html)
to create a service principal and then configure in Terraform.

**Hints & Tips**:

You can obtain your **subscription ID** and **tenant ID** via Azure Portal or Azure CLI: `az login`

It's probably easier to get the credential from Azure Portal.

- **Subscription ID**: Navigate to the [Subscriptions blade within the Azure Portal](https://portal.azure.com/#blade/Microsoft_Azure_Billing/SubscriptionsBlade) and copy the **Subscription ID**  

    ![Subscription ID](https://s3-us-west-1.amazonaws.com/education-yh/screenshots/vault-autounseal-azure-1.png)

- **Tenant ID**: Navigate to the [Azure Active Directory > Properties](https://portal.azure.com/#blade/Microsoft_AAD_IAM/ActiveDirectoryMenuBlade/Properties) in the Azure Portal, and copy the **Directory ID** which is your tenant ID  

    ![Tenant ID](https://s3-us-west-1.amazonaws.com/education-yh/screenshots/vault-autounseal-azure-2.png)

- **Client ID**: Same as the [**Application ID**](https://portal.azure.com/#blade/Microsoft_AAD_IAM/ApplicationsListBlade)

    ![Client ID](https://s3-us-west-1.amazonaws.com/education-yh/screenshots/vault-autounseal-azure-3.png)

- **Client secret**: The [password (credential)](https://portal.azure.com/#blade/Microsoft_AAD_IAM/ApplicationsListBlade) set on your application

<br>

**NOTE:** It is important that your Service Principal app has appropriate role (e.g. "Owner") and API permissions.

To assign roles: **Subscriptions > [your subscription] > Access control (IAM) > Add role assignment**

Also, I ran into an issue with `Insufficient privileges to complete the operation` error, and I referenced the following:

- https://github.com/Azure-Samples/azure-sdk-for-go-samples/issues/238#issuecomment-441874407
- https://stackoverflow.com/questions/44323560/graph-api-insufficient-privileges-to-complete-the-operation
- https://github.com/Azure/azure-sdk-for-node/issues/2363#issuecomment-354897064

![Granted Permissions](https://s3-us-west-1.amazonaws.com/education-yh/screenshots/vault-azure-sp.png)

---

## Auto-unseal using Azure Key Vault


1. Set this location as your working directory

1. Provide Azure credentials in the `terraform.tfvars.example` and save it as `terraform.tfvars`

    > NOTE: Overwrite the Azure `location` or `environment` name in the `terraform.tfvars` as desired.

1. Run the Terraform commands:

    ```shell
    # Pull necessary plugins
    $ terraform init

    $ terraform plan

    # Output provides the SSH instruction
    $ terraform apply -auto-approve
    ...
    Outputs:

    ip = 52.168.108.142
    key_vault_name = Test-vault-a414d041
    ssh_link = ssh azureuser@52.168.108.142
    ```

1. SSH into the virtual machine:

    ```text
    $ ssh azureuser@52.168.108.142
    ```

1. Check the current Vault status:

    ```text
    $ vault status
    Key                      Value
    ---                      -----
    Recovery Seal Type       azurekeyvault
    Initialized              false
    Sealed                   true
    Total Recovery Shares    0
    Threshold                0
    Unseal Progress          0/0
    Unseal Nonce             n/a
    Version                  n/a
    HA Enabled               false
    ```
    Vault hasn't been initialized, yet.

1. Initialize Vault

    ```plaintext
    $ vault operator init

    Recovery Key 1: PfPiNcKeZRVigLJxqyCPHezqLbLLz8q4PAzeSAueFnvK
    Recovery Key 2: MLLZQL1hsT9Pjp5KYw5f22/q5ia3/A9lf+XpEoEKjiMR
    Recovery Key 3: GLVGur9KTUdOEGSxB8byOZTreRZnHX9fl+F32sxhLsav
    Recovery Key 4: n3I5h2yNOx9sEJ2vej9n4GacYi9Si4RGE8zcssahFlQ+
    Recovery Key 5: 9qG+L8Z5uoyKJMbBPtcXyYw00XJMxLry6h5U5wjl356f

    Initial Root Token: s.bRyEk2vIPrKfeldFZD5xFvUL

    Success! Vault is initialized

    Recovery key initialized with 5 key shares and a key threshold of 3. Please
    securely distribute the key shares printed above.
    ```

1. Stop and start the Vault server

    ```shell
    $ sudo systemctl restart vault
    ```

1. Check to verify that the Vault is auto-unsealed

    ```text
    $ vault status
    Key                      Value
    ---                      -----
    Recovery Seal Type       shamir
    Initialized              true
    Sealed                   false
    Total Recovery Shares    5
    Threshold                3
    Version                  1.0.2
    Cluster Name             vault-cluster-092ba5de
    Cluster ID               8b173565-7d74-fe5b-a199-a2b56b7019ee
    HA Enabled               false
    ```

1. Explorer the Vault configuration file

    ```plaintext
    $ cat /etc/vault.d/config.hcl

    storage "file" {
      path = "/opt/vault"
    }
    listener "tcp" {
      address     = "0.0.0.0:8200"
      tls_disable = 1
    }
    seal "azurekeyvault" {
      client_id      = "YOUR-AZURE-APP-ID"
      client_secret  = "YOUR-AZURE-APP-PASSWORD"
      tenant_id      = "YOUR-AZURE-TENANT-ID"
      vault_name     = "Test-vault-xxxx"
      key_name       = "generated-key"
    }
    ui=true
    disable_mlock = true
    ```

## Azure Auth Method

The `azure` auth method allows authentication against Vault using Azure Active Directory credentials.

1. First, log into Vault using the generated initial root token:

    ```plaintext
    $ vault login s.bRyEk2vIPrKfeldFZD5xFvUL
    ```

1. Explorer the `/tmp/azure_auth.sh` file

    ```plaintext
    $ cat /tmp/azure_auth.sh
    ```

    This script performs the following:

    - Enable the Azure auth method at `azure`
    - Configure the Azure auth method
    - Create a role named `dev-role` with `default` policy
    - Finally, log into Vault using as `dev-role` to obtain a Vault client token

1. Execute the script

    ```plaintext
    $ ./azure_auth.sh

     ...

    Key                  Value
    ---                  -----
    token                s.kjS8K4VrrpejH1kuYKdqpdEG
    token_accessor       iawFjCWPnVEowHIu9VRZ0yU0
    token_duration       768h
    token_renewable      true
    token_policies       ["default"]
    identity_policies    []
    policies             ["default"]
    token_meta_role      dev-role
    ```

    A valid service token is generated.


## Azure Secrets Engine

Vault Azure secrets engine dynamically generate Azure service principals and role assignments. Vault roles can be mapped to one or more Azure roles, or generate a new secret for an existing service principal. 

1. Be sure to log into Vault using the generated initial root token:

    ```plaintext
    $ vault login s.bRyEk2vIPrKfeldFZD5xFvUL
    ```

1. I haven't quite figure this out, but `main.tf` fails to pull out the correct object ID.  So, you have to manually replace this value in the `/tmp/azure_secret.sh` file.  Go to [**Azure Portal**](https://portal.azure.com/#blade/Microsoft_AAD_IAM/ApplicationsListBlade) and find a generated app named, **`yh-azure-test`** and copy its **Object ID** (NOT the Application ID).

1. Repace the object ID in `/tmp/azure_secret.sh`:

    ```plaintext
    $ cd /tmp
    $ sudo vi azure_secret.sh

    ...
    vault write azure/roles/my-role ttl=1h application_object_id=<REPLACE_THIS>
    ...
    ```

1. Execute the script

    ```plaintext
    $ ./azure_secret.sh

    Success! Enabled the azure secrets engine at: azure/
    Success! Data written to: azure/config
    Success! Data written to: azure/roles/my-role
    Success! Data written to: azure/roles/reader-role
    ```

1. Generate a new credential for `my-role`

    ```plaintext
    $ vault read azure/creds/my-role

    Key                Value
    ---                -----
    lease_id           azure/creds/my-role/GTKS2xaqAVyKjZ8p4xSOJf85
    lease_duration     1h
    lease_renewable    true
    client_id          b4407306-8386-4dd4-893b-e140eb57a036
    client_secret      08dabc6c-0d09-2763-7775-eaf7049c35a7
    ```

    In this example, I already have an existing service principal (`[env]-test-sp`). The Azure secrets engine dynamically genrates a new password which is good for 1 hour.

1. Generate a new credential for `reader-role`

    ```plaintext
    $ vault read azure/creds/reader-role
    Key                Value
    ---                -----
    lease_id           azure/creds/reader-role/YYUOnTAlpOYALwSEFX0U7Dwt
    lease_duration     1h
    lease_renewable    true
    client_id          95d50df6-2dbe-4c8d-9880-ff9f59dd1c97
    client_secret      d4a4f2f6-276f-bcb4-cc9c-e199414a6efd
    ```

    Instad, the `reader-role` is based on Azure's built-in role, "Reader" scoped to my subscription. Therefore, Azure secrets engine dynamically generates a service principal which is valid for 1 hour. 

1.  Revoke the generated credentials

    ```plaintext
    $ vault lease revoke -prefix azure/creds
    All revocation operations queued successfully! 
    ```

    This is good to show that Vault provides a break-glass procedure if a suspicious activity was detected.

## Clean up

When you are done exploring, run `terraform destroy`

```plaintext
$ terraform destroy -auto-approve

$ rm -rf .terraform terraform.tfstate*
```
