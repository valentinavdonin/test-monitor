# test-monitor (process -> https ping + restart log)

## Описание

**test-monitor** - инструмент для мониторинга процессов в Linux.  
По умолчанию он отслеживает процесс `test` и раз в минуту:
- проверяет, запущен ли процесс;
- если процесс работает — отправляет HTTPS-запрос на `https://test.com/monitoring/test/api`;
- фиксирует **перезапуск процесса** (по времени старта из `/proc/<pid>/stat`) и пишет в лог `/var/log/monitoring.log`;
- при недоступности сервера мониторинга также добавляет запись в лог.

Мониторинг реализован как скрипт на `bash` и юниты `systemd` (oneshot + timer).  
Запуск обеспечивается через `systemd`-таймер с периодичностью 1 минута и автозапуском при старте системы.

### Основные возможности
- ⏱ Ежеминутная проверка через `systemd`-таймер (`OnCalendar=*-*-* *:*:00`, `Persistent=true`).
- 🔎 Надёжное определение перезапуска по `starttime` (поле 22 в `/proc/<pid>/stat`) в рамках одного `boot_id`.
- 🌐 HTTPS-пинг сервера мониторинга только при реально работающем процессе.
- 🧾 Логирование событий: перезапуск процесса и недоступность эндпоинта в `/var/log/monitoring.log`.
- ⚙️ Конфигурация через `/etc/test-monitor/test-monitor.env`.
- 🔒 Харденинг systemd: `NoNewPrivileges`, `PrivateTmp`, `ProtectSystem=full`; запись разрешена только в нужные каталоги.
- 🧰 Установка одной командой: `make install`.

## Установка

Требования: Linux с systemd, `curl`, права root.

```bash
git clone <your-remote-or-path> test-monitor
cd test-monitor
sudo make install
```

Пути установки по умолчанию:
- Cкрипт: `/usr/local/bin/test-monitor.sh`
- Юниты: `/etc/systemd/system/test-monitor.service` и `/etc/systemd/system/test-monitor.timer`
- Конфиг: `/etc/test-monitor/test-monitor.env`
- State: `/var/lib/test-monitor/`
- Лог: `/var/log/monitoring.log`
- Logrotate: `/etc/logrotate.d/test-monitor`

Переопределить префиксы можно так:
```bash
sudo make PREFIX=/opt install
```

## Настройка

Отредактируйте `/etc/test-monitor/test-monitor.env` (создаётся при установке):
```bash
PROC_NAME=test
MONITOR_URL=https://test.com/monitoring/test/api
# STATE_DIR=/var/lib/test-monitor
# LOG_FILE=/var/log/monitoring.log
# LOCK_FILE=/run/lock/test-monitor.lock
```

Перечитайте юниты:
```bash
sudo systemctl daemon-reload
sudo systemctl restart test-monitor.timer
```

## Проверка

```bash
systemctl status test-monitor.timer
sudo systemctl start test-monitor.service      # разовый запуск
sudo tail -n 50 /var/log/monitoring.log
journalctl -u test-monitor.service --since "10 min ago"
```

### Как протестировать без реального процесса `test`

Создайте процесс с именем `test`:
```bash
bash -c 'exec -a test sleep infinity' &
echo $!   # PID
```

Через минуту скрипт отработает, увидит процесс и постучится на мониторинг.  
Теперь «перезапустим» процесс:
```bash
pkill -f '^test$'
bash -c 'exec -a test sleep infinity' &
```

В `/var/log/monitoring.log` появится запись о перезапуске.

## Удаление

```bash
sudo make uninstall
# При желании вручную удалить:
#   sudo rm -rf /etc/test-monitor /var/lib/test-monitor /var/log/monitoring.log
```

## Безопасность

Юнит запускается как `root`, но с усилениями (`NoNewPrivileges`, `ProtectSystem=full`, `PrivateTmp`).  
Запись разрешена только в: `/var/lib/test-monitor`, `/var/log/monitoring.log`, `/run/lock`.

## Лицензия
MIT
