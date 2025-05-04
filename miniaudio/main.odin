package main

import "core:fmt"
import "core:os"
import ma "vendor:miniaudio"

filename :: "beep.wav"

main :: proc() {
	if !os.exists(filename) {
		fmt.println("file", filename, "exists")
	}

	engine: ma.engine
	if res := ma.engine_init(nil, &engine); res != .SUCCESS {
		panic("failed to init")
	}

	if res := ma.engine_play_sound(&engine, filename, nil); res != .SUCCESS {
		panic("failed to play")
	}

  for {
    // loop so async play function has time to act
  }
}
