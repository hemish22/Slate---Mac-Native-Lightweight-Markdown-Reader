.PHONY: build test run install package screenshots clean
build:
	bash Scripts/build.sh
test:
	bash Scripts/test.sh
run: build
	open build/Slate.app
install: build
	bash Scripts/install.sh
package: build
	bash Scripts/package.sh
screenshots: build
	bash Scripts/capture-screenshots.sh
clean:
	rm -rf build
