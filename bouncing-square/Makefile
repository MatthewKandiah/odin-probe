OUT = bouncing-square

build: build-shaders build-main

run: build
	./$(OUT)

build-main:
	odin build main -out:$(OUT)

build-shaders:
	glslc shaders/shader.vert -o vert.spv
	glslc shaders/shader.frag -o frag.spv

clean:
	rm ./*.spv
	rm $(OUT)
