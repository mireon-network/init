# init

Первичная настройка VPS (Debian / Ubuntu): обновление, пользователь и SSH-ключи, харденинг SSH, UFW, Fail2ban, Docker.

Перед запуском отредактируй в репозитории `NEW_USER`, `SSH_PORT` и `SSH_PUB_KEYS` в [init.sh](init.sh).

## Установка одной командой / повторный запуск

На сервере под **root**:

```bash
curl -fsSL https://raw.githubusercontent.com/mireon-network/init/main/init.sh | bash
```

Повторный запуск безопасен частично: пользователь не пересоздаётся, конфиги SSH/UFW/Fail2ban и Docker обновятся снова.

## После скрипта

Сервер перезагрузится сам. Когда поднимется — проверь вход:

`ssh -p <SSH_PORT> <NEW_USER>@<IP>`

Лог: `/home/<NEW_USER>/vps_setup.log`

## Требования

- Debian или Ubuntu, доступ в интернет
- Запуск от root (`ssh root@…` или `sudo -i`)
- В `SSH_PUB_KEYS` должен быть твой публичный ключ
