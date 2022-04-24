package main

import (
	"fmt"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
)

type Counter struct {
	counter int
}

func (counter *Counter) Increment() error {
	counter.counter++
	return nil
}

func ThrowError() error {
	return fmt.Errorf("DebouncerTestError")
}

func TestDebouncerDebouncesCalls(t *testing.T) {
	t.Parallel()

	counter := &Counter{}
	debounced, errChan := debounceNoArgsFunc(getProjectLogger(), 1*time.Second, counter.Increment)

	// Repeatedly call the debounced function in a tight loop, then wait the debounced time, and verify that Increment
	// was only called once.
	for i := 0; i < 10; i++ {
		debounced()
	}
	// 1 more second than debounce interval
	time.Sleep(2 * time.Second)
	assert.Equal(t, 1, counter.counter)

	select {
	case err := <-errChan:
		assert.NoError(t, err)
	case <-time.After(5 * time.Second):
		t.Fatalf("Timed out waiting for response from debounced function")
	}
}

func TestDebouncerReturnsError(t *testing.T) {
	t.Parallel()

	debounced, errChan := debounceNoArgsFunc(getProjectLogger(), 1*time.Second, ThrowError)
	debounced()
	// 1 more second than debounce interval
	time.Sleep(2 * time.Second)

	select {
	case err := <-errChan:
		assert.Error(t, err)
		assert.Equal(t, "DebouncerTestError", err.Error())
	case <-time.After(5 * time.Second):
		t.Fatalf("Timed out waiting for response from debounced function")
	}
}

func TestDebouncerResetsAfterSuccess(t *testing.T) {
	t.Parallel()

	counter := &Counter{}
	debounced, _ := debounceNoArgsFunc(getProjectLogger(), 1*time.Second, counter.Increment)
	debounced()
	// 1 more second than debounce interval
	time.Sleep(2 * time.Second)
	assert.Equal(t, 1, counter.counter)

	// Call debounced again now that it successfully ran to completion, and verify it calls the function again.
	debounced()
	// 1 more second than debounce interval
	time.Sleep(2 * time.Second)
	assert.Equal(t, 2, counter.counter)
}
