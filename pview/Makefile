NAME=pview
VERSION=0.1
DIR=$(NAME)-$(VERSION)

$(NAME): pview.vala
	valac $(VALACFLAGS) -o pview --pkg gtk+-2.0 pview.vala

install: $(NAME)
	install -D -o root -g root -s $(NAME) $(DESTDIR)/usr/bin/pview

clean:
	/bin/rm -f pview

deb:
	mkdir $(DIR)
	make install DESTDIR=$(DIR)
	mkdir $(DIR)/DEBIAN
	cp control $(DIR)/DEBIAN/control
	dpkg-deb --build $(DIR)
