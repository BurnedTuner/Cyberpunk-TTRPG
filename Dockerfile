FROM node:22-slim AS builder
WORKDIR /usr/src/app
COPY package.json .
COPY package-lock.json* .
RUN npm ci

FROM node:22-slim
WORKDIR /usr/src/app
COPY --from=builder /usr/src/app/ /usr/src/app/
COPY . .

# Установка git и необходимых инструментов
RUN apt-get update && \
    apt-get install -y git cron procps && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Создаем скрипт для проверки и применения обновлений
RUN echo '#!/bin/bash\n\
cd /usr/src/app\n\
git remote update\n\
UPSTREAM=${1:-"@{u}"}\n\
LOCAL=$(git rev-parse @)\n\
REMOTE=$(git rev-parse "$UPSTREAM")\n\
BASE=$(git merge-base @ "$UPSTREAM")\n\
if [ "$LOCAL" != "$REMOTE" ]; then\n\
    git pull\n\
    npx quartz build\n\
fi' > /usr/src/app/update_content.sh && \
    chmod +x /usr/src/app/update_content.sh

# Настраиваем cron для периодического запуска скрипта (каждую минуту)
RUN echo "*/1 * * * * /usr/src/app/update_content.sh >> /var/log/cron.log 2>&1" > /etc/cron.d/content-update-cron && \
    chmod 0644 /etc/cron.d/content-update-cron && \
    crontab /etc/cron.d/content-update-cron && \
    touch /var/log/cron.log

# Создаем скрипт запуска для одновременного запуска cron и сервера
RUN echo '#!/bin/bash\n\
service cron start\n\
echo "Cron service started"\n\
exec npx quartz build --serve' > /usr/src/app/start.sh && \
    chmod +x /usr/src/app/start.sh

CMD ["/usr/src/app/start.sh"]
