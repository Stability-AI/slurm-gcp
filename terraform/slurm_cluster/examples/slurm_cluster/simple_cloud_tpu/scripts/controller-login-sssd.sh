#!/bin/bash
set -x
set -e
set -o pipefail

echo "Setup sssd connection to Active Directory via LDAP on `hostname`"

sshd_config_file="/etc/ssh/sshd_config"

if [ -d "/etc/sssd" ]
then
        echo "Found sssd directory. Proceeding..."
else
        echo "sssd configuration directory not found."
        sudo mkdir -p /etc/sssd
fi

cat > /etc/sssd/sssd.conf << EOF
[domain/default]
cache_credentials = True
default_shell = /bin/bash
enumerate = true
override_homedir = /home/%u
id_provider = ldap
ldap_default_authtok = BX9fK~z3tjmR[d#F\$Vnx2-
ldap_default_bind_dn = cn=ReadOnlyUser,ou=AD-Manage,dc=research,dc=stability,dc=ai
ldap_id_mapping = True
ldap_referrals = False
ldap_schema = AD
ldap_search_base = dc=research,dc=stability,dc=ai?subtree?(&(!(objectClass=computer))(!(userAccountControl:1.2.840.113556.1.4.803:=2)))
ldap_id_use_start_tls = false
ldap_tls_reqcert = never
ldap_uri = ldap://10.100.20.21:389
ldap_user_extra_attrs = altSecurityIdentities:altSecurityIdentities
ldap_user_ssh_public_key = altSecurityIdentities
use_fully_qualified_names = False
debug_level=10
#access_provider = simple
#simple_allow_groups = devops

[sssd]
config_file_version = 2
services = nss, pam, ssh
domains = default
full_name_format = %1\$s
debug_level=10

[nss]
filter_users = nobody,root
filter_groups = nobody,root
debug_level=10

[pam]
offline_credentials_expiration = 7
debug_level=10
EOF
sudo chmod 0600 /etc/sssd/sssd.conf

sudo systemctl restart sssd

echo ""
echo "###################################################"
echo "Step 4: ssh Auth setup"
echo "###################################################"
## Allow password authentication for SSH
sudo sed -i 's/[#]AuthorizedKeysCommand .*/AuthorizedKeysCommand \/usr\/bin\/sss_ssh_authorizedkeys/' $sshd_config_file
sudo sed -i 's/[#]AuthorizedKeysCommandUser .*/AuthorizedKeysCommandUser root/' $sshd_config_file
sudo sed -i 's/[#]PasswordAuthentication .*/PasswordAuthentication no/' $sshd_config_file

#sudo sed -i -e 's/^/#/' $ec2_connect_conf
sudo systemctl daemon-reload

cat > /etc/sudoers.d/100-AD-admins << EOF
# add domain admins as sudoers
%Sudoers  ALL=(ALL) NOPASSWD:ALL
EOF

# restart ssh service
echo "Restarting sshd..."
sudo systemctl restart sshd

echo "AD Setup Completed."