package main

import (
	"fmt"
	"log"
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
					//exec.Command(suspendScript).Run()
				} else {
					fmt.Println("Long press detected, shutting down...")
					//exec.Command(shutdownScript).Run()
				}
			}
		}
	}
}
