# galeno-whatsapp — build universal (arm64 + amd64) para macOS.
#
# go-sqlite3 usa cgo (envuelve SQLite en C), así que GOARCH solo no basta: el
# compilador C también tiene que apuntar a la arquitectura destino. El clang
# de Xcode soporta -arch arm64/-arch x86_64 nativamente, así que no hace
# falta un toolchain cruzado aparte — es el patrón estándar para cruzar cgo
# en Mac.

BINARY  := galeno-whatsapp
BIN_DIR := bin

.PHONY: build-arm64 build-amd64 universal clean

build-arm64:
	GOOS=darwin GOARCH=arm64 CGO_ENABLED=1 CC="clang -arch arm64" \
		go build -o $(BIN_DIR)/$(BINARY)-arm64 .

build-amd64:
	GOOS=darwin GOARCH=amd64 CGO_ENABLED=1 CC="clang -arch x86_64" \
		go build -o $(BIN_DIR)/$(BINARY)-amd64 .

universal: build-arm64 build-amd64
	lipo -create -output $(BIN_DIR)/$(BINARY) $(BIN_DIR)/$(BINARY)-arm64 $(BIN_DIR)/$(BINARY)-amd64
	@echo "Universal binary en $(BIN_DIR)/$(BINARY)"
	@file $(BIN_DIR)/$(BINARY)

clean:
	rm -rf $(BIN_DIR)
