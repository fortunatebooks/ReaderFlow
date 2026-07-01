XCODEGEN ?= xcodegen
SCHEME ?= ReaderFlow
DESTINATION ?= platform=iOS Simulator,name=iPhone 16

.PHONY: generate build test clean

generate:
	$(XCODEGEN) generate

build:
	xcodebuild -scheme $(SCHEME) -destination '$(DESTINATION)' build

test:
	xcodebuild -scheme $(SCHEME) -destination '$(DESTINATION)' test

clean:
	rm -rf build DerivedData

