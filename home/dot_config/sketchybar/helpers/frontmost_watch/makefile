bin/frontmost_watch: frontmost_watch.m | bin
	clang -O3 -fobjc-arc -framework AppKit -framework CoreGraphics -framework CoreFoundation $< -o $@

bin:
	mkdir bin
