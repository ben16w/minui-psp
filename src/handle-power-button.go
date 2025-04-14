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
	suspendScript  = "/usr/local/bin/suspend.sh"
	shutdownScript = "/usr/local/bin/shutdown.sh"
)

func main() {
	dev, err := evdev.Open(devicePath)
	if err != nil {
		log.Fatalf("Failed to open input device: %v", err)
	}
	fmt.Printf("Listening on device: %s (%s)\n", dev.Name, devicePath)

	var pressTime time.Time
	for {
		events, err := dev.Read()
		if err != nil {
			log.Printf("Failed to read input: %v", err)
			continue
		}

		for _, e := range events {
			if e.Type == evdev.EV_KEY && e.Code == powerKeyCode {
				if e.Value == 1 {
					// Key pressed
					pressTime = time.Now()
					fmt.Println("Power button pressed")
				} else if e.Value == 0 && !pressTime.IsZero() {
					// Key released
					duration := time.Since(pressTime)
					pressTime = time.Time{} // Reset
					fmt.Printf("Power button released after %v\n", duration)

					if duration < shortPressMax {
						fmt.Println("Short press detected, suspending...")
						exec.Command(suspendScript).Run()
					} else {
						fmt.Println("Long press detected, shutting down...")
						exec.Command(shutdownScript).Run()
					}
				}
			}
		}
	}
}
