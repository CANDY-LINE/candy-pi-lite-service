PI_HOST ?= raspberrypi.local

deploy:
	./install.sh pack && \
	scp ./candy-pi-lite-service-*.tgz pi@$(PI_HOST):~
