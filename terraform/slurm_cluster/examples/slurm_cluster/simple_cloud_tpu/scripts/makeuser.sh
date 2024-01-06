#!/bin/bash
set -ex

cat > /slurm/scripts/makeuser.sh <<FILE

# Root does not need SSH key generation
[ \${PAM_USER} == "root" ] && exit 0

# The home directory for every user must be determined in the most generic way because
# we should not assume that every user has its home directory in /home/\$USER.
user_home_dir="\$(getent passwd \${PAM_USER} | cut -d ':' -f 6)"

if [ ! -d "\${user_home_dir}" ]; then
    mkdir -p \${user_home_dir}
    chmod -R 0750 \${user_home_dir}
    chown \${PAM_USER}:$(id -g \${PAM_USER}) -R \${user_home_dir}
fi

# Skip SSH key creation if the SSH has been already configured for the user.
# We assume that SSH has been already configured if the directory .ssh already exists in the user home.
user_ssh_dir="\${user_home_dir}/.ssh"
[ -d "\${user_ssh_dir}" ] && exit 0

mkdir -p -m 0700 "\${user_ssh_dir}"
ssh-keygen -q -t ed25519 -f "\${user_ssh_dir}/id_ed25519" -N ''
cat "\${user_ssh_dir}/id_ed25519.pub" >> "\${user_ssh_dir}/authorized_keys"

chmod 0600 "\${user_ssh_dir}/authorized_keys"

cat <<EOF >>\${user_ssh_dir}/config
Host *
    ForwardAgent yes
    IdentitiesOnly yes
    IdentityFile ~/.ssh/sai_ed25519
    StrictHostKeyChecking no
    UserKnownHostsFile=/dev/null
EOF
chown \${PAM_USER}:$(id -g \${PAM_USER}) -R "\${user_ssh_dir}"
FILE

chmod +x /slurm/scripts/makeuser.sh
echo 'session    optional     pam_exec.so log=/var/log/pam_ssh_key_generator.log /slurm/scripts/makeuser.sh' >> /etc/pam.d/sshd
sed -i 's|/usr/bin/google_authorized_keys|/usr/bin/sss_ssh_authorizedkeys|g' /etc/ssh/sshd_config

systemctl restart sshd
