Удобный набор скриптов для развёртывания Telegram MTProxy через связку:

EU сервер — основной сервер с MTProxy
RU сервер — входная точка для клиентов, которая пересылает трафик на EU через socat
Схема подходит для случаев, когда нужно, чтобы пользователи подключались к RU серверу, а реальный MTProxy работал на EU сервере.

Содержание
Как это работает
Архитектура
Быстрый старт
Скрипты
Команды запуска
Повторный запуск меню RU
Возможности RU-менеджера
Где хранятся данные
Пример работы
Требования
Важно
Как это работает
В этой схеме используются два сервера.

EU сервер
На EU сервере запускается основной MTProxy.

Именно он обрабатывает трафик Telegram.

RU сервер
RU сервер принимает подключения от клиентов и пересылает TCP-трафик на EU сервер через socat.

Итоговый маршрут выглядит так:

text

Telegram Client -> RU Server -> EU Server (MTProxy)
То есть пользователь подключается не напрямую к EU, а к RU.

Архитектура
text

+-------------------+        +-------------------+        +----------------------+
| Telegram Client   | -----> | RU Server         | -----> | EU Server            |
| tg://proxy link   |        | socat port relay  |        | MTProxy              |
+-------------------+        +-------------------+        +----------------------+
Что получает клиент
Клиент получает Telegram-ссылку вида:

text

tg://proxy?server=RU_IP&port=RU_PORT&secret=SECRET
Где:

RU_IP — IP RU сервера
RU_PORT — порт на RU сервере
SECRET — secret MTProxy, который использует EU сервер
Быстрый старт
1. Установить EU сервер
bash

bash <(curl -fsSL https://raw.githubusercontent.com/evgen1114/tgproxy-manager/main/install.sh)
2. Запустить RU менеджер
bash

bash <(curl -fsSL https://raw.githubusercontent.com/evgen1114/tgproxy-manager/main/ru.sh)
3. Через меню RU создать клиента
Нужно будет указать:

имя клиента
EU IP
EU PORT
SECRET
RU PORT
После этого скрипт:

создаст systemd-сервис
поднимет TCP-forward через socat
сохранит клиента в базу
покажет ссылку
сгенерирует QR-код
Скрипты
install.sh
Скрипт для установки и настройки EU сервера.

Назначение:

подготовка сервера
установка MTProxy
запуск основного прокси
настройка работы EU стороны
ru.sh
Скрипт для управления RU сервером.

Назначение:

установка зависимостей
создание клиентов
проброс портов на EU
генерация Telegram-ссылок
генерация QR-кодов
управление systemd-сервисами
Команды запуска
Установка / запуск EU скрипта
bash

bash <(curl -fsSL https://raw.githubusercontent.com/evgen1114/tgproxy-manager/main/install.sh)
Запуск RU менеджера напрямую с GitHub
bash

bash <(curl -fsSL https://raw.githubusercontent.com/evgen1114/tgproxy-manager/main/ru.sh)
Повторный запуск меню RU
Если ты уже скачал ru.sh на сервер и хочешь запускать меню повторно локально, можно сделать так:

Сначала скачать файл
bash

curl -fsSL https://raw.githubusercontent.com/evgen1114/tgproxy-manager/main/ru.sh -o /root/ru.sh
Сделать исполняемым
bash

chmod +x /root/ru.sh
Запускать меню в любой момент
bash

bash /root/ru.sh
или:

bash

/root/ru.sh
Возможности RU-менеджера
После запуска ru.sh откроется меню:

text

1. Создать клиента
2. Список клиентов
3. Показать ссылку и QR клиента
4. Удалить клиента
5. Статус сервисов
0. Выход
1. Создать клиента
Создаёт нового клиента на RU сервере.

Что делает:

принимает входные данные
создаёт отдельный systemd-сервис
запускает проброс RU_PORT -> EU_IP:EU_PORT
сохраняет данные клиента
выводит ссылку и QR
2. Список клиентов
Показывает всех созданных клиентов и их маршруты:

text

RU_IP:RU_PORT -> EU_IP:EU_PORT
3. Показать ссылку и QR клиента
Позволяет заново получить:

Telegram-ссылку
QR-код в терминале
PNG-файл QR-кода
4. Удалить клиента
Удаляет:

systemd-сервис клиента
запись из базы
PNG QR-кода
5. Статус сервисов
Показывает статус systemd для каждого клиента.

Где хранятся данные
На RU сервере используется директория:

text

/opt/mtproxy-bridge
База клиентов
text

/opt/mtproxy-bridge/clients.db
QR-коды
text

/opt/mtproxy-bridge/qrcodes
systemd unit-файлы
text

/etc/systemd/system/mtproxy-forward-CLIENT.service
Принцип работы RU-скрипта
Для каждого клиента создаётся отдельный сервис вида:

text

mtproxy-forward-CLIENT.service
Этот сервис запускает примерно такую логику:

text

socat TCP-LISTEN:RU_PORT,fork,reuseaddr TCP:EU_IP:EU_PORT
То есть:

RU сервер слушает порт RU_PORT
каждое входящее соединение пересылается на EU_IP:EU_PORT
Пример:

text

RU 5.6.7.8:443 -> EU 1.2.3.4:3443
Пример работы
Допустим у тебя есть:

EU IP: 1.2.3.4
EU PORT: 3443
RU IP: 5.6.7.8
RU PORT: 443
SECRET: eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
Тогда клиенту выдаётся ссылка:

text

tg://proxy?server=5.6.7.8&port=443&secret=eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
Фактический маршрут трафика:

text

5.6.7.8:443 -> 1.2.3.4:3443
Типовой сценарий использования
Шаг 1. Поднять EU
bash

bash <(curl -fsSL https://raw.githubusercontent.com/evgen1114/tgproxy-manager/main/install.sh)
Шаг 2. Запустить RU менеджер
bash

bash <(curl -fsSL https://raw.githubusercontent.com/evgen1114/tgproxy-manager/main/ru.sh)
Шаг 3. Создать клиента через меню
Указать:

имя клиента
IP EU сервера
порт EU
secret
порт RU
Шаг 4. Отдать пользователю ссылку или QR
Требования
Для EU сервера
Linux
root-доступ
доступ в интернет
Для RU сервера
Linux
root-доступ
systemd
доступ в интернет
пакетный менеджер: apt, dnf или yum
Важно
На RU сервере должны быть открыты клиентские порты.
RU сервер должен иметь доступ к EU серверу по нужному порту.
SECRET должен совпадать с secret, который использует MTProxy на EU сервере.
Если включён firewall, нужно разрешить входящие подключения на RU PORT.
RU сервер не запускает MTProxy, он только пересылает трафик на EU.
Полезно знать
Быстрый запуск RU без сохранения файла
bash

bash <(curl -fsSL https://raw.githubusercontent.com/evgen1114/tgproxy-manager/main/ru.sh)
Сохранить RU-скрипт локально и запускать меню вручную
bash

curl -fsSL https://raw.githubusercontent.com/evgen1114/tgproxy-manager/main/ru.sh -o /root/ru.sh
chmod +x /root/ru.sh
bash /root/ru.sh
FAQ
RU сервер поднимает MTProxy?
Нет.

RU сервер только делает TCP-forward через socat.

Где реально работает прокси?
На EU сервере.

Что указывать пользователю?
Пользователю нужно отдавать:

RU IP
RU PORT
SECRET
Можно ли создать несколько клиентов?
Да.

Для каждого клиента можно создать отдельный порт и отдельный systemd-сервис.

