# Docker CLI Binary aus dem offiziellen Image holen (kein Daemon, nur Client)
FROM docker:27-cli AS docker-cli

FROM python:3.12-slim

WORKDIR /app

# Docker CLI Binary kopieren — einzige Abhängigkeit für docker exec
COPY --from=docker-cli /usr/local/bin/docker /usr/local/bin/docker

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

EXPOSE 4000

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "4000"]
