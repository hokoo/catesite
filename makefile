setup.all:
	bash ./install/setup.sh

setup.wp:
	bash ./install/setup-wp.sh

setup.env:
	bash ./install/setup-env.sh

clear.all:
	bash ./install/clear.sh

docker.up:
	docker-compose up -d

docker.stop:
	docker-compose stop

docker.down:
	docker-compose down
	
connect.php:
	docker-compose exec php bash

connect.nginx:
	docker-compose exec nginx sh

connect.php.root:
	docker-compose exec --user=root php bash
