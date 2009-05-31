NAME=zipview
VERSION=1.0
DESTDIR=$(NAME)-$(VERSION)
SOURCES=zipview.vala archive.vapi
CCFLAGS=-X -larchive

$(NAME): $(SOURCES)
	valac $(VALACFLAGS) -o $(NAME) --pkg gtk+-2.0 $(CCFLAGS) $(SOURCES)

install: $(NAME)
	install -D -o root -g root -s $(NAME) $(DESTDIR)/usr/bin/$(NAME)

clean:
	/bin/rm -f $(NAME)
