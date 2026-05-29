#!/bin/bash

# ==========================================
# ВХОДНЫЕ ДАННЫЕ (ОТРЕДАКТИРУЙ ПОД СЕБЯ)
# ==========================================
NEW_USER="shef"
SSH_PORT="52148"
# Массив публичных ключей (начинаются с ssh-rsa, ssh-ed25519 и т.д.)
SSH_PUB_KEYS=(
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOxSx8pPWCYzrwgwCTiT52B2CN/916GYqtKYsDGi2lqJ vvpn"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHIPOMNzeM+dLIZmcv7GDXRAah22V3yozsEL+eHCfyGj bug"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFOEpAWgbsUE6mcNNHi9tG6hc/QU7CB5yjyhNt201Yl7 proxy"
)

# ==========================================
# НАСТРОЙКА ЛОГИРОВАНИЯ
# ==========================================
TMP_LOG="/root/vps_setup_tmp.log"
FINAL_LOG="/home/$NEW_USER/vps_setup.log"

# Настройка цветов для красивого вывода
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Перенаправляем весь вывод скрипта (stdout и stderr) одновременно в терминал и в файл
exec > >(tee -a "$TMP_LOG") 2>&1

# Функции для логирования
log_info() { echo -e "${CYAN}[i] $1${NC}"; }
log_success() { echo -e "${GREEN}[✔] $1${NC}"; }
log_warn() { echo -e "${YELLOW}[!] $1${NC}"; }
log_error() { echo -e "${RED}[✖] $1${NC}"; }

# ==========================================
# ПРОВЕРКИ ПЕРЕД СТАРТОМ
# ==========================================
if [ "$EUID" -ne 0 ]; then
  log_error "Скрипт должен быть запущен от имени root!"
  exit 1
fi

log_info "=========================================="
log_info "Начинаем первоначальную настройку сервера!"
log_info "Пользователь: $NEW_USER | SSH Порт: $SSH_PORT"
log_info "=========================================="

# ==========================================
# ФАЗА 1: Обновление системы
# ==========================================
log_info "Шаг 1/8: Обновление системы и пакетов..."
# DEBIAN_FRONTEND=noninteractive избавляет от розовых экранов с вопросами в Ubuntu
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt full-upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"
apt-get install -y curl wget nano ufw sudo
log_success "Система успешно обновлена."

# ==========================================
# ФАЗА 2: Создание пользователя и ключей
# ==========================================
log_info "Шаг 2/8: Создание пользователя $NEW_USER..."
if id "$NEW_USER" &>/dev/null; then
    log_warn "Пользователь $NEW_USER уже существует. Пропускаем создание."
else
    useradd -m -s /bin/bash -G sudo "$NEW_USER"
    log_success "Пользователь $NEW_USER создан."
fi

log_info "Настройка SSH-ключей для $NEW_USER..."
USER_HOME="/home/$NEW_USER"
mkdir -p "$USER_HOME/.ssh"

# Записываем все ключи из массива, каждый с новой строки
printf "%s\n" "${SSH_PUB_KEYS[@]}" > "$USER_HOME/.ssh/authorized_keys"

chmod 700 "$USER_HOME/.ssh"
chmod 600 "$USER_HOME/.ssh/authorized_keys"
chown -R "$NEW_USER:$NEW_USER" "$USER_HOME/.ssh"
log_success "SSH-ключи успешно добавлены."

# ==========================================
# ФАЗА 3: Безопасная правка /etc/sudoers
# ==========================================
log_info "Шаг 3/8: Настройка sudoers (беспарольный sudo, удаление includedir)..."
cp /etc/sudoers /tmp/sudoers.tmp
chmod 0640 /tmp/sudoers.tmp

# 1. Даем группе sudo права без пароля
sed -i 's/^%sudo.*/%sudo   ALL=(ALL:ALL) NOPASSWD:ALL/' /tmp/sudoers.tmp
# 2. ПОЛНОСТЬЮ удаляем директиву includedir (т.к. #includedir тоже парсится как директива)
sed -i '/^[#@]includedir/d' /tmp/sudoers.tmp
# 3. Комментируем группу admin (если она есть)
sed -i 's/^%admin/#%admin/' /tmp/sudoers.tmp

# Проверяем синтаксис (ОЧЕНЬ ВАЖНО)
if visudo -c -f /tmp/sudoers.tmp &>/dev/null; then
    cp /tmp/sudoers.tmp /etc/sudoers
    chmod 0440 /etc/sudoers
    log_success "Файл /etc/sudoers успешно и безопасно обновлен."
else
    log_error "Ошибка синтаксиса в sudoers! Изменения отменены."
fi
rm -f /tmp/sudoers.tmp

# ==========================================
# ФАЗА 4: Харденинг SSH
# ==========================================
log_info "Шаг 4/8: Настройка SSH (Смена порта, отключение паролей)..."
SSHD_CONFIG="/etc/ssh/sshd_config"
cp $SSHD_CONFIG "${SSHD_CONFIG}.bak"

# Функция для безопасной замены или добавления параметра в sshd_config
set_ssh_param() {
    local param=$1
    local value=$2
    if grep -q "^[#[:space:]]*$param\b" "$SSHD_CONFIG"; then
        sed -i "s/^[#[:space:]]*$param\b.*/$param $value/" "$SSHD_CONFIG"
    else
        echo "$param $value" >> "$SSHD_CONFIG"
    fi
}

set_ssh_param "Port" "$SSH_PORT"
set_ssh_param "PermitRootLogin" "no"
set_ssh_param "PasswordAuthentication" "no"
set_ssh_param "PermitEmptyPasswords" "no"
set_ssh_param "PubkeyAuthentication" "yes"
set_ssh_param "KbdInteractiveAuthentication" "no"
set_ssh_param "ChallengeResponseAuthentication" "no"

systemctl restart ssh
log_success "SSH настроен и перезапущен на порту $SSH_PORT."

# ==========================================
# ФАЗА 5: Настройка Firewall (UFW)
# ==========================================
log_info "Шаг 5/8: Настройка брандмауэра UFW..."
ufw default deny incoming
ufw default allow outgoing
ufw allow "$SSH_PORT/tcp"
ufw allow 80/tcp
ufw allow 443/tcp
log_success "UFW настроен. Открыты порты: $SSH_PORT, 80, 443. Включение — в конце скрипта."

# ==========================================
# ФАЗА 6: Настройка Fail2ban
# ==========================================
log_info "Шаг 6/8: Установка и настройка Fail2ban..."
apt-get install -y fail2ban

cat <<EOF > /etc/fail2ban/jail.local
[DEFAULT]
ignoreip = 127.0.0.1/8 ::1
bantime = 604800
findtime = 86400
maxretry = 3

[sshd]
enabled = true
port    = $SSH_PORT
backend = systemd
mode    = aggressive
EOF

log_success "Fail2ban настроен. Включение — в конце скрипта."

# ==========================================
# ФАЗА 7: Установка Docker
# ==========================================
log_info "Шаг 7/8: Установка Docker..."
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
usermod -aG docker "$NEW_USER"
rm -f get-docker.sh
log_success "Docker установлен. Пользователь $NEW_USER добавлен в группу docker."

# ==========================================
# ФАЗА 8: Финализация и сохранение логов
# ==========================================
log_info "Шаг 8/8: Завершение работы и перенос логов..."

log_info "Включение UFW и Fail2ban..."
ufw --force enable
systemctl enable fail2ban
systemctl restart fail2ban
log_success "UFW активен. Fail2ban включён в автозагрузку и запущен."

echo -e "\n========================================================================"
log_success "✅ ПЕРВОНАЧАЛЬНАЯ НАСТРОЙКА УСПЕШНО ЗАВЕРШЕНА!"
echo -e "${YELLOW}ВАЖНО:${NC}"
echo -e "1. Сервер сейчас перезагрузится автоматически."
echo -e "2. После reboot проверь подключение:"
echo -e "   ${CYAN}ssh -p $SSH_PORT $NEW_USER@<IP_СЕРВЕРА>${NC}"
echo -e "3. Лог-файл установки: ${CYAN}$FINAL_LOG${NC}"
echo -e "========================================================================\n"

# Восстанавливаем stdout и stderr (закрываем пайп к tee)
exec 1>&- 2>&-
exec 1>/dev/tty 2>&1 # Возвращаем вывод в консоль

# Теперь безопасно переносим лог
sleep 1 # Даем процессу tee миллисекунды на завершение
mv "$TMP_LOG" "$FINAL_LOG"
chown "$NEW_USER:$NEW_USER" "$FINAL_LOG"

log_info "Перезагрузка сервера..."
sleep 3
reboot