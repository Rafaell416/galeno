package main

import (
	"fmt"
	"os"
	"strings"
	"time"

	waLog "go.mau.fi/whatsmeow/util/log"
)

// stderrLogger mirrors whatsmeow's own waLog.Stdout implementation
// (go.mau.fi/whatsmeow/util/log), but writes to stderr.
//
// Mandatory for "serve": stdout is the MCP stdio transport there, and
// whatsmeow's own package writes its internal logs through whatever Logger
// we hand it — if that were waLog.Stdout, every connection event or
// reconnect would print straight to stdout and corrupt the JSON-RPC stream
// mid-session. Used for all three subcommands, not only "serve", so the
// logging behaves the same everywhere and nobody has to remember which
// subcommand needs which logger.
type stderrLogger struct {
	mod   string
	color bool
	min   int
}

var logColors = map[string]string{
	"INFO":  "\033[36m",
	"WARN":  "\033[33m",
	"ERROR": "\033[31m",
}

var logLevels = map[string]int{
	"":      -1,
	"DEBUG": 0,
	"INFO":  1,
	"WARN":  2,
	"ERROR": 3,
}

// newLogger is our replacement for waLog.Stdout: same signature and
// behavior, except every line goes to os.Stderr.
func newLogger(module string, minLevel string, color bool) waLog.Logger {
	return &stderrLogger{mod: module, color: color, min: logLevels[strings.ToUpper(minLevel)]}
}

func (s *stderrLogger) outputf(level, msg string, args ...interface{}) {
	if logLevels[level] < s.min {
		return
	}
	var colorStart, colorReset string
	if s.color {
		colorStart = logColors[level]
		colorReset = "\033[0m"
	}
	fmt.Fprintf(os.Stderr, "%s%s [%s %s] %s%s\n",
		time.Now().Format("15:04:05.000"), colorStart, s.mod, level, fmt.Sprintf(msg, args...), colorReset)
}

func (s *stderrLogger) Errorf(msg string, args ...interface{}) { s.outputf("ERROR", msg, args...) }
func (s *stderrLogger) Warnf(msg string, args ...interface{})  { s.outputf("WARN", msg, args...) }
func (s *stderrLogger) Infof(msg string, args ...interface{})  { s.outputf("INFO", msg, args...) }
func (s *stderrLogger) Debugf(msg string, args ...interface{}) { s.outputf("DEBUG", msg, args...) }
func (s *stderrLogger) Sub(mod string) waLog.Logger {
	return &stderrLogger{mod: fmt.Sprintf("%s/%s", s.mod, mod), color: s.color, min: s.min}
}
