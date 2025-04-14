package main

import (
	"fmt"
	"log"
	"os/exec"
	"time"

	"github.com/holoplot/go-evdev"
)

const (
	powerKeyCode   = 116 // KEY_POWER
	shortPressMax  = 2 * time.Second
	devicePath     = "/dev/input/event1" // Change this to the actual device
	suspendScript  = "../start-suspend"
	shutdownScript = "../start-shutdown"
)

func main() {
	dev, err := evdev.Open(devicePath)
	if err != nil {
		log.Fatalf("Failed to open input device: %v", err)
	}
	fmt.Printf("Listening on device: %s (%s)\n", dev.Name, devicePath)

	var pressTime time.Time
	for {
		event, err := dev.ReadOne()
		if err != nil {
			log.Printf("Failed to read input: %v", err)
			continue
		}

		if event.Type == evdev.EV_KEY && event.Code == powerKeyCode {
			if event.Value == 1 {
				// Key pressed
				pressTime = time.Now()
				fmt.Println("Power button pressed")
			} else if event.Value == 0 && !pressTime.IsZero() {
				// Key released
				duration := time.Since(pressTime)
				pressTime = time.Time{} // Reset
				fmt.Printf("Power button released after %v\n", duration)

				if duration < shortPressMax {
					fmt.Println("Short press detected, suspending...")
					runScript(suspendScript)
				} else {
					fmt.Println("Long press detected, shutting down...")
					runScript(shutdownScript)
				}
			}
		}
	}
}

func runScript(scriptPath string) {
	fmt.Printf("Running script: %s\n", scriptPath)
	cmd := exec.Command(scriptPath)
	if err := cmd.Run(); err != nil {
		log.Printf("Failed to run %s script: %v", scriptPath, err)
	}
}
