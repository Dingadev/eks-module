package main

import "github.com/gruntwork-io/gruntwork-cli/entrypoint"

func main() {
	app := newApp()
	entrypoint.RunApp(app)
}
