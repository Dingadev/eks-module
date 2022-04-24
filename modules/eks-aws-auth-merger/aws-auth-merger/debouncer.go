package main

import (
	"time"

	"github.com/sirupsen/logrus"
)

const (
	chanBuffer = 10
)

// debounce will hold calling the given function until a set interval has passed without being called. This will return
// the debounced function which can be called to schedule the debounced call. Note that the call immediately returns,
// relying on the paired error channel to receive results.
// Inspired by https://github.com/bep/debounce/blob/master/debounce.go, with modification to handle errors
func debounceNoArgsFunc(logger *logrus.Logger, interval time.Duration, funcToCall func() error) (func(), chan error) {
	var timer *time.Timer
	errChan := make(chan error, chanBuffer)
	debounced := func() {
		// On first call, timer is not set so we schedule to call the function at a later time. On subsequent calls, if
		// the timer has not fired yet, this will stop the existing timer and reschedule a new function.
		if timer != nil {
			timer.Stop()
		}
		timer = time.AfterFunc(interval, func() {
			logger.Debug("No additional requests came in in the set interval for debouncer. Calling function.")
			errChan <- funcToCall()
		})
	}
	return debounced, errChan
}
