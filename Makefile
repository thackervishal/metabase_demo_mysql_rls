.PHONY: start stop reset

start:
	@bash scripts/start.sh

stop:
	docker compose stop

reset:
	docker compose down -v
	rm -f .mysql-seeded
