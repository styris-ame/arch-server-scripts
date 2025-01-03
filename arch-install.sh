#!/bin/bash

# Define color codes
PURPLE="\033[1;35m"
ORANGE="\033[1;33m"
RESET="\033[0m"

# Print the styled text
echo -e "${PURPLE}╔═════════════════════════════════════════╗${RESET}"
echo -e "${PURPLE}║${RESET} ${ORANGE}       Arch Server Install Script      ${RESET} ${PURPLE}║${RESET}"
echo -e "${PURPLE}╚═════════════════════════════════════════╝${RESET}"

echo ""

echo -n "${ORANGE}[1/6]${RESET} "; read -p "Enter desired root password: " root_password
echo -n "${ORANGE}[1/6]${RESET} "; read -p "Enter desired user username: " user_username
echo -n "${ORANGE}[1/6]${RESET} "; read -p "Enter desired user password: " user_password

echo -n "${ORANGE}[1/6]${RESET} "; read -p "Enter desired hostname: " hostname
echo -n "${ORANGE}[1/6]${RESET} "; read -p "Enter desired IP address: " ip_address
echo -n "${ORANGE}[1/6]${RESET} "; read -p "Enter desired default gateway: " default_gateway



INTERFACE=$(ip route | grep '^default' | awk '{print $5}')

DISK=/dev/$(lsblk -dn -o NAME,SIZE --sort SIZE | tail -n1 | cut -d ' ' -f1)

sgdisk --zap-all $DISK
# Create GPT partition table
sgdisk -o $DISK
# Create EFI system partition (1GB)
sgdisk -n 1:2048:+1G -t 1:EF00 -c 1:"EFI System" $DISK
# Create root partition (remaining disk space)
sgdisk -n 2:0:0 -t 2:8300 -c 2:"Root" $DISK

mkfs.ext4 ${DISK}2
mkfs.fat -F 32 ${DISK}1

mount ${DISK}2 /mnt
mount --mkdir ${DISK}1 /mnt/boot

mkswap -U clear --size 4G --file /mnt/swapfile

pacstrap -K /mnt base linux linux-firmware nano man-db man-pages texinfo openssh git base-devel

genfstab -U /mnt >> /mnt/etc/fstab

echo "/swapfile none swap defaults 0 0" >> /mnt/etc/fstab

arch-chroot /mnt

ln -sf /usr/share/zoneinfo/America/Los_Angeles /etc/localtime

hwclock --systohc

systemctl enable sshd
systemctl enable systemd-timesyncd
systemctl enable systemd-networkd
systemctl enable systemd-resolved
ln -sf ../run/systemd/resolve/stub-resolv.conf /etc/resolv.conf

sed -i '/#en_US.UTF-8 UTF-8/s/^#//' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" >> /etc/locale.conf

sed -i 's/^#SystemMaxUse=.*$/SystemMaxUse=10M/' /etc/systemd/journald.conf
sed -i 's/^#MaxRetentionSec=0.*$/MaxRetentionSec=3month/' /etc/systemd/journald.conf

echo "${hostname}" >> /etc/hostname

echo "[Match]" >> /etc/systemd/network/20-wired.network
echo "Name=${INTERFACE}" >> /etc/systemd/network/20-wired.network
echo "" >> /etc/systemd/network/20-wired.network
echo "[Network]" >> /etc/systemd/network/20-wired.network
echo "Address=${ip_address}/24" >> /etc/systemd/network/20-wired.network
echo "Gateway=${default_gateway}" >> /etc/systemd/network/20-wired.network
echo "DNS=1.0.0.1,8.8.4.4" >> /etc/systemd/network/20-wired.network

mkinitcpio -P

echo "root:${root_password}" | chpasswd

printf '%s' "$(cat <<'EOF'
#
# ~/.bashrc
#

# If not running interactively, don't do anything
case $- in
    *i*) ;;
      *) return;;
esac

# don't put duplicate lines or lines starting with space in the history.
# See bash(1) for more options
HISTCONTROL=ignoreboth

# append to the history file, don't overwrite it
shopt -s histappend

# for setting history length see HISTSIZE and HISTFILESIZE in bash(1)
HISTSIZE=1000
HISTFILESIZE=2000

# check the window size after each command and, if necessary,
# update the values of LINES and COLUMNS.
shopt -s checkwinsize

# If set, the pattern "**" used in a pathname expansion context will
# match all files and zero or more directories and subdirectories.
#shopt -s globstar

# make less more friendly for non-text input files, see lesspipe(1)
[ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)"

# set variable identifying the chroot you work in (used in the prompt below)
if [ -z "${debian_chroot:-}" ] && [ -r /etc/debian_chroot ]; then
    debian_chroot=$(cat /etc/debian_chroot)
fi

# set a fancy prompt (non-color, unless we know we "want" color)
case "$TERM" in
    xterm-color|*-256color) color_prompt=yes;;
esac

# uncomment for a colored prompt, if the terminal has the capability; turned
# off by default to not distract the user: the focus in a terminal window
# should be on the output of commands, not on the prompt
#force_color_prompt=yes

if [ -n "$force_color_prompt" ]; then
    if [ -x /usr/bin/tput ] && tput setaf 1 >&/dev/null; then
        # We have color support; assume it's compliant with Ecma-48
        # (ISO/IEC-6429). (Lack of such support is extremely rare, and such
        # a case would tend to support setf rather than setaf.)
        color_prompt=yes
    else
        color_prompt=
    fi
fi

if [ "$color_prompt" = yes ]; then
    PS1='${debian_chroot:+($debian_chroot)}\[\033[01;36m\]\u@\h\[\033[00m\]:\[\033[01;33m\]\w\[\033[00m\]\$ '
else
    PS1='${debian_chroot:+($debian_chroot)}\u@\h:\w\$ '
fi
unset color_prompt force_color_prompt

# If this is an xterm set the title to user@host:dir
case "$TERM" in
xterm*|rxvt*)
    PS1="\[\e]0;${debian_chroot:+($debian_chroot)}\u@\h: \w\a\]$PS1"
    ;;
*)
    ;;
esac

# enable color support of ls and also add handy aliases
if [ -x /usr/bin/dircolors ]; then
    test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
    alias ls='ls --color=auto'
    #alias dir='dir --color=auto'
    #alias vdir='vdir --color=auto'

    alias grep='grep --color=auto'
    alias fgrep='fgrep --color=auto'
    alias egrep='egrep --color=auto'
fi

# some more ls aliases
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
EOF
)" > /etc/skel/.bashrc

useradd -m -G wheel "${user_username}"
echo "${user_username}:${user_password}" | chpasswd
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

git clone https://aur.archlinux.org/yay.git
cd yay
makepkg -s
pacman -U --noconfirm *.pkg.tar.zst
cd ..
rm -rf yay

printf '%s' "$(cat <<'EOF'
#!/bin/bash

cleanup() {
  rm -rf /root/arch-install.sh
}

trap cleanup EXIT

sed -i '$d; $d' /etc/profile

# Define color codes
PURPLE="\033[1;35m"
ORANGE="\033[1;33m"
RESET="\033[0m"

# Print the styled text
echo -e "${PURPLE}╔═════════════════════════════════════════╗${RESET}"
echo -e "${PURPLE}║${RESET} ${ORANGE}    Arch Server Post-Install Script    ${RESET} ${PURPLE}║${RESET}"
echo -e "${PURPLE}╚═════════════════════════════════════════╝${RESET}"
echo ""

prompt() {
  local prompt="$1"
  local response
  while true; do
    read -n 1 -s -p "$prompt (Y/N): " response
    response=$(echo "$response" | tr '[:lower:]' '[:upper:]')
    echo "$response"
    if [[ "$response" == "Y" ]]; then
      return 0  # True
    elif [[ "$response" == "N" ]]; then
      return 1  # False
    else
      echo "Invalid response. Please enter Y or N."
    fi
  done
}

if prompt "Install Cockpit?"; then
  echo "Installing Cockpit..."
  yay -Syu cockpit cockpit-packagekit networkmanager firewalld udisks2 cockpit-storaged
  systemctl enable --now cockpit.socket
fi

sleep 5

clear

echo "Install complete!"
exit 0

EOF
)" >> /root/arch-install.sh

chmod +x /root/arch-install.sh

echo "" >> /etc/profile
echo "echo '${user_password}' | sudo -S bash '/root/arch-install.sh'" >> /etc/profile

exit

umount -R /mnt

efibootmgr --create --disk "${DISK}" --part 1 --label "Arch Linux" --loader /vmlinuz-linux --unicode "root=UUID=$(blkid -s UUID -o value ${DISK}2) rw initrd=\initramfs-linux.img"