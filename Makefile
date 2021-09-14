up:
	docker compose up
down:
	docker compose down
mythtv:
	docker build -t mythtv -f Dockerfile.backend . 
mythweb:
	docker build -t mythweb -f Dockerfile.mythweb .

