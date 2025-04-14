package main

import (
	"log"
	"os"
	"os/exec"
	"path/filepath"
	"time"

	"github.com/holoplot/go-evdev"
)

const (
	powerKeyCode  = 116 // KEY_POWER
	shortPressMax = 2 * time.Second
	devicePath    = "/dev/input/event1" // Change this to the actual device
)

var (
	binPath, _     = os.Executable()
	pakPath, _     = filepath.Abs(filepath.Dir(filepath.Dir(filepath.Dir(binPath))))
	logFile        = filepath.Join(os.Getenv("LOGS_PATH"), "PSP-power-button")
	suspendScript  = filepath.Join(pakPath, "bin", "suspend")
	shutdownScript = filepath.Join(pakPath, "bin", "shutdown")
)

func main() {
	logFileHandle, err := os.OpenFile(logFile+".log", os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0666)
	if err != nil {
		log.Fatalf("Failed to open log file: %v", err)
	}
	defer logFileHandle.Close()
	log.SetOutput(logFileHandle)

	dev, err := evdev.Open(devicePath)
	if err != nil {
		log.Fatalf("Failed to open input device: %v", err)
	}
	log.Printf("Listening on device: %s\n", devicePath)

	var pressTime time.Time
	var cooldownUntil time.Time

	for {
		event, err := dev.ReadOne()
		if err != nil {
			log.Printf("Failed to read input: %v", err)
			continue
		}

		if time.Now().Before(cooldownUntil) {
			log.Println("Cooldown period active, ignoring event")
			continue
		}

		if event.Type == evdev.EV_KEY && event.Code == powerKeyCode {
			if event.Value == 1 {
				// Key pressed
				pressTime = time.Now()
				log.Println("Power button pressed")
			} else if event.Value == 0 && !pressTime.IsZero() {
				// Key released
				duration := time.Since(pressTime)
				pressTime = time.Time{} // Reset
				log.Printf("Power button released after %v\n", duration)

				if duration < shortPressMax {
					log.Println("Short press detected, suspending...")
					runScript(suspendScript)
					cooldownUntil = time.Now().Add(1 * time.Second)
				} else {
					log.Println("Long press detected, shutting down...")
					runScript(shutdownScript)
				}
			}
		}
	}
}

func runScript(scriptPath string) {
	log.Printf("Running script: %s\n", scriptPath)
	cmd := exec.Command(scriptPath)
	if err := cmd.Run(); err != nil {
		log.Printf("Failed to run %s script: %v", scriptPath, err)
	}
}
