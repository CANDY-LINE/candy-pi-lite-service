PI_HOST ?= raspberrypi.local
PI_USER ?= pi

deploy:
	./install.sh pack && \
	scp ./candy-pi-lite-service-*.tgz $(PI_USER)@$(PI_HOST):~

clean:
	rm -f *.dtbo *.tgz
